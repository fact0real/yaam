import Foundation

struct WebSDRConsensusInput {
    let id: String
    let receiverID: String
    let slotStart: Date
    let text: String
}

struct WebSDRConsensusGroup {
    let slotStart: Date
    let text: String
    let observationIDs: [String]
    let receiverIDs: Set<String>
}

/// Align receiver clocks only when two distinct, non-repeating messages support
/// the same whole-slot offset. A single repeated CQ cannot establish alignment.
enum WebSDRConsensusBuilder {
    static func build(_ inputs: [WebSDRConsensusInput], primaryReceiverID: String?) -> [WebSDRConsensusGroup] {
        let byReceiver = Dictionary(grouping: inputs, by: \.receiverID)
        let anchor = primaryReceiverID.flatMap { byReceiver[$0] } ??
            byReceiver.keys.sorted().first.flatMap { byReceiver[$0] } ?? []
        var offsets: [String: Int] = [:]
        if let anchorID = anchor.first?.receiverID { offsets[anchorID] = 0 }
        let anchorByText = Dictionary(grouping: anchor, by: \.text)
        for (receiverID, observations) in byReceiver where offsets[receiverID] == nil {
            let ownByText = Dictionary(grouping: observations, by: \.text)
            var votes: [Int: Set<String>] = [:]
            for (text, own) in ownByText {
                guard own.count == 1, let matching = anchorByText[text], matching.count == 1 else { continue }
                let delta = Int((own[0].slotStart.timeIntervalSince(matching[0].slotStart) / 15).rounded())
                guard abs(delta) <= 4 else { continue }
                votes[delta, default: []].insert(text)
            }
            if let winner = votes.max(by: {
                if $0.value.count != $1.value.count { return $0.value.count < $1.value.count }
                if abs($0.key) != abs($1.key) { return abs($0.key) > abs($1.key) }
                return $0.key > $1.key
            }), winner.value.count >= 2 {
                offsets[receiverID] = winner.key
            }
        }

        struct Key: Hashable { let slot: Int; let text: String }
        var grouped: [Key: [WebSDRConsensusInput]] = [:]
        for input in inputs {
            let originalSlot = Int((input.slotStart.timeIntervalSince1970 / 15).rounded())
            let key = Key(slot: originalSlot - (offsets[input.receiverID] ?? 0), text: input.text)
            grouped[key, default: []].append(input)
        }
        return grouped.map { key, observations in
            WebSDRConsensusGroup(
                slotStart: Date(timeIntervalSince1970: Double(key.slot * 15)),
                text: key.text,
                observationIDs: observations.map(\.id),
                receiverIDs: Set(observations.map(\.receiverID)))
        }.sorted { a, b in
            if a.slotStart != b.slotStart { return a.slotStart > b.slotStart }
            if a.receiverIDs.count != b.receiverIDs.count {
                return a.receiverIDs.count > b.receiverIDs.count
            }
            return a.text < b.text
        }
    }
}
