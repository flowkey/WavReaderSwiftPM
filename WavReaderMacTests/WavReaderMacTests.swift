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

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    let testBundle = Bundle(for: WavReaderTests.self)

    func testExample() {
        let urls = ["16bit-44100", "16bit-48000", "24bit-44100", "24bit-48000", "32bit-44100", "32bit-48000"].compactMap {
            return testBundle.url(forResource: $0, withExtension: ".wav")
        }

        try! urls.forEach { url in
            print(url)

            let blockSize = 1024
            let wavReader = try WavReader(bytes: Data(contentsOf: url, options: .alwaysMapped), blockSize: blockSize)


            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
            assert(file.fileFormat.channelCount == 1)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(blockSize))!
            try file.read(into: buffer, frameCount: AVAudioFrameCount(blockSize))

            let array = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))

            XCTAssertEqual(array, wavReader.makeIterator().next()!)
        }
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
