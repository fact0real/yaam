import Foundation

@main struct SerialModemDriverRegression {
    static func pins() -> [String] {
        SerialLog.drain().map(\.text).filter { $0.hasPrefix("DTR ") || $0.hasPrefix("RTS ") }
    }
    static func main() {
        for key in ["lab599AutoConnect", "fx4crAutoConnect", "icomUSBAutoConnect", "xiegu6100AutoConnect"] {
            UserDefaults.standard.set(false, forKey: key)
        }
        SerialPortService.allowsOpen = true
        let lab = Lab599TX500Driver.shared
        lab.connect(port: "fixture.invalid")
        lab.setKeyPin(active: true, pin: .dtr)
        lab.setKeyPin(active: true, pin: .rts)
        lab.disconnect()
        precondition(pins().isEmpty, "TX-500 CAT must not control modem pins")

        let fx = FX4CRDriver.shared
        fx.connect(port: "fixture.invalid", type: .bluetooth)
        fx.setKeyPin(active: true, pin: .dtr)
        fx.setKeyPin(active: true, pin: .rts)
        fx.disconnect()
        precondition(pins().isEmpty, "Bluetooth CAT has no USB modem-pin keying")
        fx.connect(port: "fixture.invalid", type: .usb)
        precondition(pins() == ["RTS false"], "Existing USB RTS release must remain before CAT")
        fx.setKeyPin(active: true, pin: .dtr)
        fx.setKeyPin(active: false, pin: .dtr)
        fx.setKeyPin(active: true, pin: .rts)
        fx.setKeyPin(active: false, pin: .rts)
        precondition(pins() == ["DTR true", "DTR false", "RTS true", "RTS false"])
        fx.disconnect()
        _ = pins()

        let xiegu = Xiegu6100Driver.shared
        xiegu.enableHardwareRTSPTT = false
        xiegu.enableHardwareDTRCW = false
        xiegu.connect(port: "fixture.invalid")
        xiegu.setKeyPin(active: true, pin: .dtr)
        xiegu.setKeyPin(active: true, pin: .rts)
        xiegu.setPTT(true); xiegu.setPTT(false); xiegu.stopMorse()
        precondition(pins().isEmpty, "Hardware options disabled: CAT only")
        // The existing live options still work without broadening any other driver's permission.
        xiegu.enableHardwareRTSPTT = true
        xiegu.enableHardwareDTRCW = true
        xiegu.setKeyPin(active: true, pin: .dtr)
        xiegu.stopMorse()
        xiegu.setPTT(true); xiegu.setPTT(false)
        precondition(pins() == ["DTR true", "DTR false", "RTS true", "RTS false"])
        xiegu.disconnect()
        xiegu.enableHardwareRTSPTT = false
        xiegu.enableHardwareDTRCW = false
        _ = pins()

        let icom = IcomUSBRadioDriver.shared
        icom.enableHardwareRTSPTT = false
        icom.enableHardwareDTRCW = false
        icom.connect(port: "fixture.invalid")
        icom.setPTT(true); icom.setPTT(false); icom.stopMorse()
        precondition(pins().isEmpty)
        icom.enableHardwareRTSPTT = true
        icom.enableHardwareDTRCW = true
        icom.setPTT(true); icom.setPTT(false); icom.stopMorse()
        precondition(pins() == ["RTS true", "RTS false", "DTR false"])
        icom.disconnect()
        print("PASS real drivers: TX-500/Bluetooth denial, FX-4CR USB release/keying, Icom/X6100 opt-in and PTT release")
    }
}
