//
//  WavReader.swift
//  WavReader
//
//  Created by Geordie Jay on 03.03.20.
//  Copyright © 2020 flowkey. All rights reserved.
//

import Foundation
import CWavHeader

public struct WavReader: Sequence {
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

    public init(bytes: Data, blockSize: Int = 1024) throws {
        self.blockSize = blockSize

        guard
            let indexOfFormatSection = bytes.firstOccurence(of: "fmt", maxSearchBytes: 512),
            let fmtChunk = bytes.withUnsafeBytes({ buffer -> FmtChunk? in
                buffer.baseAddress?.advanced(by: indexOfFormatSection).bindMemory(to: FmtChunk.self, capacity: 1).pointee
            })
            else {
            preconditionFailure("Invalid wav header: could not find fmt section")
        }

        sampleRate = Int(fmtChunk.sampleRate)
        numChannels = Int(fmtChunk.channelCount)
        bitsPerSample = Int(fmtChunk.bitsPerSample)
        bytesPerSample = bitsPerSample / 8
        bytesPerFrame = numChannels * bytesPerSample

        guard
            let indexOfDataSection = bytes.firstOccurence(of: "data", maxSearchBytes: 512),
            let dataChunk = bytes.withUnsafeBytes({ buffer -> DataChunk? in
                buffer.baseAddress?.advanced(by: indexOfDataSection).bindMemory(to: DataChunk.self, capacity: 1).pointee
            })
            else {
            preconditionFailure("Invalid wav header: could not find data section")
        }

        numFrames = Int(dataChunk.dataSize) / bytesPerFrame
        numSamples = numFrames * numChannels
        offsetToWavData = indexOfDataSection + MemoryLayout<DataChunk>.size

        self.bytes = bytes
        precondition(bitsPerSample == 16, "The algo currently only supports 16bit")
    }

    public init(filename: String = "example.wav", blockSize: Int = 1024) throws {
        let wavData = try Data(contentsOf: URL(fileURLWithPath: filename), options: [.mappedIfSafe])
        try self.init(bytes: wavData, blockSize: blockSize)
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
            let offsetToWavData = wavFile.offsetToWavData

            // it's cheaper to do multiplication than division, so divide
            // here once and multiply each sample by this number:
            let floatFactor = Float(1.0) / Float(Int16.max)

            var framesRead = 0

            return wavFile.bytes.withUnsafeBytes { bufferPointer in
                let int16buffer = UnsafeBufferPointer<Int16>(
                    start: bufferPointer.baseAddress!.advanced(by: offsetToWavData).assumingMemoryBound(to: Int16.self),
                    count: wavFile.numSamples
                )

                while frameIndex < wavFile.numFrames {
                    for channel in 0 ..< wavFile.numChannels {
                        let dataArrayIndex = frameIndex + channel
                        let sample = int16buffer[dataArrayIndex]
                        floatBuffer[framesRead] = Float(sample) * floatFactor
                    }

                    framesRead += 1
                    self.frameIndex += 1

                    if framesRead == wavFile.blockSize {
                        return floatBuffer
                    }
                }

                if framesRead > 0 {
                    // We're at EOF

                    // Empty the rest of the float buffer, otherwise it
                    // will contain the previous frame's data:
                    (framesRead ..< wavFile.blockSize).forEach { i in
                        floatBuffer[i] = 0.0
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
