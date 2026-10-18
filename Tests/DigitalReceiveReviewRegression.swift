// No audio devices or radio transports are opened. Feed text and PCM directly into the real engines.
import AVFoundation
import Foundation

@main
@MainActor
struct DigitalReceiveReviewRegression {
    static func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    static func main() {
        let codes = VaricodeCodec.asciiToVaricode
        precondition(codes.count == 128 && Set(codes).count == 128)
        precondition(codes.allSatisfy { $0.first == "1" && $0.last == "1" && !$0.contains("00") })
        for i in 0..<128 {
            let character = Character(UnicodeScalar(i)!)
            precondition(VaricodeCodec.varicodeToAscii[codes[i]] == character)
            precondition(VaricodeCodec.encode(char: character) == codes[i] + "00")
        }
        // Independent anchors from G3PLX's published Table 1, including the reported digit/backslash collision.
        for (character, code) in [(Character("E"), "1110111"), ("3", "11111111"), ("\\", "111101111"), ("_", "101101101"), ("r", "10101")] {
            precondition(VaricodeCodec.encode(char: character) == code + "00")
        }
        for chunkSize in [1, 2, 7, 128] {
            let engine = DigitalModemEngine()
            engine.myCallsign = "K0ABC"
            let text = Array("CQ DE EA3XYZ EA3XYZ 599 ")
            for offset in stride(from: 0, to: text.count, by: chunkSize) {
                engine.appendDecodedText(String(text[offset..<min(text.count, offset + chunkSize)]))
            }
            precondition(engine.targetCallsign == "EA3XYZ")
            precondition(engine.decodedTokens.filter { $0.isCallsign }.map(\.text) == ["EA3XYZ", "EA3XYZ"])
        }
        let pending = DigitalModemEngine()
        pending.appendDecodedText("CQ DE EA3X")
        precondition(pending.targetCallsign.isEmpty)
        pending.appendDecodedText("YZ ")
        precondition(pending.targetCallsign == "EA3XYZ")
        pending.clearTerminals()
        pending.targetCallsign = ""
        pending.appendDecodedText(String(repeating: "X", count: 1000) + "EA3XYZ ")
        precondition(pending.targetCallsign.isEmpty)
        // An unavailable output must not key a radio or pretend that the text was transmitted.
        pending.myCallsign = "EA3XYZ"
        _ = KeyLog.drain()
        pending.queueTextForTransmission("CQ")
        tick()
        precondition(!pending.isTransmitting && !pending.txRefusal.isEmpty && pending.txTransmittedText.isEmpty)
        precondition(pending.txRemainingText == "CQ" && KeyLog.drain().isEmpty)
        // Registration is process-local; do not write to the operator's saved preferences.
        UserDefaults.standard.register(defaults: ["operatorCallsign": "EA3XYZ", "stationCallsign": "EA3XYZ"])
        let olivia = OliviaMFSKEngine()
        olivia.queueTextForTransmission("CQ")
        precondition(!olivia.isTransmitting && olivia.txRefusal.contains("Audio transmitter") && olivia.txTransmittedText.isEmpty)
        let hell = HellschreiberEngine()
        hell.queueTextForTransmission("CQ")
        precondition(!hell.isTransmitting && hell.txRefusal.contains("Audio transmitter") && hell.txTransmittedText.isEmpty)
        // Complete 10 seconds of carrier at two hardware sample rates and awkward buffer boundaries.
        for rate in [44_100.0, 48_000.0] {
            let receiver = HellschreiberEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            var position = 0
            let total = Int(rate * 10)
            while position < total {
                let count = min(2047, total - position)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                for i in 0..<count { buffer.floatChannelData![0][i] = Float(sin(2 * Double.pi * 980 * Double(position + i) / rate)) }
                receiver.processAudioBuffer(buffer)
                position += count
            }
            tick()
            let pixels = receiver.columns.count * 14
            precondition(abs(Double(pixels) / 10 - 245) < 2.45, "Hell pixel rate at \(rate) is \(Double(pixels) / 10)")
        }
        print("DigitalReceiveReviewRegression passed: 128 standard Varicodes, streamed callsigns, safe unavailable TX, Hell 245 pixels/s at 44.1/48 kHz")
    }
}
