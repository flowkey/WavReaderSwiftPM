import Foundation
import XCTest
@testable import WavReader

/// `WAVE_FORMAT_EXTENSIBLE` states the real encoding in its extension rather than in `formatType`,
/// and multichannel recordings are routinely written that way — every WAV in the RWCP
/// impulse-response corpus is, 16 or 30 channels of ordinary 16-bit PCM. Rejecting the container
/// rejected files whose samples this reader can already decode.
final class ExtensibleFormatTests: XCTestCase {
    /// A minimal extensible file, built in code rather than checked in so the test says what the
    /// bytes mean and depends on no corpus.
    private func extensibleWav(
        channels: UInt16, bitsPerSample: UInt16, subFormatTag: UInt16,
        extensionSize: UInt16 = 22, frames: Int = 4
    ) -> Data {
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

        let bytesPerFrame = Int(channels) * Int(bitsPerSample) / 8

        var fmt = Data("fmt ".utf8)
        fmt.append(le32(UInt32(16 + 2 + Int(extensionSize))))
        fmt.append(le16(0xFFFE))
        fmt.append(le16(channels))
        fmt.append(le32(16000))
        fmt.append(le32(UInt32(16000 * bytesPerFrame)))
        fmt.append(le16(UInt16(bytesPerFrame)))
        fmt.append(le16(bitsPerSample))
        fmt.append(le16(extensionSize))                 // cbSize
        fmt.append(le16(bitsPerSample))                 // validBitsPerSample
        fmt.append(le32(0))                             // channelMask
        fmt.append(le16(subFormatTag))                  // SubFormat GUID, first two bytes
        fmt.append(Data([0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00,
                         0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]))   // fixed KSDATAFORMAT suffix

        var data = Data("data".utf8)
        data.append(le32(UInt32(frames * bytesPerFrame)))
        data.append(Data(repeating: 0, count: frames * bytesPerFrame))

        var riff = Data("RIFF".utf8)
        riff.append(le32(UInt32(4 + fmt.count + data.count)))
        riff.append(Data("WAVE".utf8))
        return riff + fmt + data
    }

    /// 30 channels is the widest form in the RWCP corpus, and the one that used to throw.
    func testExtensiblePCMIsReadRatherThanRejected() throws {
        let reader = try WavReader(bytes: extensibleWav(
            channels: 30, bitsPerSample: 16, subFormatTag: 1))
        XCTAssertEqual(reader.numChannels, 30)
        XCTAssertEqual(reader.sampleRate, 16000)
        XCTAssertEqual(reader.bitsPerSample, 16)
    }

    func testExtensibleFloatIsReadRatherThanRejected() throws {
        let reader = try WavReader(bytes: extensibleWav(
            channels: 2, bitsPerSample: 32, subFormatTag: 3))
        XCTAssertEqual(reader.numChannels, 2)
    }

    /// The container is understood; the encoding inside it is not. Accepting it would decode noise.
    func testExtensibleWithAnUnknownSubFormatIsStillRejected() {
        XCTAssertThrowsError(try WavReader(bytes: extensibleWav(
            channels: 2, bitsPerSample: 16, subFormatTag: 0x0055)))
    }

    /// `cbSize` too small for the 22-byte extension: the SubFormat bytes are not there to read.
    func testExtensibleWithNoRoomForTheGUIDIsRejected() {
        XCTAssertThrowsError(try WavReader(bytes: extensibleWav(
            channels: 2, bitsPerSample: 16, subFormatTag: 1, extensionSize: 0)))
    }
}
