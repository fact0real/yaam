import Foundation
import FT8Codec

/// FT8Codec keeps at most 50 distinct decodes per window (FT8808_MAX_DECODED in the
/// ft8-808 shim). Asked for more, its duplicate check never ends once a 51st distinct
/// message is decoded, so a busy 13.5 s window must not be decoded with a larger limit.
@main
struct WebSDRDecodeLimitRegression {
    static let codecTableSize = 50
    static let deadlineSeconds = 15.0

    final class Outcome: @unchecked Sendable {
        var detectionCount = 0
        var texts = Set<String>()
    }

    static func main() throws {
        var failures: [String] = []

        // 1. A window with more distinct signals than the codec can store must return.
        let signalCount = 60
        var texts = Set<String>()
        var noise = Noise(state: 9)
        let rate = 12_000
        var audio = [Float](repeating: 0, count: 30 * rate)
        for i in 0..<audio.count { audio[i] = noise.next() * 0.002 }
        for i in 0..<signalCount {
            let text = "CQ K\(i % 10)\(letter(i / 10))\(letter(i)) FN42"
            texts.insert(text)
            let tones = try FT8Codec.encode(text)
            let signal = FT8Codec.synthesize(tones: tones,
                                             baseFrequencyHz: 250 + Float(i) * 2_700 / Float(signalCount))
            for (k, sample) in signal.enumerated() where 6_200 + k < audio.count {
                audio[6_200 + k] += sample * 1.5 / Float(signalCount)
            }
        }
        precondition(texts.count == signalCount, "Every synthesised message must be distinct")

        let outcome = Outcome()
        let finished = DispatchSemaphore(value: 0)
        let first = Array(audio[0..<(15 * rate)])
        let second = Array(audio[(15 * rate)...])
        Thread.detachNewThread {
            let detections = WebSDRCycleDecoder.decode(previous: first, next: second, sampleRate: rate)
            outcome.detectionCount = detections.count
            outcome.texts = Set(detections.map(\.message.text))
            finished.signal()
        }
        if finished.wait(timeout: .now() + deadlineSeconds) == .timedOut {
            failures.append("WebSDRCycleDecoder.decode did not return within \(Int(deadlineSeconds)) s " +
                            "for a window with \(signalCount) distinct FT8 signals")
        } else {
            if outcome.detectionCount < codecTableSize {
                failures.append("A busy window must still decode up to the limit " +
                                "(\(outcome.detectionCount) of \(signalCount) detections)")
            }
            if !outcome.texts.isSubset(of: texts) {
                failures.append("Decoded text that was never transmitted")
            }
        }

        // 2. Both WebSDR call sites must pass a limit the codec can honour. The monitor
        //    cannot be compiled on its own, so its call site is checked in the source.
        //    Failure messages name the scanned directory as #filePath spells it, so a build
        //    with relative paths prints a relative directory.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let shownRoot = ((#filePath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let scanned = shownRoot.isEmpty ? "YAAM" : "\(shownRoot)/YAAM"
        func sourceFailure(_ message: String) {
            failures.append("\(message) (source scan of \(scanned))")
        }
        func source(_ name: String) -> String {
            let url = root.appendingPathComponent("YAAM/\(name)")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                preconditionFailure("Cannot read \(scanned)/\(name); run from the repository root")
            }
            return text
        }
        func matches(_ pattern: String, in text: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, range: range).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            }
        }
        let decoderSource = source("WebSDRCycleDecoder.swift")
        let declared = matches(#"maxMessagesPerWindow\s*=\s*(\d+)"#, in: decoderSource).compactMap { Int($0) }
        if declared.count != 1 {
            sourceFailure("WebSDRCycleDecoder.maxMessagesPerWindow must be declared once (found \(declared.count))")
        } else if declared[0] > codecTableSize {
            sourceFailure("maxMessagesPerWindow is \(declared[0]); FT8Codec stores only \(codecTableSize)")
        }
        //    The argument is read up to the closing parenthesis or the next comma and must be
        //    the shared constant exactly, so "maxMessagesPerWindow + 14" is rejected too.
        let sharedLimit = ["maxMessagesPerWindow", "WebSDRCycleDecoder.maxMessagesPerWindow"]
        for name in ["WebSDRCycleDecoder.swift", "WebSDRFT8Monitor.swift"] {
            let arguments = matches(#"maxMessages:\s*([^,)]+)"#, in: source(name))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if arguments.isEmpty {
                sourceFailure("\(name): no FT8Codec.decode call with maxMessages found")
            }
            for argument in arguments where !sharedLimit.contains(argument) {
                sourceFailure("\(name): maxMessages is \"\(argument)\"; use WebSDRCycleDecoder.maxMessagesPerWindow as it is")
            }
        }

        if failures.isEmpty {
            print("WebSDR decode limit regression passed: \(signalCount) signals in one window " +
                  "returned \(outcome.detectionCount) detections, both call sites use the shared limit")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    static func letter(_ k: Int) -> String {
        String(UnicodeScalar(UInt8(65 + k % 26)))
    }

    struct Noise {
        var state: UInt64
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF) * 2 - 1
        }
    }
}
