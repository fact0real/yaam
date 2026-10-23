import Foundation

nonisolated final class VerifiedRadio: @unchecked Sendable {
    let lock = NSLock()
    var mode = "MD6;", tx = false, refuseTX = false, silent = false
    func reply(_ command: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if command == "TX;" { if !refuseTX { tx = true }; return nil }
        if command == "RX;" { tx = false; return nil }
        if silent { return nil }
        if command == "MD;" { return mode }
        if command == "PT;" { return tx ? "PT1;" : "PT0;" }
        return nil
    }
}
@main
struct TX500VerifiedPTTRegression {
    static func main() async throws {
        UserDefaults.standard.set(false, forKey: "lab599AutoConnect")
        SerialPortService.allowsOpen = true
        let model = VerifiedRadio()
        SerialPortService.writeReply = { model.reply($0) }
        let driver = Lab599TX500Driver.shared
        driver.connect(port: "fixture.invalid")
        _ = SerialLog.drain()
        try await driver.keyFT8Verified(maximumDuration: 2, before: Date().addingTimeInterval(0.2))
        let success = SerialLog.drain().map(\.text)
        precondition(success == ["MD;", "PT;", "TX;", "PT;"], "Fresh DIG, RX and TX readbacks precede audio permission")
        precondition(driver.isTransmitting)
        driver.setPTT(false)
        print("PASS TX-500 fresh MD6/PT0/PT1 ordering, with no mode mutation or audio")
        for mode in ["MD2;", "MD8;", "MD9;", "MD999;"] {
            model.mode = mode
            _ = SerialLog.drain()
            do { try await driver.keyFT8Verified(maximumDuration: 2, before: Date().addingTimeInterval(0.1)); preconditionFailure("Unverified DIG accepted") }
            catch {}
            precondition(!SerialLog.drain().contains { $0.text == "TX;" })
        }
        model.mode = "MD6;"; model.refuseTX = true
        do { try await driver.keyFT8Verified(maximumDuration: 2, before: Date().addingTimeInterval(0.1)); preconditionFailure("Refused TX accepted") }
        catch {}
        precondition(!driver.isTransmitting && SerialLog.drain().contains { $0.text == "RX;" })
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("FT8 audio was blocked") })
        model.refuseTX = false; model.silent = true
        do { try await driver.keyFT8Verified(maximumDuration: 2, before: Date().addingTimeInterval(0.05)); preconditionFailure("Stale cached replies accepted") }
        catch {}
        precondition(!SerialLog.drain().contains { $0.text == "TX;" })
        model.silent = false
        let cancelled = Task { try await driver.keyFT8Verified(maximumDuration: 2, before: Date().addingTimeInterval(0.2)) }
        cancelled.cancel()
        do { try await cancelled.value; preconditionFailure("Cancellation accepted") } catch {}
        precondition(!SerialLog.drain().contains { $0.text == "TX;" })
        model.silent = true
        driver.checkFT8Receive()
        try await Task.sleep(for: .milliseconds(450))
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("fresh PT0 receive was NOT confirmed") })
        model.silent = false
        driver.disconnect()
        print("PASS TX-500 wrong/unknown mode, rejected PTT, stale replies, timeout and cancellation block TX/audio and request RX")
        let fx = FX4CRDriver.shared
        SerialPortService.rtsResult = false
        _ = SerialLog.drain()
        fx.connect(port: "fixture.invalid", type: .usb)
        let opened = SerialLog.drain().map(\.text)
        precondition(opened.prefix(2) == ["OPEN", "RTS false"], "RTS must be lowered immediately after open, before CAT")
        precondition(!opened.contains { $0.hasPrefix("DTR") })
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("FX-4CR: RTS could not be released") })
        fx.disconnect()
        print("PASS FX-4CR lowers RTS before CAT, preserves DTR, and persists USB line-release failure")
    }
}
