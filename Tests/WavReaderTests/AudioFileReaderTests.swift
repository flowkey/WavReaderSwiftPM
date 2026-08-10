import XCTest
@testable import WavReader

/// FLAC is lossless, so a FLAC encoding of a WAV fixture has to decode back to the very same
/// samples. These compare the two readers against each other on `Tests/Flacs/<name>.flac` and
/// `Tests/Wavs/<name>.wav`, which are the same audio in both containers, and demand exact equality
/// rather than a tolerance — anything less would hide a scaling or endianness mistake, since a
/// half-scaled or byte-swapped decode still correlates with the original.
final class AudioFileReaderTests: XCTestCase {
    /// Fixture pairs: 16- and 24-bit mono, two sample rates. Float WAVs have no FLAC counterpart,
    /// because FLAC stores integer samples only.
    private static let fixtureNames = [
        "16bit-44100",
        "16bit-48000",
        "24bit-44100",
        "24bit-48000",
    ]

    /// The fixtures sit beside the test sources rather than being declared resources, so they are
    /// addressed relative to this file. `Bundle.module` would work under SwiftPM but not in the
    /// CMake build, which compiles these sources without a resource bundle.
    private static var testsDirectory: String {
        (((#filePath as NSString)
            .deletingLastPathComponent as NSString)   // WavReaderTests/
            .deletingLastPathComponent)                // Tests/
    }

    private func wavPath(_ name: String) -> String {
        "\(Self.testsDirectory)/Wavs/\(name).wav"
    }

    private func flacPath(_ name: String) -> String {
        "\(Self.testsDirectory)/Flacs/\(name).flac"
    }

    // MARK: - Stream properties

    func testFlacReportsTheSameStreamPropertiesAsTheWav() throws {
        for name in Self.fixtureNames {
            let wav = try WavReader(filename: wavPath(name))
            let flac = try FlacReader(filename: flacPath(name))

            XCTAssertEqual(flac.sampleRate, wav.sampleRate, "sample rate, \(name)")
            XCTAssertEqual(flac.numChannels, wav.numChannels, "channel count, \(name)")
            XCTAssertEqual(flac.numFrames, wav.numFrames, "frame count, \(name)")
            XCTAssertEqual(flac.bitsPerSample, wav.bitsPerSample, "bit depth, \(name)")
        }
    }

    // MARK: - readSlice

    /// Spans chosen to cover the three things `readSlice` has to get right beyond the ordinary case:
    /// a start before the file (zero-padded head), an end past it (zero-padded tail), and a span
    /// that is entirely outside.
    func testReadSliceAgreesWithTheWavReader() throws {
        let spans = [
            (begin: 0, end: 2000),        // the whole fixture
            (begin: 250, end: 750),       // interior, seek required
            (begin: -300, end: 400),      // zero-padded head
            (begin: 1800, end: 2400),     // zero-padded tail
            (begin: -500, end: -100),     // entirely before the file
            (begin: 5000, end: 5500),     // entirely after the file
            (begin: 1, end: 2),           // a span shorter than one FLAC block
        ]

        for name in Self.fixtureNames {
            let wav = try WavReader(filename: wavPath(name))
            let flac = try FlacReader(filename: flacPath(name))

            for span in spans {
                let fromWav = wav.readSlice(beginMilliseconds: span.begin, endMilliseconds: span.end)
                let fromFlac = flac.readSlice(beginMilliseconds: span.begin, endMilliseconds: span.end)

                XCTAssertEqual(fromFlac.count, fromWav.count, "\(name) \(span): length")
                XCTAssertEqual(fromFlac, fromWav, "\(name) \(span): samples")
            }
        }
    }

    /// Two reads of the same span from one reader must agree. Each `readSlice` opens its own
    /// decoder and seeks, so this is what would catch a decoder left mid-stream between calls.
    func testRepeatedReadSlicesAreIdentical() throws {
        for name in Self.fixtureNames {
            let flac = try FlacReader(filename: flacPath(name))
            let first = flac.readSlice(beginMilliseconds: 400, endMilliseconds: 900)
            let second = flac.readSlice(beginMilliseconds: 400, endMilliseconds: 900)
            XCTAssertEqual(first, second, "\(name): repeated read")
            XCTAssertFalse(first.allSatisfy { $0 == 0 }, "\(name): fixture decoded as silence")
        }
    }

    // MARK: - Block iteration

    func testBlockIterationAgreesWithTheWavReader() throws {
        for name in Self.fixtureNames {
            let wavBlocks = Array(try WavReader(filename: wavPath(name), blockSize: 1024))
            let flacBlocks = Array(try FlacReader(filename: flacPath(name), blockSize: 1024))

            XCTAssertEqual(flacBlocks.count, wavBlocks.count, "\(name): block count")
            for (index, (fromFlac, fromWav)) in zip(flacBlocks, wavBlocks).enumerated() {
                XCTAssertEqual(fromFlac, fromWav, "\(name): block \(index)")
            }
        }
    }

    // MARK: - Format dispatch

    func testAudioFileReaderDispatchesOnTheFileContents() throws {
        for name in Self.fixtureNames {
            switch try AudioFileReader(filename: wavPath(name)) {
            case .wav: break
            case .flac: XCTFail("\(name).wav opened as FLAC")
            }
            switch try AudioFileReader(filename: flacPath(name)) {
            case .flac: break
            case .wav: XCTFail("\(name).flac opened as WAV")
            }
        }
    }

    /// The magic decides the format, so a FLAC file named `.wav` still decodes. This is the case
    /// that makes an in-place corpus conversion survivable rather than a silent failure.
    func testAudioFileReaderIgnoresAMisleadingExtension() throws {
        let name = Self.fixtureNames[0]
        let misnamed = "\(NSTemporaryDirectory())/misnamed-\(name).wav"
        try? FileManager.default.removeItem(atPath: misnamed)
        try FileManager.default.copyItem(atPath: flacPath(name), toPath: misnamed)
        defer { try? FileManager.default.removeItem(atPath: misnamed) }

        let reader = try AudioFileReader(filename: misnamed)
        switch reader {
        case .flac: break
        case .wav: XCTFail("a FLAC file named .wav opened as WAV")
        }

        let throughReader = reader.readSlice(beginMilliseconds: 0, endMilliseconds: 2000)
        let fromWav = try WavReader(filename: wavPath(name))
            .readSlice(beginMilliseconds: 0, endMilliseconds: 2000)
        XCTAssertEqual(throughReader, fromWav)
    }

    func testAudioFileReaderRejectsSomethingThatIsNeither() throws {
        let notAudio = "\(NSTemporaryDirectory())/not-audio.wav"
        try Data("this is not an audio file".utf8).write(to: URL(fileURLWithPath: notAudio))
        defer { try? FileManager.default.removeItem(atPath: notAudio) }

        XCTAssertThrowsError(try AudioFileReader(filename: notAudio)) { error in
            guard case AudioFileReader.FormatError.unrecognisedContainer = error else {
                return XCTFail("expected unrecognisedContainer, got \(error)")
            }
        }
    }

    func testAudioFileReaderForwardsProperties() throws {
        for name in Self.fixtureNames {
            let wav = try WavReader(filename: wavPath(name))
            let reader = try AudioFileReader(filename: flacPath(name))

            XCTAssertEqual(reader.sampleRate, wav.sampleRate, "sample rate, \(name)")
            XCTAssertEqual(reader.numFrames, wav.numFrames, "frame count, \(name)")
            XCTAssertEqual(reader.numChannels, wav.numChannels, "channel count, \(name)")
            XCTAssertEqual(reader.bitsPerSample, wav.bitsPerSample, "bit depth, \(name)")
            XCTAssertEqual(reader.numSamples, wav.numSamples, "sample count, \(name)")
        }
    }

    /// The wrapped iterator owns the open decoder, so this is the case that would catch it being
    /// released while its blocks are still being consumed.
    func testAudioFileReaderIterationOutlivesTheWrappedReader() throws {
        for name in Self.fixtureNames {
            let throughReader = Array(try AudioFileReader(filename: flacPath(name), blockSize: 1024))
            let direct = Array(try WavReader(filename: wavPath(name), blockSize: 1024))
            XCTAssertEqual(throughReader.count, direct.count, "\(name): block count")
            XCTAssertEqual(throughReader, direct, "\(name): blocks")
        }
    }

    static let allTests = [
        ("testFlacReportsTheSameStreamPropertiesAsTheWav", testFlacReportsTheSameStreamPropertiesAsTheWav),
        ("testReadSliceAgreesWithTheWavReader", testReadSliceAgreesWithTheWavReader),
        ("testRepeatedReadSlicesAreIdentical", testRepeatedReadSlicesAreIdentical),
        ("testBlockIterationAgreesWithTheWavReader", testBlockIterationAgreesWithTheWavReader),
        ("testAudioFileReaderDispatchesOnTheFileContents", testAudioFileReaderDispatchesOnTheFileContents),
        ("testAudioFileReaderIgnoresAMisleadingExtension", testAudioFileReaderIgnoresAMisleadingExtension),
        ("testAudioFileReaderRejectsSomethingThatIsNeither", testAudioFileReaderRejectsSomethingThatIsNeither),
        ("testAudioFileReaderForwardsProperties", testAudioFileReaderForwardsProperties),
        ("testAudioFileReaderIterationOutlivesTheWrappedReader", testAudioFileReaderIterationOutlivesTheWrappedReader),
    ]
}
