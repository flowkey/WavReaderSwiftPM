//
//  WavFile.swift
//  readWav
//
//  Created by Geordie Jay on 03.03.20.
//  Copyright © 2020 flowkey. All rights reserved.
//

import Foundation
import CWavHeader

public struct WavFile: Sequence {
    let numFrames: Int
    let numChannels: Int
    let bitsPerSample: Int
    let bytesPerSample: Int

    let bytesPerFrame: Int
    let numSamples: Int

    private(set) var bytes: Data
    let blockSize: Int // in frames

    init(bytes: Data, blockSize: Int = 1024) throws {
        self.blockSize = blockSize

        let header = bytes.withUnsafeBytes { buffer -> WavHeader in
            return buffer.bindMemory(to: WavHeader.self)[0]
        }

        print(header)

        numChannels = Int(header.channels)
        bitsPerSample = Int(header.bits_per_sample)
        bytesPerSample = bitsPerSample / 8

        bytesPerFrame = numChannels * bytesPerSample
        numFrames = Int(header.data_size) / bytesPerFrame
        numSamples = numFrames * numChannels

        self.bytes = bytes
        precondition(bitsPerSample == 16, "The algo currently only supports 16bit")
    }

    init(filename: String = "example.wav", blockSize: Int = 1024) throws {
        let wavData = try Data(contentsOf: URL(fileURLWithPath: filename), options: [.mappedIfSafe])
        try self.init(bytes: wavData, blockSize: blockSize)
    }

    public func makeIterator() -> WavFileIterator {
        return WavFileIterator(self)
    }
}

public class WavFileIterator: IteratorProtocol {
    private var floatBuffer: [Float]
    private var wavFile: WavFile

    private var frameIndex = 0

    fileprivate init(_ wavFile: WavFile) {
        self.wavFile = wavFile
        floatBuffer = [Float](repeating: 0.0, count: wavFile.blockSize * wavFile.numChannels)
    }

    public func next() -> [Float]? {
        // it's cheaper to do multiplication than division, so divide
        // here once and multiply each sample by this number:
        let floatFactor = Float(1.0) / Float(Int16.max)
        let offsetToWavData = MemoryLayout<WavHeader>.size

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
