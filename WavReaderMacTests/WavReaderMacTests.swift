//
//  WavReaderMacTests.swift
//  WavReaderMacTests
//
//  Created by Geordie Jay on 25.03.20.
//  Copyright © 2020 flowkey. All rights reserved.
//

import XCTest
import AVFoundation
@testable import WavReaderMac

class WavReaderTests: XCTestCase {
    let testBundle = Bundle(for: WavReaderTests.self)

    func testSingleBlock() {
        let testFiles = ["16bit-44100", "16bit-48000", "24bit-44100", "24bit-48000", "32bit-44100", "32bit-48000"]
        try! testFiles.forEach { file in
            print(file)
            let url = testBundle.url(forResource: file, withExtension: ".wav")!

            let blockSize = 1024
            let wavReader = try WavReader(
                bytes: Data(contentsOf: url, options: .alwaysMapped),
                blockSize: blockSize
            )

            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(blockSize))!
            try file.read(into: buffer, frameCount: AVAudioFrameCount(blockSize))

            XCTAssertEqual(
                wavReader.makeIterator().next()!,
                Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            )
        }
    }
}
