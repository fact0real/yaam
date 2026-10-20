import Foundation

nonisolated enum QuickLogReusePolicy {
    /// An explicit new draft contains no persistent QSO identity, upload or confirmation state.
    static func newDraft(from fields: [String: String], now: Date = Date()) -> QuickLogDraft {
        var draft = QuickLogDraft()
        draft.callsign = fields["CALL"] ?? ""
        draft.frequencyMHz = fields["FREQ"] ?? ""
        draft.band = fields["BAND"] ?? ""
        draft.mode = fields["MODE"] ?? ""
        draft.submode = fields["SUBMODE"] ?? ""
        draft.rstSent = fields["RST_SENT"] ?? ""
        draft.rstReceived = fields["RST_RCVD"] ?? ""
        draft.name = fields["NAME"] ?? ""
        draft.qth = fields["QTH"] ?? ""
        draft.grid = fields["GRIDSQUARE"] ?? fields["GRID"] ?? ""
        draft.country = fields["COUNTRY"] ?? ""
        draft.comment = fields["COMMENT"] ?? ""
        draft.startedAt = now; draft.endedAt = now
        draft.source = "Manual — copied as a new draft"
        return draft
    }
}
