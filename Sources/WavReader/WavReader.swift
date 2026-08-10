//
//  WavReader.swift
//  WavReader
//
//  Created by Geordie Jay on 03.03.20.
//  Copyright © 2020 flowkey. All rights reserved.
//

import Foundation
import CWavHeader

public struct WavReader: Sequence, Sendable {
    public let formatType: Format
    public let sampleRate: Int
    public let numFrames: Int
    public let numChannels: Int
    public let bitsPerSample: Int
    public let bytesPerSample: Int

    public let bytesPerFrame: Int
    public let numSamples: Int
    public let blockSize: Int // in frames

    fileprivate let bytes: Data
    fileprivate let offsetToWavData: Int

    public enum FormatError: Error {
        case couldNotFindFmtSection
        case couldNotFindDataSection
        case unsupportedFormat(format: Int)
    }

    public enum Format: Sendable {
        case pcm
        case ieeeFloat
    }

    public init(bytes: Data, blockSize: Int = 1024) throws {
        self.blockSize = blockSize

        guard
            let indexOfFormatSection = bytes.firstOccurence(of: "fmt", maxSearchBytes: 2048),
            let fmtChunk = bytes.withUnsafeBytes({ buffer -> FmtChunk? in
                buffer.baseAddress?.advanced(by: indexOfFormatSection).bindMemory(to: FmtChunk.self, capacity: 1).pointee
            })
        else {
            throw FormatError.couldNotFindFmtSection
        }

        switch fmtChunk.formatType {
        case 1: self.formatType = .pcm
        case 3: self.formatType = .ieeeFloat
        default: throw FormatError.unsupportedFormat(format: Int(fmtChunk.formatType))
        }

        sampleRate = Int(fmtChunk.sampleRate)
        numChannels = Int(fmtChunk.channelCount)
        bitsPerSample = Int(fmtChunk.bitsPerSample)
        bytesPerSample = bitsPerSample / 8
        bytesPerFrame = numChannels * bytesPerSample

        guard
            let indexOfDataSection = bytes.firstOccurence(of: "data", maxSearchBytes: 4096),
            let dataChunk = bytes.withUnsafeBytes({ buffer -> DataChunk? in
                buffer.baseAddress?.advanced(by: indexOfDataSection).bindMemory(to: DataChunk.self, capacity: 1).pointee
            })
        else {
            throw FormatError.couldNotFindDataSection
        }

        numFrames = Int(dataChunk.dataSize) / bytesPerFrame
        numSamples = numFrames * numChannels
        offsetToWavData = indexOfDataSection + MemoryLayout<DataChunk>.size

        self.bytes = bytes
    }

    public init(filename: String = "example.wav", blockSize: Int = 1024) throws {
        let wavData = try Data(contentsOf: URL(fileURLWithPath: filename), options: [.mappedIfSafe])
        try self.init(bytes: wavData, blockSize: blockSize)
    }

