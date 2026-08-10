//
//  AudioFileReader.swift
//  WavReader
//
//  Copyright © 2026 flowkey. All rights reserved.
//

import Foundation

/// Opens WAV or FLAC without the caller having to know which it got, and presents the surface both
/// readers share: the stream properties, `readSlice`, and block iteration.
///
/// The format is decided by the first four bytes, not the file extension. A corpus that has been
/// through a conversion often carries names that disagree with its contents — a `.wav` holding FLAC
/// after an in-place transcode, or the reverse — and reading the magic makes that harmless instead
/// of a decode failure several layers down.
public enum AudioFileReader: Sequence, Sendable {
    case wav(WavReader)
    case flac(FlacReader)

    public enum FormatError: Error {
        /// The file is shorter than the four bytes that identify a container.
        case fileTooShortToIdentify(String)
        /// The leading bytes are neither `RIFF` nor `fLaC`.
        case unrecognisedContainer(String)
    }

    public init(filename: String, blockSize: Int = 1024) throws {
        switch try AudioFileReader.container(ofFileAt: filename) {
        case .wav:
            self = .wav(try WavReader(filename: filename, blockSize: blockSize))
        case .flac:
            self = .flac(try FlacReader(filename: filename, blockSize: blockSize))
        }
    }

    private enum Container {
        case wav
        case flac
    }

    /// Reads only the leading bytes, so identifying a file costs one short read rather than a map of
    /// the whole thing.
    private static func container(ofFileAt filename: String) throws -> Container {
        guard let handle = FileHandle(forReadingAtPath: filename) else {
            throw FormatError.fileTooShortToIdentify(filename)
        }
        defer { try? handle.close() }

        guard let magic = try handle.read(upToCount: 4), magic.count == 4 else {
            throw FormatError.fileTooShortToIdentify(filename)
        }

        switch Array(magic) {
        case Array("RIFF".utf8): return .wav
        case Array("fLaC".utf8): return .flac
        default: throw FormatError.unrecognisedContainer(filename)
        }
    }

    public var sampleRate: Int {
        switch self {
        case .wav(let reader): return reader.sampleRate
        case .flac(let reader): return reader.sampleRate
        }
    }

    public var numFrames: Int {
        switch self {
        case .wav(let reader): return reader.numFrames
        case .flac(let reader): return reader.numFrames
        }
    }

    public var numChannels: Int {
        switch self {
        case .wav(let reader): return reader.numChannels
        case .flac(let reader): return reader.numChannels
        }
    }

    public var bitsPerSample: Int {
        switch self {
        case .wav(let reader): return reader.bitsPerSample
        case .flac(let reader): return reader.bitsPerSample
        }
    }

    public var numSamples: Int {
        switch self {
        case .wav(let reader): return reader.numSamples
        case .flac(let reader): return reader.numSamples
        }
    }

    public var blockSize: Int {
        switch self {
        case .wav(let reader): return reader.blockSize
        case .flac(let reader): return reader.blockSize
        }
    }

    /// Mono samples (first channel) normalized to [-1, 1], zero-padded wherever the requested span
    /// falls outside the file.
    public func readSlice(beginMilliseconds: Int, endMilliseconds: Int) -> [Float] {
        switch self {
        case .wav(let reader): return reader.readSlice(
            beginMilliseconds: beginMilliseconds, endMilliseconds: endMilliseconds)
        case .flac(let reader): return reader.readSlice(
            beginMilliseconds: beginMilliseconds, endMilliseconds: endMilliseconds)
        }
    }

    public func makeIterator() -> AudioFileReader.Iterator {
        switch self {
        case .wav(let reader): return Iterator(wrapped: reader.makeIterator().next)
        case .flac(let reader): return Iterator(wrapped: reader.makeIterator().next)
        }
    }
}

extension AudioFileReader {
    /// Yields the underlying reader's blocks unchanged: `blockSize` frames with every channel
    /// interleaved, the last one zero-padded to full length.
    ///
    /// Holding the wrapped iterator's `next` keeps that iterator alive for as long as this one, which
    /// matters for FLAC — its iterator owns an open decoder and closes it on deinit.
    public struct Iterator: IteratorProtocol {
        private let wrapped: () -> [Float]?

        fileprivate init(wrapped: @escaping () -> [Float]?) {
            self.wrapped = wrapped
        }

        public func next() -> [Float]? {
            wrapped()
        }
    }
}
