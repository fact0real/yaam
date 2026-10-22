//
//  TransmitNotices.swift
//  YAAM
//
//  Transmit-safety notices that must not be lost when the next status replaces a driver's lastMessage (Y-001, B-018):
//  today, a PTT safety timer that released PTT (TXLimits.safetyTimerMessage). FT8 sets "Receive" as soon as its slot
//  ends and the rigctld client's poll rewrites its status every second, so that message was gone before anyone read it.
//  One notice per radio: it stays until the operator acknowledges receive. Screens show `notices`.
//  Each radio posts with its own Source: Multi-Rig makes a rigctld client or Icom network radio per slot, and two radios
//  of the same kind must not replace or clear each other's notice.
//
//  Platform: pure Swift and Combine, no AppKit, so it can be shared with an iPad or iPhone version.
//

import Combine
import Foundation

final class TransmitNotices: ObservableObject {
    static let shared = TransmitNotices()

    /// Who posts a notice: a name for the operator and an identity of its own.
    struct Source: Equatable {
        var name: String
        let id = UUID()
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let source: Source
        let text: String
        let date: Date
    }

    @Published private(set) var notices: [Notice] = []

    /// Shows `text` for `source`, replacing that source's earlier notice.
    func post(_ source: Source, text: String) {
        notices.removeAll { $0.source.id == source.id }
        notices.append(Notice(source: source, text: text, date: Date()))
    }

    /// The operator has read it.
    func dismiss(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }
}
