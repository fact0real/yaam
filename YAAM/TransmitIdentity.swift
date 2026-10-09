//
//  TransmitIdentity.swift
//  YAAM
//
//  One check for "may this station transmit?": the operator's own callsign (and, for FT8/FT4, the
//  locator) must be set and accepted before anything is keyed. Nothing here knows a real callsign
//  or locator. Foundation and GridLocator only, so it can be tested on its own
//  (Tests/TransmitIdentityRegression.swift).
//

import Foundation

nonisolated enum TransmitIdentity {

    // MARK: - The callsign shape rule (the one place to change it)

    /// Whether a callsign that ends in a digit is accepted for transmitting. Special-event callsigns can
    /// end in a digit (for example 0I2012, 0M100, 0R100). false keeps the rule as it was written: a callsign
    /// ends in a letter. true accepts the digit ending as well. The project owner sets this after checking
    /// the ITU and IARU rules for special-event callsigns; the tests run with both values.
    static let acceptsCallsignsEndingInDigit = false

    // Optional "XX/" prefix (1-5 characters), 1-3 characters, one digit, up to 6 more characters ending in a
    // letter (special-event calls such as 0B100RSGB are longer than ordinary ones), optional "/P", "/M",
    // "/QRP" style suffix. Plausibility only: it does not claim a licence exists, and it must not refuse
    // a real call, so it is wider than the calls issued every day.
    private static let callsignPatternEndingInLetter =
        #"^([A-Z0-9]{1,5}/)?[A-Z0-9]{1,3}[0-9][A-Z0-9]{0,6}[A-Z](/[A-Z0-9]{1,4})?$"#
    // The same shape, but the last character may be a digit. The part after the optional prefix still has to
    // contain a letter, so a bare number is not a callsign.
    private static let callsignPatternEndingInDigit =
        #"^([A-Z0-9]{1,5}/)?(?=[A-Z0-9]*[A-Z])[A-Z0-9]{1,3}[0-9][A-Z0-9]{0,6}(/[A-Z0-9]{1,4})?$"#

    /// Words that stand for "no callsign". Never accepted, whatever they look like.
    static let placeholderCallsigns: Set<String> = [
        "DEFAULT", "NOCALL", "N0CALL", "CALLSIGN", "MYCALL", "YOURCALL", "YOURCALLSIGN"
    ]

    // MARK: - Messages shown to the operator

    /// No callsign has been entered (or only a placeholder word such as NOCALL).
    static let callsignMissingMessage = "Set your callsign in Settings > Stations before transmitting."
    /// A callsign has been entered, but the shape rule does not accept it.
    static let callsignRejectedMessage =
        "The callsign in Settings > Stations is not accepted for transmitting. Check how it is written."
    /// No locator has been entered.
    static let locatorMissingMessage = "Set your locator in Settings > Stations before transmitting."
    /// A locator has been entered, but it does not begin with a valid Maidenhead square.
    static let locatorRejectedMessage =
        "The locator in Settings > Stations is not accepted. It must begin with a Maidenhead square: two letters, then two digits."

    /// Posted when the active station profile has been saved or switched. A refusal that was shown for the
    /// previous profile no longer applies; screens that show one clear it on this notification.
    static let identityChanged = Notification.Name("TransmitIdentity.identityChanged")

    // MARK: - Neutral text for fields and displays

    /// Prompt of a text field that takes the operator's own callsign.
    static let callsignPlaceholder = "Your callsign"
    /// Prompt of a text field that takes the operator's own locator.
    static let locatorPlaceholder = "Your locator"
    /// Shown instead of the operator's callsign when none is set.
    static let callsignNotSetLabel = "Callsign not set"
    /// Shown instead of the operator's locator when none is set.
    static let locatorNotSetLabel = "Locator not set"
    /// Stands in for the operator's callsign in previews and file names. It is one of the placeholder words, so
    /// the keyer refuses it and it is never sent.
    static let callsignPreviewToken = "CALLSIGN"

    // MARK: - Callsign

    static func normalized(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// True for an empty value or one of the words that stand for "no callsign".
    static func isPlaceholderCallsign(_ raw: String?) -> Bool {
        let call = normalized(raw)
        return call.isEmpty || placeholderCallsigns.contains(call)
    }

    /// The callsign as the operator entered it (trimmed, upper-cased); empty when none was entered or only
    /// a placeholder word. An engine holds this value; its checks then tell "not set" from "not accepted".
    static func enteredCallsign(_ raw: String?) -> String {
        isPlaceholderCallsign(raw) ? "" : normalized(raw)
    }

    static func isValidCallsign(
        _ raw: String?,
        acceptsCallsignsEndingInDigit: Bool = TransmitIdentity.acceptsCallsignsEndingInDigit
    ) -> Bool {
        let call = normalized(raw)
        guard !call.isEmpty, !placeholderCallsigns.contains(call) else { return false }
        let pattern = acceptsCallsignsEndingInDigit ? callsignPatternEndingInDigit : callsignPatternEndingInLetter
        return call.range(of: pattern, options: .regularExpression) != nil
    }

    /// The callsign trimmed and upper-cased, or nil when it is empty, a placeholder or not callsign-shaped.
    static func usableCallsign(
        _ raw: String?,
        acceptsCallsignsEndingInDigit: Bool = TransmitIdentity.acceptsCallsignsEndingInDigit
    ) -> String? {
        isValidCallsign(raw, acceptsCallsignsEndingInDigit: acceptsCallsignsEndingInDigit) ? normalized(raw) : nil
    }

    /// Why a station with this callsign may not key the transmitter, or nil when it may.
    /// "Not set" (empty or a placeholder word) and "not accepted" (entered, but the shape rule refuses it)
    /// are different messages: the operator did enter a callsign in the second case.
    static func callsignRefusal(
        _ raw: String?,
        acceptsCallsignsEndingInDigit: Bool = TransmitIdentity.acceptsCallsignsEndingInDigit
    ) -> String? {
        if isPlaceholderCallsign(raw) { return callsignMissingMessage }
        if !isValidCallsign(raw, acceptsCallsignsEndingInDigit: acceptsCallsignsEndingInDigit) {
            return callsignRejectedMessage
        }
        return nil
    }

    // MARK: - Locator

    /// The four-character square that FT8 and FT4 send, or nil. The first four characters must be a valid
    /// Maidenhead square, which is exactly what the Stations screen requires (GridLocator.fourCharacterGrid,
    /// used by StationProfile.validationMessage); characters after them do not matter here. The digits must
    /// be ASCII: the Stations screen also accepts digits of other scripts, which no receiver decodes.
    static func ft8Locator(_ raw: String?) -> String? {
        guard let square = GridLocator.fourCharacterGrid(from: raw ?? "") else { return nil }
        let characters = Array(square)
        return characters[2].isASCII && characters[3].isASCII ? square : nil
    }

    /// The locator as it may be sent when more than four characters are sent (RTTY/PSK macros, chat posts):
    /// the square, then as many valid sub-square pairs as follow (letters A-X, digits, letters A-X), so 4, 6,
    /// 8 or 10 characters. Anything after the last valid pair is dropped. nil when there is no valid square.
    static func locator(_ raw: String?) -> String? {
        guard let square = ft8Locator(raw) else { return nil }
        let characters = Array(normalized(raw))
        let pairs: [ClosedRange<Character>] = ["A"..."X", "0"..."9", "A"..."X"]
        var result = square
        var index = 4
        for range in pairs {
            guard index + 1 < characters.count,
                  characters[index].isASCII, characters[index + 1].isASCII,
                  range.contains(characters[index]), range.contains(characters[index + 1]) else { break }
            result += String(characters[index...index + 1])
            index += 2
        }
        return result
    }

    /// True when the value begins with a valid Maidenhead square (what the Stations screen accepts).
    static func isValidLocator(_ raw: String?) -> Bool {
        ft8Locator(raw) != nil
    }

    /// Why FT8/FT4 may not send this locator, or nil when they may. Empty is "not set"; anything else that
    /// does not begin with a valid square is "not accepted".
    static func locatorRefusal(_ raw: String?) -> String? {
        if normalized(raw).isEmpty { return locatorMissingMessage }
        return ft8Locator(raw) == nil ? locatorRejectedMessage : nil
    }

    // MARK: - FT8 / FT4

    /// FT8 and FT4 messages carry the operator's callsign and four-character locator.
    /// Returns why the station may not transmit, or nil when it may.
    static func refusal(callsign: String?, grid: String?) -> String? {
        callsignRefusal(callsign) ?? locatorRefusal(grid)
    }

    /// "<dx> <callsign> <locator>" for a station that has just been heard: the operator's own callsign and
    /// four-character locator, or nil while either is not usable. No default is ever substituted.
    static func gridMessage(to dx: String, callsign: String?, grid: String?) -> String? {
        guard refusal(callsign: callsign, grid: grid) == nil,
              let own = usableCallsign(callsign), let ownGrid = ft8Locator(grid) else { return nil }
        let target = normalized(dx)
        guard !target.isEmpty else { return nil }
        return "\(target) \(own) \(ownGrid)"
    }

    /// True for the text of a refusal about the station's callsign or locator. An engine or a screen that holds
    /// such a text clears it when the station identity changes; any other message is left alone.
    static func isIdentityRefusal(_ text: String) -> Bool {
        [callsignMissingMessage, callsignRejectedMessage, locatorMissingMessage, locatorRejectedMessage,
         notYourCallsignText, notYourLocatorText].contains(text)
    }

    static let noMessageText = "There is no message to transmit."
    static let notYourCallsignText = "The message does not come from your own callsign, so it was not sent."
    static let notYourLocatorText = "The message carries a locator that is not yours, so it was not sent."

    /// Final check on the text about to be keyed. Free text ("TNX 73 GL") carries no sender and is not
    /// refused. A standard message (CQ or a callsign, then the sender's callsign) must be sent by the
    /// operator, as the plain callsign or as the hashed form "<callsign>", and a locator in it must be the
    /// operator's own. Catches a message built from stale or default values.
    static func ft8MessageRefusal(_ message: String, callsign: String?, grid: String?) -> String? {
        if let issue = refusal(callsign: callsign, grid: grid) { return issue }
        guard let own = usableCallsign(callsign), let ownGrid = ft8Locator(grid) else {
            return callsignMissingMessage
        }
        let words = message.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return noMessageText }
        // Placeholder callsigns must never slip through as FT8 free text.
        guard !words.contains(where: { placeholderCallsigns.contains($0) }) else { return notYourCallsignText }
        guard let senderIndex = standardMessageSenderIndex(words) else { return nil }

        let sender = words[senderIndex]
        guard sender == own || sender == "<\(own)>" else { return notYourCallsignText }
        for word in words.dropFirst(senderIndex + 1) where isLocatorWord(word) && word != ownGrid {
            return notYourLocatorText
        }
        return nil
    }

    /// The position of the sender in a standard message, or nil when the text is free text.
    /// "CQ [modifier] <sender> ...", "QRZ <sender> ...", "DE <sender> ..." or "<callsign> <sender> ...".
    private static func standardMessageSenderIndex(_ words: [String]) -> Int? {
        var index = 1
        if ["CQ", "QRZ", "DE"].contains(words[0]) {
            while index < words.count - 1, isCQModifier(words[index]) { index += 1 }
            return index < words.count && looksLikeCallsign(words[index]) ? index : nil
        }
        return looksLikeCallsign(words[0]) && words.count >= 2 && looksLikeCallsign(words[1]) ? 1 : nil
    }

    private static func isCQModifier(_ word: String) -> Bool {
        let letters = word.count <= 4 && word.allSatisfy { $0.isASCII && $0.isLetter }
        let digits = word.count == 3 && word.allSatisfy { $0.isASCII && $0.isNumber }
        return letters || digits
    }

    /// A word that could be a callsign in a message: a hashed "<...>" form, a placeholder word, or letters and
    /// digits with at least one of each. Wider than the shape rule on purpose: a word that is nearly a
    /// callsign still has to be the operator's.
    private static func looksLikeCallsign(_ word: String) -> Bool {
        if word.hasPrefix("<") && word.hasSuffix(">") { return true }
        if placeholderCallsigns.contains(word) { return true }
        let allowed = word.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "/" }
        return allowed && word.contains(where: \.isNumber) && word.contains(where: \.isLetter)
    }

    private static func isLocatorWord(_ word: String) -> Bool {
        word != "RR73" && word.range(of: #"^[A-R]{2}[0-9]{2}$"#, options: .regularExpression) != nil
    }

    // MARK: - The operator's saved callsign and locator, for screens that do not hold the app state

    /// Station profiles mirror the active callsign and locator to these keys (AppStatePersistence).
    private static let savedCallsignKeys = ["operatorCallsign", "stationCallsign"]

    /// The saved callsign as entered: empty when none is saved or it is a placeholder word.
    static func savedEnteredCallsign(defaults: UserDefaults = .standard) -> String {
        for key in savedCallsignKeys {
            let value = enteredCallsign(defaults.string(forKey: key))
            if !value.isEmpty { return value }
        }
        return ""
    }

    /// The saved callsign when it is usable for transmitting, otherwise nil.
    static func savedOperatorCallsign(defaults: UserDefaults = .standard) -> String? {
        usableCallsign(savedEnteredCallsign(defaults: defaults))
    }

    /// Why the saved callsign may not be used for transmitting, or nil when it may.
    static func savedCallsignRefusal(defaults: UserDefaults = .standard) -> String? {
        callsignRefusal(savedEnteredCallsign(defaults: defaults))
    }

    /// The saved locator (4, 6, 8 or 10 characters) when there is a valid one, otherwise nil.
    static func savedOperatorLocator(defaults: UserDefaults = .standard) -> String? {
        locator(defaults.string(forKey: "stationGrid"))
    }

    // MARK: - The Stations screen

    /// A note for the Stations screen after a profile has been saved: what in it will not be accepted for
    /// transmitting, or nil. Only a value that was entered and is refused is reported; a profile without a
    /// locator is fine for logging, so a missing value is not reported. Saving itself is never blocked.
    static func stationNote(callsign: String?, grid: String?) -> String? {
        var notes: [String] = []
        if !isPlaceholderCallsign(callsign), callsignRefusal(callsign) != nil { notes.append(callsignRejectedMessage) }
        if !normalized(grid).isEmpty, ft8Locator(grid) == nil { notes.append(locatorRejectedMessage) }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    /// The line under the Stations form after a save: `text`, then the note of `stationNote` when there is one.
    /// Both ways of saving ("Save" and "Save and activate") build their line with this.
    static func stationStatus(_ text: String, callsign: String?, grid: String?) -> String {
        guard let note = stationNote(callsign: callsign, grid: grid) else { return text }
        return text + " " + note
    }

    /// True for a plain "Saved ..." line, which the Stations screen shows in green; a line that carries a note
    /// is shown in orange.
    static func isPlainSavedStatus(_ status: String) -> Bool {
        status.hasPrefix("Saved") && !status.contains(callsignRejectedMessage) && !status.contains(locatorRejectedMessage)
    }
}
