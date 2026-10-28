import Foundation

@main struct QSLReceivedCardStoreRegression {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = QSLReceivedCardStore(directory: root)
        let first = try store.saveMedia(data: Data([1, 2, 3]), preferredName: "../../qsl_card.jpg")
        let second = try store.saveMedia(data: Data([4, 5, 6]), preferredName: "qsl_card.jpg")
        precondition(first != second && first.deletingLastPathComponent().path == root.path)
        let original = try Data(contentsOf: first)
        precondition(original == Data([1, 2, 3]))
        let owner = UUID(), other = UUID()
        var item = QSLInboundItem(source: .email, filename: "qsl_card.jpg", callsign: "ON5AM", mediaFileURL: first, mediaData: Data([1, 2, 3]))
        item.stationProfileID = owner
        item.sourceMessageID = "inert-fixture"
        let inserted = try store.insert(item)
        precondition(inserted.items.count == 1)
        var duplicate = item
        duplicate = QSLInboundItem(source: .email, filename: item.filename)
        duplicate.stationProfileID = owner
        duplicate.sourceMessageID = item.sourceMessageID
        let replayed = try store.insert(duplicate)
        precondition(replayed.items.count == 1)
        _ = try store.setStatus(.archived, id: item.id, profileID: owner)
        do {
            _ = try store.setStatus(.rejected, id: item.id, profileID: other)
            preconditionFailure("Cross-profile update accepted")
        } catch {}
        _ = try store.recordReply(ids: [item.id], profileID: owner, sentAt: Date(timeIntervalSince1970: 100), messageID: "sent-fixture")
        let parallel = QSLReceivedCardStore(directory: root)
        _ = try parallel.snapshot()
        _ = try store.recordReply(ids: [item.id], profileID: owner, sentAt: Date(timeIntervalSince1970: 101), messageID: "sent-fixture")
        _ = try parallel.setStatus(.archived, id: item.id, profileID: owner)
        let restarted = QSLReceivedCardStore(directory: root)
        let saved = try restarted.snapshot().items
        precondition(saved.count == 1 && saved[0].status == .archived)
        precondition(saved[0].replyMessageID == "sent-fixture" && saved[0].replySentAt != nil)
        precondition(saved[0].mediaData == nil && saved[0].mediaFileURL == first)
        precondition(saved[0].sourceMessageID == item.sourceMessageID && saved[0].stationProfileID == owner)
        precondition(FileManager.default.fileExists(atPath: first.path))
        let index = root.appendingPathComponent("received-cards.json")
        let corrupt = Data("corrupt archive".utf8)
        try corrupt.write(to: index)
        let broken = QSLReceivedCardStore(directory: root)
        do { _ = try broken.insert(item); preconditionFailure("Corrupt index overwritten") } catch {}
        let protected = try Data(contentsOf: index)
        precondition(protected == corrupt)
        let mail = """
        From: =?UTF-8?B?VGVzdA==?= <test@example.org>
        Subject: =?UTF-8?Q?QSL_=E2=80=94_ON5AM?=
        Content-Type: multipart/mixed;
          boundary="outer"

        --outer
        Content-Type: multipart/related; boundary="inner"

        --inner
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        QSO=20confirmed
        --inner
        Content-Type: image/jpeg; name="qsl_card.jpg"
        Content-Transfer-Encoding: base64

        AQID
        --inner--
        --outer
        Content-Type: application/octet-stream
        Content-Disposition: attachment; filename="qsl_card.jpg"
        Content-Transfer-Encoding: base64

        BAUG
        --outer--
        """
        let parsed = QSLMailAttachmentParser.parse(Data(mail.utf8))
        precondition(parsed.from == "Test <test@example.org>" && parsed.subject == "QSL — ON5AM")
        precondition(parsed.attachments.count == 2 && parsed.attachments[0].data != parsed.attachments[1].data)
        precondition(parsed.body.contains("QSO confirmed"))
        print("PASS: restart, original media, filename collisions, replay, profile ownership, corrupt-index protection")
    }
}
