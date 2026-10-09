// swiftc -parse-as-library YAAM/FT8AudioDecimator.swift Tests/FT8AudioDecimatorRegression.swift -o /tmp/yaam-decimator && /tmp/yaam-decimator
import Foundation

@main
struct FT8AudioDecimatorRegression {
    static func main() {
        let input = (0..<48_000).map { index -> Float in
            let time = Double(index) / 48_000
            return Float(sin(2 * .pi * 2_500 * time) + sin(2 * .pi * 9_000 * time))
        }
        var whole = FT8AudioDecimator()
        let complete = whole.process(input)
        precondition(complete.count == 12_000)

        var packetized = FT8AudioDecimator()
        var chunks: [Float] = []
        var start = 0
        while start < input.count {
            let end = min(input.count, start + 257)
            chunks.append(contentsOf: packetized.process(Array(input[start..<end])))
            start = end
        }
        precondition(chunks == complete, "Network packet boundaries changed filtered samples")

        func amplitude(_ frequency: Double) -> Double {
            let settled = complete.dropFirst(100)
            let n = Double(settled.count)
            let cosine = settled.enumerated().reduce(0.0) { total, item in
                total + Double(item.element) * cos(2 * .pi * frequency * Double(item.offset + 100) / 12_000)
            }
            let sine = settled.enumerated().reduce(0.0) { total, item in
                total + Double(item.element) * sin(2 * .pi * frequency * Double(item.offset + 100) / 12_000)
            }
            return 2 * hypot(cosine, sine) / n
        }

        precondition(amplitude(2_500) > 0.95, "FT8 passband was attenuated")
        precondition(amplitude(3_000) < 0.01, "9 kHz alias was not suppressed")
        print("FT8 audio decimator passed: continuous packets, passband, alias rejection")
    }
}
