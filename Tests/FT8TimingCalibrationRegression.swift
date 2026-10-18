// Known start times, not a median learned from received stations. Uses the pinned real codec and decoder.
// Run via Tests/run-review-regressions.sh after a Debug build.
import Foundation
import FT8Codec

@main
struct FT8TimingCalibrationRegression {
    static func main() throws {
        let tones = try FT8Codec.encode("CQ K0ABC FN31")
        let waveform = FT8Codec.synthesize(tones: tones, baseFrequencyHz: 1500, sampleRate: 12_000)
        for expanded in [false, true] {
            for sentDT: Float in [-2.2, -1.8, 0, 1, 1.8, 2.2] {
                let offset = Int(((sentDT + 0.5) * 12_000).rounded())
                var audio = [Float](repeating: 0, count: 180_000)
                for i in 0..<waveform.count where (0..<audio.count).contains(offset + i) { audio[offset + i] = waveform[i] }
                let messages = try FT8StationDecoder.decode(samples: audio, sampleRate: 12_000, protocol: .ft8, expanded: expanded)
                guard let found = messages.first(where: { $0.message.text == "CQ K0ABC FN31" }) else { preconditionFailure("Known FT8 waveform did not decode") }
                let measured = found.message.timeSeconds + found.timeCorrection
                precondition(abs(measured - sentDT) < 0.1, "DT \(sentDT) measured as \(measured)")
                precondition((abs(measured) > 2) == (abs(sentDT) > 2), "Clock warning at the wrong threshold")
            }
        }
        let ft4Tones = try FT8Codec.encode("CQ K0ABC FN31", protocol: .ft4)
        let ft4Wave = FT8Codec.synthesize(tones: ft4Tones, baseFrequencyHz: 1500, protocol: .ft4, sampleRate: 12_000)
        var ft4Audio = [Float](repeating: 0, count: 90_000)
        for i in 0..<ft4Wave.count { ft4Audio[6000 + i] = ft4Wave[i] }
        let rawFT4 = try FT8Codec.decode(samples: ft4Audio, sampleRate: 12_000, protocol: .ft4)
        let wrappedFT4 = try FT8StationDecoder.decode(samples: ft4Audio, sampleRate: 12_000, protocol: .ft4, expanded: false)
        precondition(!rawFT4.isEmpty && wrappedFT4.count == rawFT4.count)
        precondition(wrappedFT4.allSatisfy { $0.timeCorrection == 0 }, "Do not apply an FT8 calibration to FT4")
        print("FT8TimingCalibrationRegression passed: known DTs, expanded decoding, 2-second warning boundary, unchanged FT4")
    }
}
