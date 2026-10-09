import Foundation

/// Continuous 48 kHz → 12 kHz conversion for the Icom LAN receive stream.
/// The low-pass filter removes energy above the new Nyquist frequency before
/// decimation, while keeping its phase and history across network packets.
nonisolated struct FT8AudioDecimator {
    private static let factor = 4
    private static let tapCount = 65
    private static let coefficients: [Float] = {
        let midpoint = Double(tapCount - 1) / 2
        let cutoff = 4_200.0 / 48_000.0
        var taps = (0..<tapCount).map { index -> Double in
            let offset = Double(index) - midpoint
            let ideal = offset == 0
                ? 2 * cutoff
                : sin(2 * .pi * cutoff * offset) / (.pi * offset)
            let window = 0.54 - 0.46 * cos(2 * .pi * Double(index) / Double(tapCount - 1))
            return ideal * window
        }
        let gain = taps.reduce(0, +)
        for index in taps.indices { taps[index] /= gain }
        return taps.map(Float.init)
    }()

    private var history = [Float](repeating: 0, count: tapCount)
    private var nextWrite = 0
    private var phase = 0

    mutating func process(_ input: [Float]) -> [Float] {
        var output: [Float] = []
        output.reserveCapacity((input.count + Self.factor - 1) / Self.factor)
        for sample in input {
            history[nextWrite] = sample
            nextWrite = (nextWrite + 1) % Self.tapCount
            if phase == 0 {
                var filtered: Float = 0
                var index = (nextWrite + Self.tapCount - 1) % Self.tapCount
                for tap in Self.coefficients {
                    filtered += tap * history[index]
                    index = index == 0 ? Self.tapCount - 1 : index - 1
                }
                output.append(filtered)
            }
            phase = (phase + 1) % Self.factor
        }
        return output
    }
}
