import Foundation
import FT8Codec
import FT8808Engine

@main
struct WebSDRReceiveRegression {
    static func main() throws {
        let first = try FT8Codec.transmitAudio("CQ K1ABC FN42", baseFrequencyHz: 1_000)
        let second = try FT8Codec.transmitAudio("CQ W9XYZ EN50", baseFrequencyHz: 1_500)
        let joined = first + second
        let split = 12 * 12_000
        let detections = WebSDRCycleDecoder.decode(previous: Array(joined[..<split]),
                                                   next: Array(joined[split...]),
                                                   sampleRate: 12_000)
        precondition(detections.contains { $0.message.text == "CQ K1ABC FN42" })
        precondition(detections.contains { $0.message.text == "CQ W9XYZ EN50" })
        let firstCycle = detections.first { $0.message.text == "CQ K1ABC FN42" }!.cycleOffsetSeconds
        let secondCycle = detections.first { $0.message.text == "CQ W9XYZ EN50" }!.cycleOffsetSeconds
        precondition(abs(secondCycle - firstCycle - 15) < 2,
                     "The two adjacent FT8 cycles must stay distinct")

        let concurrent = try FT8Codec.transmitAudio("CQ W9XYZ EN50", baseFrequencyHz: 2_000)
        let mixed = zip(first, concurrent).map { ($0 + $1) * 0.5 }
        let paired = WebSDRCycleDecoder.decode(previous: Array(mixed.prefix(split)),
                                               next: Array(mixed.dropFirst(split)),
                                               sampleRate: 12_000)
        if let a = paired.first(where: { $0.message.text == "CQ K1ABC FN42" }),
           let b = paired.first(where: { $0.message.text == "CQ W9XYZ EN50" }) {
            precondition(a.cycleOffsetSeconds == b.cycleOffsetSeconds,
                         "Messages within one FT8 cycle must share its time label")
        } else {
            preconditionFailure("Both simultaneous FT8 messages must decode")
        }

        var timeline = WebSDRAudioTimeline()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var slots: [AudioSlot] = []
        for second in 1...30 {
            let chunk = Array(repeating: Float(0.1), count: 12_000)
            let result = timeline.append(chunk, endedAt: base.addingTimeInterval(Double(second)))
            precondition(result.interruptionSeconds == nil)
            slots += result.slots
        }
        precondition(slots.count == 2)
        precondition(slots[0].startTime == base)
        precondition(slots[1].startTime == base.addingTimeInterval(15))

        let interruption = timeline.append(Array(repeating: Float(0.1), count: 12_000),
                                           endedAt: base.addingTimeInterval(41))
        precondition(interruption.interruptionSeconds != nil)
        precondition(interruption.slots.isEmpty,
                     "A missing audio span must never become a complete FT8 slot")
        print("WebSDR receive regression passed: both cycles, shared cycle time, gap detection")
    }
}
