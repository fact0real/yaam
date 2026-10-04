import Foundation
import FT8Codec

/// Decodes every FT8 cycle covered by two adjacent WebSDR recordings.
/// FT8Codec decodes only the first slot of a multi-slot buffer, so each
/// candidate 13.5-second window must be passed to it separately.
enum WebSDRCycleDecoder {
    struct Detection {
        let message: FT8Message
        /// Seconds after the beginning of the first recording's audio.
        let audioOffsetSeconds: Double
        /// Common onset for all signals decoded in the same FT8 cycle.
        let cycleOffsetSeconds: Double
        let signalLevelDbFS: Double?
    }

    nonisolated static func decode(previous: [Float], next: [Float], sampleRate rate: Int) -> [Detection] {
        guard rate > 0 else { return [] }
        let joined = previous + next
        let windowCount = Int(13.5 * Double(rate))
        guard joined.count >= windowCount else { return [] }
        guard joined.contains(where: { abs($0) > 0.000_01 }) else { return [] }
        let maxStart = joined.count - windowCount
        let step = max(1, rate / 2)
        var detections: [Detection] = []
        for start in stride(from: 0, through: maxStart, by: step) {
            if Task<Never, Never>.isCancelled { return [] }
            let window = Array(joined[start..<(start + windowCount)])
            guard let messages = try? FT8Codec.decode(samples: window, sampleRate: rate,
                                                     protocol: .ft8, maxMessages: 64) else { continue }
            for message in messages {
                let offset = Double(start) / Double(rate) + Double(message.timeSeconds)
                guard offset >= -0.5, offset <= Double(joined.count) / Double(rate) else { continue }
                if let prior = detections.firstIndex(where: {
                    $0.message.text == message.text &&
                    abs($0.message.frequencyHz - message.frequencyHz) <= 5 &&
                    abs($0.audioOffsetSeconds - offset) < 6
                }) {
                    if message.score > detections[prior].message.score {
                        detections[prior] = Detection(message: message,
                                                      audioOffsetSeconds: offset,
                                                      cycleOffsetSeconds: offset,
                                                      signalLevelDbFS: nil)
                    }
                } else {
                    detections.append(Detection(message: message,
                                                audioOffsetSeconds: offset,
                                                cycleOffsetSeconds: offset,
                                                signalLevelDbFS: nil))
                }
            }
        }
        let sorted = detections.sorted { $0.audioOffsetSeconds < $1.audioOffsetSeconds }
        guard !sorted.isEmpty else { return [] }
        var grouped: [Detection] = []
        var group: [Detection] = []
        func flush() {
            guard !group.isEmpty else { return }
            let times = group.map(\.audioOffsetSeconds).sorted()
            let onset = times[times.count / 2]
            grouped += group.map {
                Detection(message: $0.message,
                          audioOffsetSeconds: $0.audioOffsetSeconds,
                          cycleOffsetSeconds: onset,
                          signalLevelDbFS: WebSDRSignalLevel.estimate(
                            samples: joined, sampleRate: rate,
                            onsetSeconds: $0.audioOffsetSeconds,
                            frequencyHz: $0.message.frequencyHz))
            }
            group.removeAll()
        }
        for detection in sorted {
            if let last = group.last,
               detection.audioOffsetSeconds - last.audioOffsetSeconds > 4.0 {
                flush()
            }
            group.append(detection)
        }
        flush()
        return grouped
    }
}

enum WebSDRSlotTime {
    /// Receive-side slot estimate. A remote SDR may have an unknown whole-slot delay.
    static func nearestBoundary(to observedAt: Date) -> Date {
        let index = (observedAt.timeIntervalSince1970 / 15).rounded()
        return Date(timeIntervalSince1970: index * 15)
    }

    static func isEven(_ slot: Date) -> Bool {
        Int((slot.timeIntervalSince1970 / 15).rounded()).isMultiple(of: 2)
    }
}
