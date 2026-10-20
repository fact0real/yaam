import Foundation

nonisolated struct DigitalContactCompletion: Sendable, Equatable {
    let id: UUID
    let call: String
    let grid: String
    let protocolName: String
    let band: String
    let stationCall: String
    let stationGrid: String
    let startedAt: Date
    let endedAt: Date
    let transmitHz: UInt64?
    let receiveHz: UInt64?
    let sentReport: String
    let receivedReport: String

    var fields: [String: String] {
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = Calendar(identifier: .gregorian); date.timeZone = TimeZone(secondsFromGMT: 0)
        date.dateFormat = "yyyyMMdd"
        var values = ["CALL": call, "BAND": band, "MODE": protocolName == "FT4" ? "MFSK" : protocolName,
                      "QSO_DATE": date.string(from: startedAt), "QSO_DATE_OFF": date.string(from: endedAt),
                      "STATION_CALLSIGN": stationCall, "APP_YAAM_DIGITAL_SESSION_ID": id.uuidString]
        date.dateFormat = "HHmmss"
        values["TIME_ON"] = date.string(from: startedAt); values["TIME_OFF"] = date.string(from: endedAt)
        if protocolName == "FT4" { values["SUBMODE"] = "FT4" }
        if let transmitHz { values["FREQ"] = String(format: "%.6f", Double(transmitHz) / 1_000_000) }
        if let receiveHz { values["FREQ_RX"] = String(format: "%.6f", Double(receiveHz) / 1_000_000) }
        if !grid.isEmpty { values["GRIDSQUARE"] = grid }
        if !stationGrid.isEmpty { values["MY_GRIDSQUARE"] = stationGrid }
        if !sentReport.isEmpty { values["RST_SENT"] = sentReport }
        if !receivedReport.isEmpty { values["RST_RCVD"] = receivedReport }
        return values
    }
}

nonisolated struct DigitalContactTracker {
    private var session: DigitalContactCompletion?
    static func rfFrequency(dialHz: UInt64, audioHz: Float) -> UInt64? {
        guard dialHz > 0, audioHz.isFinite, audioHz >= 0, audioHz <= 96_000 else { return nil }
        let (frequency, overflow) = dialHz.addingReportingOverflow(UInt64(audioHz))
        return overflow ? nil : frequency
    }
    mutating func reset() { session = nil }
    mutating func observe(call: String, grid: String, protocolName: String, band: String, stationCall: String, stationGrid: String,
                          at time: Date, transmitHz: UInt64? = nil, receiveHz: UInt64? = nil, sentReport: Int? = nil, receivedReport: Int? = nil) {
        guard !call.isEmpty, !stationCall.isEmpty, ["FT8", "FT4"].contains(protocolName) else { return }
        let old = session
        let same = old?.call == call && old?.protocolName == protocolName && old?.band == band && old?.stationCall == stationCall
        let current = same ? old : nil
        session = DigitalContactCompletion(id: current?.id ?? UUID(), call: call, grid: grid.isEmpty ? current?.grid ?? "" : grid,
            protocolName: protocolName, band: band, stationCall: stationCall, stationGrid: stationGrid,
            startedAt: min(current?.startedAt ?? time, time), endedAt: max(current?.endedAt ?? time, time),
            transmitHz: transmitHz ?? current?.transmitHz, receiveHz: receiveHz ?? current?.receiveHz,
            sentReport: sentReport.map { String(format: "%+03d", $0) } ?? current?.sentReport ?? "",
            receivedReport: receivedReport.map { String(format: "%+03d", $0) } ?? current?.receivedReport ?? "")
    }
    func completion(call: String, at time: Date) -> DigitalContactCompletion? {
        guard let s = session, s.call == call, time >= s.startedAt else { return nil }
        return DigitalContactCompletion(id: s.id, call: s.call, grid: s.grid, protocolName: s.protocolName, band: s.band,
            stationCall: s.stationCall, stationGrid: s.stationGrid, startedAt: s.startedAt, endedAt: max(time, s.endedAt),
            transmitHz: s.transmitHz, receiveHz: s.receiveHz, sentReport: s.sentReport, receivedReport: s.receivedReport)
    }
}
