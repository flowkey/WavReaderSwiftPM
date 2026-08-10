import Foundation
import WavReader

// Compares two audio files through `AudioFileReader` and reports whether they are the same audio.
//
// This exists to gate a corpus conversion. `flac -t` and a PCM hash comparison already establish
// that a FLAC encoding is lossless, but they establish it about the reference decoder, not about the
// reader that will actually train on the file. A mistake in normalisation, channel interleaving,
// frame accounting or seeking would leave the reference checks green and still feed the model wrong
// audio, so this compares what our own code reads, and it compares samples rather than a summary.
//
//   audio-file-compare <reference> <candidate> [--quiet]
//
// Exits 0 when every sample agrees, 1 on any disagreement, 2 when a file could not be read.

struct ComparisonFailure: Error, CustomStringConvertible {
    let description: String
}

let arguments = Array(CommandLine.arguments.dropFirst())
let quiet = arguments.contains("--quiet")
let paths = arguments.filter { !$0.hasPrefix("--") }

guard paths.count == 2 else {
    FileHandle.standardError.write(Data(
        "usage: audio-file-compare <reference> <candidate> [--quiet]\n".utf8))
    exit(2)
}

let referencePath = paths[0]
let candidatePath = paths[1]

func report(_ message: String) {
    if !quiet { print(message) }
}

func failures(reference: AudioFileReader, candidate: AudioFileReader) -> [String] {
    var failures = [String]()

    func compare<T: Equatable>(_ name: String, _ lhs: T, _ rhs: T) {
        if lhs != rhs { failures.append("\(name): reference \(lhs), candidate \(rhs)") }
    }

    compare("sampleRate", reference.sampleRate, candidate.sampleRate)
    compare("numChannels", reference.numChannels, candidate.numChannels)
    compare("numFrames", reference.numFrames, candidate.numFrames)
    compare("numSamples", reference.numSamples, candidate.numSamples)

    // Anything below this compares sample values, which is meaningless across differing geometry.
    guard failures.isEmpty else { return failures }

    // Block iteration: the streaming path, every channel interleaved. This is what catches a channel
    // ordering or interleaving mistake, which a mono corpus would otherwise never expose.
    var blockIndex = 0
    let referenceIterator = reference.makeIterator()
    let candidateIterator = candidate.makeIterator()
    var totalSamplesCompared = 0
    while true {
        let referenceBlock = referenceIterator.next()
        let candidateBlock = candidateIterator.next()
        if referenceBlock == nil && candidateBlock == nil { break }
        guard let referenceBlock else {
            failures.append("candidate has more blocks than reference (at block \(blockIndex))")
            break
        }
        guard let candidateBlock else {
            failures.append("reference has more blocks than candidate (at block \(blockIndex))")
            break
        }
        if referenceBlock.count != candidateBlock.count {
            failures.append(
                "block \(blockIndex) length: reference \(referenceBlock.count), candidate \(candidateBlock.count)")
            break
        }
        if referenceBlock != candidateBlock {
            let firstDisagreement = zip(referenceBlock, candidateBlock)
                .enumerated().first { $0.element.0 != $0.element.1 }
            let detail = firstDisagreement.map { position, samples in
                "sample \(position): reference \(samples.0), candidate \(samples.1)"
            } ?? "unknown position"
            failures.append("block \(blockIndex) samples differ (\(detail))")
            break
        }
        totalSamplesCompared += referenceBlock.count
        blockIndex += 1
    }

    // The random-access path, which decodes from a seek rather than from the start of the stream. A
    // seek that lands a frame early would agree block-for-block above and disagree here.
    let durationMilliseconds = reference.numFrames * 1000 / max(reference.sampleRate, 1)
    var spans = [(begin: 0, end: durationMilliseconds)]
    if durationMilliseconds > 4 {
        let quarter = durationMilliseconds / 4
        spans.append((begin: quarter, end: quarter * 2))
        spans.append((begin: quarter * 3, end: durationMilliseconds + quarter))
        spans.append((begin: -quarter, end: quarter))
    }
    for span in spans {
        let fromReference = reference.readSlice(
            beginMilliseconds: span.begin, endMilliseconds: span.end)
        let fromCandidate = candidate.readSlice(
            beginMilliseconds: span.begin, endMilliseconds: span.end)
        if fromReference.count != fromCandidate.count {
            failures.append(
                "slice \(span.begin)..\(span.end)ms length: reference \(fromReference.count), candidate \(fromCandidate.count)")
            continue
        }
        if fromReference != fromCandidate {
            let disagreements = zip(fromReference, fromCandidate).filter { $0 != $1 }.count
            failures.append(
                "slice \(span.begin)..\(span.end)ms: \(disagreements) of \(fromReference.count) samples differ")
        }
    }

    if totalSamplesCompared == 0 {
        failures.append("no samples were compared — both files decoded as empty")
    }

    return failures
}

do {
    let reference = try AudioFileReader(filename: referencePath)
    let candidate = try AudioFileReader(filename: candidatePath)

    let problems = failures(reference: reference, candidate: candidate)

    if problems.isEmpty {
        report("""
        OK  \((referencePath as NSString).lastPathComponent) == \((candidatePath as NSString).lastPathComponent)
            \(reference.sampleRate) Hz, \(reference.numChannels) ch, \
        \(reference.numFrames) frames, \(reference.bitsPerSample)-bit
        """)
        exit(0)
    }

    FileHandle.standardError.write(Data("""
    MISMATCH  \(referencePath)
              \(candidatePath)
    \(problems.map { "          - \($0)" }.joined(separator: "\n"))

    """.utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("ERROR  could not read: \(error)\n".utf8))
    exit(2)
}