    /// Reads a slice of mono audio samples (first channel) normalized to [-1, 1].
    ///
    /// Handles negative `beginMilliseconds` (zero-pads start) and `endMilliseconds`
    /// past EOF (zero-pads end). Supports 16-bit, 24-bit PCM and 32-bit float.
    ///
    /// - Parameters:
    ///   - beginMilliseconds: Start time in milliseconds (can be negative for zero-padding).
    ///   - endMilliseconds: End time in milliseconds (can extend past file duration).
    /// - Returns: Mono `[Float]` samples normalized to [-1, 1].
    public func readSlice(beginMilliseconds: Int, endMilliseconds: Int) -> [Float] {
        let beginSample = beginMilliseconds * sampleRate / 1000
        let endSample = endMilliseconds * sampleRate / 1000
        let duration = endSample - beginSample

        var result = [Float](repeating: 0, count: duration)

        let totalFrames = numFrames
        let srcStart = Swift.max(beginSample, 0)
        let srcEnd = Swift.min(endSample, totalFrames)
        let dstStart = Swift.max(-beginSample, 0)

        guard srcStart < srcEnd else { return result }

        let count = srcEnd - srcStart

        bytes.withUnsafeBytes { rawBuffer in
            let byteBuffer = rawBuffer.bindMemory(to: UInt8.self)

            switch (formatType, bytesPerSample) {
            case (.pcm, 2):
                for i in 0..<count {
                    let byteOff = offsetToWavData + (srcStart + i) * bytesPerFrame
                    let lo = UInt16(byteBuffer[byteOff])
                    let hi = UInt16(byteBuffer[byteOff + 1])
                    let raw = Int16(bitPattern: lo | (hi << 8))
                    result[dstStart + i] = Float(raw) / 32768.0
                }
            case (.pcm, 3):
                for i in 0..<count {
                    let byteOff = offsetToWavData + (srcStart + i) * bytesPerFrame
                    let b0 = Int32(byteBuffer[byteOff])
                    let b1 = Int32(byteBuffer[byteOff + 1])
                    let b2 = Int32(Int8(bitPattern: byteBuffer[byteOff + 2]))
                    let sample = (b2 << 16) | (b1 << 8) | b0
                    result[dstStart + i] = Float(sample) / 8388608.0
                }
            case (.ieeeFloat, 4):
                for i in 0..<count {
                    let byteOff = offsetToWavData + (srcStart + i) * bytesPerFrame
                    let bits = UInt32(byteBuffer[byteOff]) |
                               (UInt32(byteBuffer[byteOff + 1]) << 8) |
                               (UInt32(byteBuffer[byteOff + 2]) << 16) |
                               (UInt32(byteBuffer[byteOff + 3]) << 24)
                    result[dstStart + i] = Float(bitPattern: bits)
                }
            default:
                // Unsupported format — return zeros
                break
            }
        }

        return result
    }

    public func makeIterator() -> WavReader.Iterator {
        return Iterator(self)
    }
}

extension WavReader {
    public class Iterator: IteratorProtocol {
        private var floatBuffer: [Float]
        private var wavFile: WavReader

        private var frameIndex = 0

        fileprivate init(_ wavFile: WavReader) {
            self.wavFile = wavFile
            floatBuffer = [Float](repeating: 0.0, count: wavFile.blockSize * wavFile.numChannels)
        }

        public func next() -> [Float]? {
            switch wavFile.formatType {
            case .pcm:
                return getNextPcmBlock()
            case .ieeeFloat:
                switch wavFile.bitsPerSample {
                case 32: return getNextFloatBlock()
                case 64: return getNextDoubleBlock()
                default: fatalError("Unsupported float bit depth: \(wavFile.bitsPerSample)")
                }
            }
        }

        private func getNextFloatBlock() -> [Float]? {
            wavFile.bytes.withUnsafeBytes { bufferPointer in
                let readBuffer = UnsafeBufferPointer(
                    start: bufferPointer.baseAddress!.advanced(by: wavFile.offsetToWavData).assumingMemoryBound(to: Float.self),
                    count: wavFile.numSamples
                )

                // each frame may contain multiple samples
                let framesToRead = Swift.min(wavFile.blockSize, (wavFile.numFrames - frameIndex))
                guard framesToRead > 0 else { return nil }

                let firstSample = frameIndex * wavFile.numChannels
                floatBuffer = readBuffer[firstSample ..< firstSample + (framesToRead * wavFile.numChannels)].map { return Float($0) }
                self.frameIndex += framesToRead
                return floatBuffer
            }
        }

        // XXX: This is a 1:1 copy of the float reader above, but with a Double type
        // We should be able to fix this with some kind of dynamism, but I couldn't figure it out quickly
        private func getNextDoubleBlock() -> [Float]? {
            wavFile.bytes.withUnsafeBytes { bufferPointer in
                let readBuffer = UnsafeBufferPointer(
                    start: bufferPointer.baseAddress!.advanced(by: wavFile.offsetToWavData).assumingMemoryBound(to: Double.self),
                    count: wavFile.numSamples
                )

                // each frame may contain multiple samples
                let framesToRead = Swift.min(wavFile.blockSize, (wavFile.numFrames - frameIndex))
                guard framesToRead > 0 else { return nil }

                let firstSample = frameIndex * wavFile.numChannels
                floatBuffer = readBuffer[firstSample ..< firstSample + (framesToRead * wavFile.numChannels)].map { return Float($0) }
                self.frameIndex += framesToRead
                return floatBuffer
            }
        }

