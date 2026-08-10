//
//  FlacReader.swift
//  WavReader
//
//  Copyright © 2026 flowkey. All rights reserved.
//

import Foundation
import CDrFlac

/// Reads FLAC files with the same surface `WavReader` presents: stream the whole file in
/// fixed-size blocks, or pull an arbitrary time slice out of the middle of it.
///
/// A WAV reader can be a value over memory-mapped bytes because sample `n` sits at a computable
/// offset. FLAC has no such mapping — samples arrive only by decoding frames in order from a
/// starting point — so a decoder is stateful. This type keeps no decoder of its own: it reads
/// STREAMINFO once at init for the properties below, and every read opens its own decoder and
/// closes it again. That makes the reader a `Sendable` value like `WavReader`, safe to hold in a
/// `let` and read from concurrently, at the cost of a file open per `readSlice`. Opening parses
/// the metadata blocks only, which is why that cost stays small next to decoding the slice.
public struct FlacReader: Sequence, Sendable {
    public let sampleRate: Int
    public let numFrames: Int
    public let numChannels: Int
    public let bitsPerSample: Int
    public let bytesPerSample: Int

    public let bytesPerFrame: Int
    public let numSamples: Int
    public let blockSize: Int // in frames

    fileprivate let filename: String

    public enum FormatError: Error {
        /// The file is absent, unreadable, or not FLAC that dr_flac will decode.
        case couldNotOpenFile(String)
    }

    public init(filename: String, blockSize: Int = 1024) throws {
        self.filename = filename
        self.blockSize = blockSize

        guard let decoder = drflac_open_file(filename, nil) else {
            throw FormatError.couldNotOpenFile(filename)
        }
        defer { drflac_close(decoder) }

        sampleRate = Int(decoder.pointee.sampleRate)
        numChannels = Int(decoder.pointee.channels)
        bitsPerSample = Int(decoder.pointee.bitsPerSample)
        bytesPerSample = bitsPerSample / 8
        bytesPerFrame = numChannels * bytesPerSample
        numFrames = Int(decoder.pointee.totalPCMFrameCount)
        numSamples = numFrames * numChannels
    }

    /// Reads a slice of mono audio samples (first channel) normalized to [-1, 1].
    ///
    /// Handles negative `beginMilliseconds` (zero-pads start) and `endMilliseconds`
    /// past EOF (zero-pads end), so the returned array always spans the requested duration.
    ///
    /// - Parameters:
    ///   - beginMilliseconds: Start time in milliseconds (can be negative for zero-padding).
    ///   - endMilliseconds: End time in milliseconds (can extend past file duration).
    /// - Returns: Mono `[Float]` samples normalized to [-1, 1].
    public func readSlice(beginMilliseconds: Int, endMilliseconds: Int) -> [Float] {
        let beginSample = beginMilliseconds * sampleRate / 1000
        let endSample = endMilliseconds * sampleRate / 1000
        let duration = endSample - beginSample

        var result = [Float](repeating: 0, count: Swift.max(duration, 0))

        let sourceStart = Swift.max(beginSample, 0)
        let sourceEnd = Swift.min(endSample, numFrames)
        let destinationStart = Swift.max(-beginSample, 0)

        guard sourceStart < sourceEnd, destinationStart < result.count else { return result }

        let count = Swift.min(sourceEnd - sourceStart, result.count - destinationStart)

        guard let decoder = drflac_open_file(filename, nil) else { return result }
        defer { drflac_close(decoder) }

        // A seek past a seekpoint still has to decode forward to the target frame, so this is the
        // one place the format costs more than a memory-mapped WAV. Encoding with a dense seektable
        // is what keeps that bounded.
        guard drflac_seek_to_pcm_frame(decoder, drflac_uint64(sourceStart)) != 0 else { return result }

        // Every channel of every frame arrives interleaved whether or not the caller wants them, so
        // a stereo file decodes twice the samples this returns.
        var interleaved = [Float](repeating: 0, count: count * numChannels)
        let framesRead = interleaved.withUnsafeMutableBufferPointer { buffer in
            Int(drflac_read_pcm_frames_f32(decoder, drflac_uint64(count), buffer.baseAddress))
        }

        for frameIndex in 0 ..< framesRead {
            result[destinationStart + frameIndex] = interleaved[frameIndex * numChannels]
        }

        return result
    }

    public func makeIterator() -> FlacReader.Iterator {
        return Iterator(self)
    }
}

extension FlacReader {
    /// Streams the file forwards in `blockSize`-frame blocks, every channel interleaved.
    ///
    /// Unlike `readSlice` this holds one decoder open for its whole life, because decoding
    /// consecutive blocks from a single stream is the case FLAC is cheap at. It is a class with
    /// mutable position, so — like `WavReader.Iterator` — one iterator belongs to one consumer.
    public final class Iterator: IteratorProtocol {
        private var floatBuffer: [Float]
        private let flacFile: FlacReader
        private let decoder: UnsafeMutablePointer<drflac>?

        private var frameIndex = 0

        fileprivate init(_ flacFile: FlacReader) {
            self.flacFile = flacFile
            self.decoder = drflac_open_file(flacFile.filename, nil)
            floatBuffer = [Float](repeating: 0.0, count: flacFile.blockSize * flacFile.numChannels)
        }

        deinit {
            if let decoder { drflac_close(decoder) }
        }

        public func next() -> [Float]? {
            guard let decoder else { return nil }

            let framesToRead = Swift.min(flacFile.blockSize, flacFile.numFrames - frameIndex)
            guard framesToRead > 0 else { return nil }

            let framesRead = floatBuffer.withUnsafeMutableBufferPointer { buffer in
                Int(drflac_read_pcm_frames_f32(decoder, drflac_uint64(framesToRead), buffer.baseAddress))
            }
            guard framesRead > 0 else { return nil }
            frameIndex += framesRead

            // A short final block leaves the tail of the buffer holding the previous block's
            // samples, so it is cleared rather than handed back as audio.
            if framesRead < flacFile.blockSize {
                for sampleIndex in (framesRead * flacFile.numChannels) ..< floatBuffer.count {
                    floatBuffer[sampleIndex] = 0.0
                }
            }

            return floatBuffer
        }
    }
}
