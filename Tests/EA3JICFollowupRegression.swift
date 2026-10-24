import Foundation

@main struct EA3JICFollowupRegression {
    static func main() throws {
        let endpoint = URL(string: "https://api.github.com/repos/fact0real/yaam/releases/latest")!
        func check(_ status: Int, _ tag: String?, _ current: String = "1.37.49", url: String = "https://github.com/fact0real/yaam/releases/tag/v1.38.0") -> GitHubReleaseCheck.Outcome {
            let json: [String: Any] = tag.map { ["tag_name": $0, "html_url": url] } ?? ["message":"rate limited"]
            return GitHubReleaseCheck.evaluate(data: try! JSONSerialization.data(withJSONObject: json),
                response: HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: nil, headerFields: nil), currentVersion: current)
        }
        func isFailure(_ outcome: GitHubReleaseCheck.Outcome) -> Bool { if case .failed = outcome { return true }; return false }
        precondition(isFailure(check(403, nil)))
        precondition(isFailure(check(429, "v1.38.0")))
        precondition(isFailure(check(200, nil)))
        precondition(isFailure(check(200, "v1.38.0-rc1")))
        precondition(isFailure(check(200, "v1.38.0", url: "https://github.com.evil.invalid/fact0real/yaam/releases/tag/v1.38.0")))
        precondition(check(200, "v1.37.49") == .current)
        precondition(check(200, "v1.37.9") == .current)
        precondition(check(200, "v1.37.49", "1.37.50") == .current)
        if case .available = check(200, "v1.38.0") {} else { preconditionFailure("Newer release missing") }
        let beforeMidnight=["CALL":"EA3JIC", "QSO_DATE":"20261023", "TIME_ON":"235950", "BAND":"20M", "MODE":"FT8"]
        var afterMidnight=beforeMidnight
        afterMidnight["QSO_DATE"]="20261024"; afterMidnight["TIME_ON"]="000010"
        precondition(QSOIdentity.isSameQSO(lhs: beforeMidnight, rhs: afterMidnight, timeToleranceSeconds: 20))
        precondition(!QSOIdentity.isSameQSO(lhs: beforeMidnight, rhs: afterMidnight, timeToleranceSeconds: 19))
        precondition(QSOIdentity.bestToleranceMatch(incoming: afterMidnight, candidates: [beforeMidnight], toleranceSeconds: 20)==0)
        precondition(QSOIdentity.newRecords([afterMidnight], existing: [beforeMidnight], toleranceSeconds: 20).isEmpty)
        precondition(QSOIdentity.exactKey(fields: beforeMidnight) != QSOIdentity.exactKey(fields: afterMidnight))
        var offOnly=beforeMidnight
        offOnly["TIME_ON"]=""; offOnly["TIME_OFF"]="000010"; offOnly["QSO_DATE_OFF"]="20261024"
        precondition(QSOIdentity.isSameQSO(lhs: afterMidnight, rhs: offOnly))
        afterMidnight["QSO_DATE"]="20261025"
        precondition(!QSOIdentity.isSameQSO(lhs: beforeMidnight, rhs: afterMidnight, timeToleranceSeconds: 3600))
        afterMidnight["QSO_DATE"]="20260230"
        precondition(!QSOIdentity.isSameQSO(lhs: afterMidnight, rhs: afterMidnight, timeToleranceSeconds: 20))
        afterMidnight["QSO_DATE"]="20261024"; afterMidnight["TIME_ON"]=""
        precondition(QSOIdentity.bestToleranceMatch(incoming: afterMidnight, candidates: [beforeMidnight], toleranceSeconds: 3600)==nil)
        precondition(QSOIdentity.newRecords([afterMidnight], existing: [beforeMidnight], toleranceSeconds: 3600).count==1)

        let slot = Date(timeIntervalSince1970: 1_000)
        precondition(FT8TransmissionTiming.canStart(slot: slot, now: slot.addingTimeInterval(-0.2)))
        precondition(FT8TransmissionTiming.canStart(slot: slot, now: slot.addingTimeInterval(0.09)))
        precondition(!FT8TransmissionTiming.canStart(slot: slot, now: slot.addingTimeInterval(0.11)))
        precondition(!FT8TransmissionTiming.canStart(slot: slot, now: slot.addingTimeInterval(60)))
        precondition(LocalClusterWirePolicy.line("EA3JIC\r\nDX injected\u{1b}") == "EA3JICDX injected")
        precondition(LocalClusterWirePolicy.xml("A&B<one>\"'") == "A&amp;B&lt;one&gt;&quot;&apos;")
        precondition(LocalClusterWirePolicy.line(String(repeating: "a", count: 10000)).count == 512)
        print("EA3JIC follow-up: release status, numeric versions, slot deadline and spot escaping passed")
    }
}