        private func getNextPcmBlock() -> [Float]? {
            // it's cheaper to do multiplication than division, so divide
            // here once and multiply each sample by this number:
            let maxPossibleValue = pow(2.0, Double(wavFile.bitsPerSample) - 1)
            let floatFactor = Double(1.0) / maxPossibleValue
            let bitShiftConst = (32 - wavFile.bitsPerSample)

            var framesRead = 0

            return wavFile.bytes.withUnsafeBytes { bufferPointer in
                let byteBuffer = UnsafeBufferPointer(
                    start: bufferPointer.baseAddress!.advanced(by: wavFile.offsetToWavData).assumingMemoryBound(to: UInt8.self),
                    count: wavFile.numFrames * wavFile.bytesPerFrame
                )


                while frameIndex < wavFile.numFrames {
                    for channel in 0 ..< wavFile.numChannels {
                        // frame:
                        // [               /---- byte
                        //   channel1: [b, b] <---- sample
                        //   channel2: [b, b] <---- sample
                        // ]
                        //
                        let baseByteArrayIndexOfSample = (frameIndex * wavFile.bytesPerFrame) + (channel * wavFile.bytesPerSample)

                        // piece together some bytes starting from the left (bigEndian puts the incoming byte on the far left)
                        // Example for three bytes (24bit PCM):
                        // 1010_1010_0000_0000_0000_0000_0000_0000
                        // 0110_0110_1010_1010_0000_0000_0000_0000
                        // 0111_1111_0110_0110_1010_1010_0000_0000
                        var sample: UInt32 = 0
                        for i in 0 ..< wavFile.bytesPerSample {
                            sample >>= 8
                            sample |= UInt32(byteBuffer[baseByteArrayIndexOfSample + i]).bigEndian
                        }

                        // Shift the bytes we've assembled so they're now sitting on the right
                        // For example: 0000_0000_0111_1111_0110_0110_1010_1010 (from example above).
                        // The const is the number of unfilled bits in our 32bit Int (8 in this example).

                        // We make the Int signed here *before* bit shifting to ensure we carry the sign
                        // bit correctly (otherwise we can end up with values bigger than `maxPossibleValue`)
                        // If we started with   1010_1100_0000_0000_0000_0000_0000_0000 (8 bit input)
                        // our result should be 1111_1111_1111_1111_1111_1111_1010_1100
                        let sampleAsSignedInt = Int32(bitPattern: sample) >> bitShiftConst

                        // We now have the correct little endian representation in the encoded byte order.
                        // Multiplication is faster than division so multiply by our constant factor.
                        // A block holds every channel interleaved, so each frame occupies
                        // `numChannels` slots rather than one.
                        floatBuffer[(framesRead * wavFile.numChannels) + channel] =
                            Float(Double(sampleAsSignedInt) * floatFactor)
                    }

                    framesRead += 1
                    self.frameIndex += 1

                    if framesRead == wavFile.blockSize {
                        return floatBuffer
                    }
                }

                if framesRead > 0 {
                    // We're at EOF but we didn't return the buffer yet
                    // That means the unwritten part of the current buffer
                    // will contain data from the _last_ iteration

                    // Empty the rest of the float buffer, otherwise it
                    // will contain the previous frame's data:
                    ((framesRead * wavFile.numChannels) ..< floatBuffer.count).forEach { sampleIndex in
                        floatBuffer[sampleIndex] = 0.0
                    }

                    return floatBuffer
                }

                return nil
            }
        }
    }
}

fileprivate extension Data {
    /// Search for the first occurence of the given string in our Data's buffer.
    /// Optionally you can provide `maxSearchBytes` which stops the search after reaching the given byte count
    /// This allows us to stop searching the entire Data buffer if the String was not found quickly.
    func firstOccurence(of string: String, maxSearchBytes: Int? = nil) -> Int? {
        let stringLength = string.utf8CString.count - 1
        if stringLength == 0 { return nil }

        let maxSearchBytes = (maxSearchBytes ?? self.count) - stringLength
        if maxSearchBytes <= 0 { return nil }

        return self.withUnsafeBytes { rawBufferPointer -> Int? in
            let buffer = rawBufferPointer.bindMemory(to: CChar.self)

            return string.withCString { stringBuffer in
                buffer.indices.first { index in
                    if index >= maxSearchBytes { return false }

                    for stringIndex in 0 ..< stringLength {
                        if buffer[index + stringIndex] != stringBuffer[stringIndex] {
                            return false
                        }
                    }

                    return true
                }
            }
        }
    }
}
