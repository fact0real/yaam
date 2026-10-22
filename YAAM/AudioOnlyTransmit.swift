//
//  AudioOnlyTransmit.swift
//  YAAM
//
//  Olivia/MFSK, Hellschreiber, JS8 and SSTV only play their audio: they never key a radio's PTT (Y-001). With VOX or
//  an external PTT that is what the operator wants. With a radio connected, the operator may expect YAAM to key it, as
//  the PSK/RTTY modes do, and then nothing goes on the air while the screen shows the mode sending. So these modes say
//  so while they send (B-018), and clear only that notice when the transmission ends.
//
//  Platform: pure Swift, no AppKit.
//

import Foundation

enum AudioOnlyTransmit {
    /// The part every notice has, so an engine can tell its notice from an error in the same field.
    private static let marker = "this mode does not key the radio"

    /// The radio YAAM has connected and would key for PSK/RTTY, or nil when none is: Radio Control's radio when it is
    /// connected, or a TX-500 or X6100 connected from its own panel (PSK/RTTY keys those too).
    static func radioInUse() -> String? {
        let rig = RigControlEngine.shared
        if rig.driverType != .disabled, rig.isConnected { return rig.driverType.rawValue }
        if Lab599TX500Driver.shared.isConnected { return "Lab599 TX-500" }
        if Xiegu6100Driver.shared.isConnected { return "Xiegu X6100" }
        return nil
    }

    /// What an audio-only mode says while it sends, or nil when no radio is connected: VOX or an external PTT is then
    /// the expected way to transmit, and there is nothing to add.
    static func notice(mode: String, radio: String?) -> String? {
        guard let radio else { return nil }
        return "\(mode): playing the audio at \(TXLimits.utc()), but \(marker) (\(radio)). "
            + "The audio goes on the air only if VOX or an external PTT keys the radio; otherwise nothing is "
            + "transmitted. Receiving, logging and the other modes keep working."
    }

    /// True for a notice from `notice`, false for any other text (an error stays until it is dealt with).
    static func isNotice(_ text: String) -> Bool {
        text.contains(marker)
    }
}
