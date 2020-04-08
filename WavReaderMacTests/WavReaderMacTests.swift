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
    func testSingleBlock16Bit44100() throws {
        try runTestOnSingleBlock("16bit-44100")
    }

    func testSingleBlock16Bit48000() throws {
        try runTestOnSingleBlock("16bit-48000")
    }

    func testSingleBlock24Bit44100() throws {
        try runTestOnSingleBlock("24bit-44100")
    }

    func testSingleBlock24Bit48000() throws {
        try runTestOnSingleBlock("24bit-48000")
    }

    func testSingleBlock32Bit44100() throws {
        try runTestOnSingleBlock("32bit-44100")
    }

    func testSingleBlock32Bit48000() throws {
        try runTestOnSingleBlock("32bit-48000")
    }
}

func runTestOnSingleBlock(_ filename: String) throws {
    let testBundle = Bundle(for: WavReaderTests.self)
    let url = testBundle.url(forResource: filename, withExtension: ".wav")!

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
