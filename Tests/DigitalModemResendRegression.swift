import Foundation

/// Runs the real queue without audio or hardware; hands out characters exactly as the modulation loop does.
@main
struct DigitalModemResendRegression {
    static func main() {
        let engine = DigitalModemEngine()
        engine.myCallsign = "EP2AES"
        func consume() -> String {
            var result = ""
            while let char = engine.nextCharacterToSend() { result.append(char) }
            return result
        }
        engine.isTransmitting = true
        engine.queueTextForTransmission("CQ CQ ")
        precondition(consume() == "CQ CQ ")
        engine.queueTextForTransmission("DE EP2AES ")
        engine.pendingTransmitText += "K"
        precondition(consume() == "DE EP2AES K")
        precondition(consume().isEmpty, "A second transmit must not repeat the TX box")
        engine.isTransmitting = false
        engine.pendingTransmitText = " NEW"
        engine.startTransmission()
        precondition(engine.txRemainingText == " NEW" && engine.txRefusal.contains("Audio transmitter is unavailable"))
        engine.stopTransmission() // idle stop preserves pending text
        precondition(engine.pendingTransmitText == " NEW")
        engine.isTransmitting = true
        _ = engine.nextCharacterToSend()
        engine.stopTransmission()
        engine.startTransmission()
        precondition(engine.txRefusal.contains("nothing new to send"), "Abort must not replay the unsent remainder")
        // Sent text is immutable; edits in the pending editor have an explicit boundary even for repeated text.
        for text in ["AAAA", "ABAB", "CQ CQ", "é👩🏽‍💻é", "EP2AES"] {
            engine.txBufferText = ""
            engine.pendingTransmitText = text
            engine.isTransmitting = true
            let first = engine.nextCharacterToSend()!
            engine.pendingTransmitText = "Z" + engine.pendingTransmitText
            precondition(consume() == "Z" + String(text.dropFirst()))
            precondition(engine.txBufferText.first == first)
            let history = engine.txBufferText
            engine.txBufferText = "CHANGED"
            precondition(engine.txBufferText == history, "Editing history must not create another transmission")
            engine.isTransmitting = false
        }
        engine.txBufferText = ""
        precondition(engine.txSentCount == 0)
        engine.pendingTransmitText = "NEW"
        engine.isTransmitting = true
        precondition(consume() == "NEW")
        engine.stopTransmission()
        print("PASS digital TX: macros, type ahead, typed start, abort, idle stop, clear, Unicode and repeated-text edits")
    }
}
