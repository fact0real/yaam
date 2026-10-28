import Foundation
import Darwin

/// The index and original media are independent of QSO matching and confirmation.
/// All disk operations run on this queue; callers use a background task.
nonisolated final class QSLReceivedCardStore: @unchecked Sendable {
    struct Snapshot: Sendable { let revision: Int; let items: [QSLInboundItem] }
    private struct Index: Codable { let version: Int; let items: [QSLInboundItem] }
    let directory: URL
    private let queue = DispatchQueue(label: "app.yaam.received-cards")
    private var items: [QSLInboundItem]?
    private var diskData: Data?
    private var revision = 0
    private var indexURL: URL { directory.appendingPathComponent("received-cards.json") }

    init(directory: URL) { self.directory = directory }

    func snapshot() throws -> Snapshot {
        try queue.sync { try withIndexLock { try load(); return Snapshot(revision: revision, items: items ?? []) } }
    }

    private func withIndexLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let lockPath = directory.appendingPathComponent(".received-cards.lock").path
        let descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func load() throws {
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            if items != nil && data == diskData { return }
            let index = try JSONDecoder().decode(Index.self, from: data)
            guard index.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            items = index.items
            diskData = data
            revision += 1
        } else if items == nil { items = [] }
        else { throw CocoaError(.fileReadNoSuchFile) }
    }

    private func save(_ updated: [QSLInboundItem]) throws -> Snapshot {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Index(version: 1, items: updated))
        try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        items = updated
        diskData = data
        revision += 1
        return Snapshot(revision: revision, items: updated)
    }

    func insert(_ item: QSLInboundItem) throws -> Snapshot {
        try queue.sync { try withIndexLock {
            try load()
            guard item.stationProfileID != nil else { throw CocoaError(.fileNoSuchFile) }
            var updated = items ?? []
            // A repeated mailbox import must not create another row for the same attachment.
            if let messageID = item.sourceMessageID, updated.contains(where: {
                $0.stationProfileID == item.stationProfileID && $0.sourceMessageID == messageID && $0.filename == item.filename
            }) { return Snapshot(revision: revision, items: updated) }
            if let existing = updated.first(where: { $0.id == item.id }), existing.stationProfileID != item.stationProfileID {
                throw CocoaError(.fileWriteNoPermission)
            }
            var stored = item
            stored.mediaData = nil // Original bytes live in the immutable media file.
            if let index = updated.firstIndex(where: { $0.id == item.id }) {
                updated[index] = stored
            } else { updated.append(stored) }
            return try save(updated)
        } }
    }

    func setStatus(_ status: QSLInboundStatus, id: UUID, profileID: UUID) throws -> Snapshot {
        try queue.sync { try withIndexLock {
            try load()
            var updated = items ?? []
            guard let index = updated.firstIndex(where: { $0.id == id && $0.stationProfileID == profileID }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            updated[index].status = status
            return try save(updated)
        } }
    }

    func attachMedia(_ url: URL, ids: Set<UUID>, profileID: UUID, mode: String = "", matchedQSOID: UUID? = nil) throws -> Snapshot {
        try queue.sync { try withIndexLock {
            try load()
            var updated = items ?? []
            guard !ids.isEmpty, ids.allSatisfy({ id in updated.contains { $0.id == id && $0.stationProfileID == profileID } }) else {
                throw CocoaError(.fileWriteNoPermission)
            }
            for index in updated.indices where ids.contains(updated[index].id) {
                updated[index].mediaFileURL = url
                if !mode.isEmpty { updated[index].mode = mode }
                updated[index].matchedQSOID = matchedQSOID
                updated[index].status = .archived
            }
            return try save(updated)
        } }
    }

    func recordReply(ids: Set<UUID>, profileID: UUID, sentAt: Date, messageID: String) throws -> Snapshot {
        try queue.sync { try withIndexLock {
            try load()
            var updated = items ?? []
            guard !ids.isEmpty, ids.allSatisfy({ id in updated.contains { $0.id == id && $0.stationProfileID == profileID } }) else {
                throw CocoaError(.fileWriteNoPermission)
            }
            for index in updated.indices where ids.contains(updated[index].id) {
                updated[index].replySentAt = sentAt
                updated[index].replyMessageID = messageID
            }
            return try save(updated)
        } }
    }

    func saveMedia(data: Data, preferredName: String) throws -> URL {
        try queue.sync {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let leaf = URL(fileURLWithPath: preferredName).lastPathComponent
                .replacingOccurrences(of: ":", with: "_")
            let url = directory.appendingPathComponent(UUID().uuidString + "-" + (leaf.isEmpty ? "QSL" : leaf))
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}
