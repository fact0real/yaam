import Foundation
import FT8Codec

nonisolated struct FT8StationDetection: Sendable {
    let message: FT8Message
    let timeCorrection: Float
}

nonisolated enum FT8StationDecoder {
    /// Optional extra timing alignments retain every standard-pass result.
    /// This is bounded timing diversity, not WSJT-X AP or signal subtraction.
    static func decode(samples: [Float], sampleRate: Int, protocol proto: FT8Protocol,
                       expanded: Bool) throws -> [FT8StationDetection] {
        let offsets: [Double] = expanded ? (proto == .ft4 ? [0, 0.006, 0.012] : [0, 0.02, 0.04]) : [0]
        var results: [FT8StationDetection] = []
        for offset in offsets {
            try Task.checkCancellation()
            let skipped = Int((offset * Double(sampleRate)).rounded())
            guard skipped < samples.count else { continue }
            let input = skipped == 0 ? samples : Array(samples.dropFirst(skipped)) + [Float](repeating: 0, count: skipped)
            // The native decoder owns a 50-entry hash table; never exceed it.
            let messages = try FT8Codec.decode(samples: input, sampleRate: sampleRate, protocol: proto, maxMessages: 50)
            for message in messages {
                guard !results.contains(where: {
                    $0.message.text == message.text && abs($0.message.frequencyHz - message.frequencyHz) < 6
                }) else { continue }
                results.append(.init(message: message, timeCorrection: Float(offset)))
            }
        }
        return results
    }
}
