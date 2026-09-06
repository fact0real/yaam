import Foundation

#if STANDALONE_TEST
nonisolated enum PortableOperatingRole: String, CaseIterable, Identifiable, Sendable {
    case none, hunter, activator
    var id: String { rawValue }
    var title: String { rawValue }
}
#endif

@main
struct QuickLogErgonomicsRegression {
    static func main() {
        testModeSubmodeConflictResolution()
        testSmartFrequencyInference()
        testQuickLogDraftStateTransitions()
        testTimeOffAndDates()
        print("All Quick Log ergonomics regression tests passed successfully.")
    }

    private static func testModeSubmodeConflictResolution() {
        // Test 1: FT8 submode with DATA mode preserves both
        var mode = "DATA"
        var submode = "FT8"
        AmateurBandPlan.normalizeModeAndSubmode(mode: &mode, submode: &submode)
        precondition(mode == "DATA", "Expected mode to be DATA when submode is FT8, got \(mode)")
        precondition(submode == "FT8", "Expected submode to be FT8, got \(submode)")

        // Test 2: FT8 submode with empty mode auto-corrects to DATA
        mode = ""
        submode = "FT8"
        AmateurBandPlan.normalizeModeAndSubmode(mode: &mode, submode: &submode)
        precondition(mode == "DATA", "Expected mode to be DATA when submode is FT8, got \(mode)")

        // Test 3: Setting mode to SSB while submode was FT8 clears incompatible submode
        mode = "SSB"
        submode = "FT8"
        AmateurBandPlan.normalizeModeAndSubmode(mode: &mode, submode: &submode)
        precondition(mode == "SSB" && submode == "", "Expected SSB mode to clear FT8 submode")

        // Test 4: SSB with USB or LSB is valid
        mode = "SSB"
        submode = "USB"
        AmateurBandPlan.normalizeModeAndSubmode(mode: &mode, submode: &submode)
        precondition(mode == "SSB" && submode == "USB", "Expected SSB USB to be preserved")

        // Test 5: submodes(forMode:) returns relevant list
        let dataSubmodes = AmateurBandPlan.submodes(forMode: "DATA")
        precondition(dataSubmodes.contains("FT8") && dataSubmodes.contains("FT4") && dataSubmodes.contains("JS8"),
                     "DATA submodes must include FT8, FT4, JS8")
        let ssbSubmodes = AmateurBandPlan.submodes(forMode: "SSB")
        precondition(ssbSubmodes.contains("USB") && ssbSubmodes.contains("LSB") && !ssbSubmodes.contains("FT8"),
                     "SSB submodes must not include FT8")
    }

    private static func testSmartFrequencyInference() {
        // FT8 on 20m: 14.074
        let ft8_20m = AmateurBandPlan.smartInfer(frequencyMHz: 14.074)
        precondition(ft8_20m.band == "20m", "Expected 20m, got \(ft8_20m.band)")
        precondition(ft8_20m.mode == "DATA", "Expected DATA, got \(ft8_20m.mode)")
        precondition(ft8_20m.submode == "FT8", "Expected FT8, got \(ft8_20m.submode)")
        precondition(ft8_20m.rst == "-10", "Expected -10 RST for FT8, got \(ft8_20m.rst)")

        // FT8 on 40m: 7.074
        let ft8_40m = AmateurBandPlan.smartInfer(frequencyMHz: 7.074)
        precondition(ft8_40m.band == "40m" && ft8_40m.submode == "FT8", "Expected 40m FT8")

        // FT4 on 20m: 14.080
        let ft4_20m = AmateurBandPlan.smartInfer(frequencyMHz: 14.080)
        precondition(ft4_20m.band == "20m" && ft4_20m.submode == "FT4", "Expected 20m FT4")

        // CW on 20m: 14.025
        let cw_20m = AmateurBandPlan.smartInfer(frequencyMHz: 14.025)
        precondition(cw_20m.band == "20m" && cw_20m.mode == "CW" && cw_20m.rst == "599", "Expected 20m CW 599")

        // SSB voice on 20m: 14.225
        let ssb_20m = AmateurBandPlan.smartInfer(frequencyMHz: 14.225)
        precondition(ssb_20m.band == "20m" && ssb_20m.mode == "SSB" && ssb_20m.rst == "59", "Expected 20m SSB 59")
    }

    private static func testQuickLogDraftStateTransitions() {
        var draft = QuickLogDraft()
        precondition(draft.band == "20m")

        // Apply frequency updates band and mode
        draft.applyFrequency("14.074")
        precondition(draft.band == "20m")
        precondition(draft.mode == "DATA")
        precondition(draft.submode == "FT8")
        precondition(draft.rstSent == "-10")

        // Change mode to SSB
        draft.applyMode("SSB")
        precondition(draft.mode == "SSB")
        precondition(draft.submode == "", "Changing to SSB should clear FT8 submode")
        precondition(draft.rstSent == "59")

        // Change submode to FT4
        draft.applySubmode("FT4")
        precondition(draft.mode == "DATA", "Setting FT4 submode must auto-promote mode to DATA")
        precondition(draft.submode == "FT4")

        // Fill QSO details
        draft.callsign = "w1aw"
        precondition(draft.normalizedCallsign == "W1AW")
        draft.sentSerial = "001"
        draft.receivedSerial = "005"
        draft.state = "ct"
        draft.arrlSection = "ct"

        // Reset for next QSO preserves context
        draft.resetForNextQSO(keepingOperatingContext: true)
        precondition(draft.callsign.isEmpty, "Callsign must be cleared")
        precondition(draft.sentSerial.isEmpty, "Serial must be cleared")
        precondition(draft.state.isEmpty, "State must be cleared")
        precondition(draft.frequencyMHz == "14.074", "Frequency must be preserved")
        precondition(draft.band == "20m", "Band must be preserved")
        precondition(draft.mode == "DATA", "Mode must be preserved")
        precondition(draft.submode == "FT4", "Submode must be preserved")
    }

    private static func testTimeOffAndDates() {
        let calendar = Calendar(identifier: .gregorian)
        var calUTC = calendar
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!

        let started = Date(timeIntervalSince1970: 1725541200) // 13:00:00 UTC
        let ended = Date(timeIntervalSince1970: 1725541245)   // 13:00:45 UTC (45 seconds later)

        let startComp = calUTC.dateComponents([.hour, .minute, .second], from: started)
        let endComp = calUTC.dateComponents([.hour, .minute, .second], from: ended)

        let timeOn = String(format: "%02d%02d%02d", startComp.hour ?? 0, startComp.minute ?? 0, startComp.second ?? 0)
        let timeOff = String(format: "%02d%02d%02d", endComp.hour ?? 0, endComp.minute ?? 0, endComp.second ?? 0)

        precondition(timeOn == "130000", "Expected TIME_ON to be 130000, got \(timeOn)")
        precondition(timeOff == "130045", "Expected TIME_OFF to be 130045, got \(timeOff)")
        precondition(ended.timeIntervalSince(started) == 45, "Duration must be 45 seconds")
    }
}
