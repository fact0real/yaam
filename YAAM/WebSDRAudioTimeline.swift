import Foundation
import FT8808Engine

/// Keeps WebAudio samples on one wall-clock timeline. A browser recorder may
/// return far fewer samples than the number of seconds it was open; the live
/// audio callback instead exposes those gaps so they cannot shift FT8 cycles.
struct WebSDRAudioTimeline {
    struct AppendResult {
        let slots: [AudioSlot]
        let interruptionSeconds: Double?
    }

    private let sampleRate = 12_000
    private let slotSamples = 12_000 * 15
    private var buffer: [Float] = []
    private var bufferStart: Date?
    private var expectedEnd: Date?
    private var nextIndex = 0

    mutating func append(_ samples: [Float], endedAt: Date) -> AppendResult {
        guard !samples.isEmpty else { return AppendResult(slots: [], interruptionSeconds: nil) }
        let duration = Double(samples.count) / Double(sampleRate)
        let start = endedAt.addingTimeInterval(-duration)
        var interruption: Double?
        if let expectedEnd {
            let gap = start.timeIntervalSince(expectedEnd)
            if gap > 0.45 {
                interruption = gap
                if gap > 3 {
                    buffer.removeAll(keepingCapacity: true)
                    bufferStart = start
                } else {
                    buffer.append(contentsOf: repeatElement(0, count: Int((gap * Double(sampleRate)).rounded())))
                }
            } else if gap < -0.75 {
                // A WebKit process restart changed the callback's clock origin.
                interruption = -gap
                buffer.removeAll(keepingCapacity: true)
                bufferStart = start
            }
        } else {
            bufferStart = start
        }
        buffer.append(contentsOf: samples)
        self.expectedEnd = endedAt
        var completed: [AudioSlot] = []
        while buffer.count >= slotSamples, let slotStart = bufferStart {
            completed.append(AudioSlot(index: nextIndex,
                                       samples: Array(buffer.prefix(slotSamples)),
                                       sampleRate: sampleRate,
                                       startTime: slotStart))
            nextIndex += 1
            buffer.removeFirst(slotSamples)
            bufferStart = slotStart.addingTimeInterval(15)
        }
        return AppendResult(slots: completed, interruptionSeconds: interruption)
    }
}
