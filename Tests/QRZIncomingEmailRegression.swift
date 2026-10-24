// swiftc -parse-as-library Tests/QRZIncomingEmailRegression.swift YAAM/QRZIncomingEmailLookup.swift -o /tmp/yaam-incoming-email-test
import Foundation
import WebKit

@MainActor enum QRZWebKitSession {
    static let userAgent = "YAAM regression"
    static func browserLikeConfiguration() -> WKWebViewConfiguration { WKWebViewConfiguration() }
    static func browserLikeRequest(url: URL, timeoutInterval: TimeInterval) -> URLRequest { URLRequest(url: url) }
}
@MainActor enum QRZSessionStore { static func restoreToWebKit(completion: (() -> Void)? = nil) { completion?() } }

@main struct QRZIncomingEmailRegression {
    @MainActor static func main() async {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool) { precondition(condition()); checks += 1 }
        func status(_ text: String = "", call: String = "W1AW", path: String = "https://www.qrz.com/db/W1AW",
                    profile: String = "W1AW", field: Bool = true, encoded: String = "", blocked: Bool = false, authenticated: Bool = true) -> QRZIncomingEmailStatus {
            QRZIncomingEmailEvidence.status(call: call, url: URL(string: path), profileCall: profile,
                fieldExists: field, fieldText: text, encodedEmail: encoded, blocked: blocked, authenticated: authenticated)
        }
        for text in ["none", "(none)", "No email address published", "not provided", "not listed.", "Not available"] {
            expect(status(text) == .notPublished)
        }
        expect(status("") == .unavailable)
        expect(status("none", authenticated: false) == .signInRequired)
        expect(status("none", profile: "", authenticated: false) == .signInRequired)
        expect(status("W1AW@ARRL.ORG") == .available("W1AW@ARRL.ORG"))
        expect(status("operator@example.org", authenticated: false) == .signInRequired)
        expect(status("operator@example.org") == .available("operator@example.org"))
        expect(status("Login required to view") == .signInRequired)
        expect(status("Hover to reveal email") == .unavailable)
        expect(status("", field: false) == .unavailable)
        expect(status("", blocked: true) == .unavailable)
        expect(status("none", path: "https://www.qrz.com/login") == .unavailable)
        expect(status("none", path: "http://www.qrz.com/db/W1AW") == .unavailable)
        expect(status("none", path: "https://www.qrz.com.evil.example/db/W1AW") == .unavailable)
        expect(status("none", profile: "K1ABC") == .unavailable)
        expect(status("none", path: "https://www.qrz.com/db/K1ABC") == .unavailable)
        expect(status("none", call: "W1AW\";alert(1);//") == .unavailable)
        expect(status("none", encoded: "broken") == .unavailable)
        expect(status("none", encoded: "prefix!9999999999") == .unavailable)
        expect(status("<script>not provided</script>") == .unavailable)
        expect(status("name@example.org\r\nBcc: other@example.org") == .unavailable)
        expect(status("contact one@example.org or two@example.org") == .unavailable)
        let email = "test@example.org"
        let encoded = email.reversed().map { "x" + String($0) }.joined() + "!" + String(String(email.count).reversed())
        expect(status("", encoded: encoded) == .available(email))
        expect(status("none", call: "ea8/w1aw", path: "https://www.qrz.com/db/EA8/W1AW", profile: "EA8/W1AW") == .notPublished)
        expect(QRZIncomingEmailEvidence.normalizedCall(" w1aw ") == "W1AW")
        for text in ["", "../../x", "https://evil.com", "W1AW?x=1", "W1AW\nK1ABC", "W1AW#bio", String(repeating: "A", count: 31)] {
            expect(QRZIncomingEmailEvidence.normalizedCall(text) == nil)
        }
        for state: QRZIncomingEmailStatus in [.unchecked, .checking, .available(email), .signInRequired, .unavailable] {
            expect(!state.permitsMissingEmailRejection)
        }
        expect(QRZIncomingEmailStatus.notPublished.permitsMissingEmailRejection)
        expect(QRZIncomingEmailEvidence.rejectionComment.contains("no email"))
        expect(!QRZIncomingEmailEvidence.rejectionComment.contains("not in my log"))

        // Late results after station change or dismissal cannot restore stale absence evidence.
        var pending: CheckedContinuation<QRZIncomingEmailStatus, Never>?
        var lookups = 0
        let checker = QRZIncomingEmailChecker(lookup: { _ in
            lookups += 1
            return await withCheckedContinuation { pending = $0 }
        })
        checker.check("w1aw")
        await Task.yield()
        expect(checker.status(for: "W1AW") == .checking)
        checker.check("K1ABC")
        expect(lookups == 1)
        checker.reset()
        pending?.resume(returning: .notPublished)
        await Task.yield()
        expect(checker.status(for: "W1AW") == .unchecked)
        expect(checker.checkingCall == nil)
        let fresh = QRZIncomingEmailChecker(lookup: { _ in .notPublished })
        fresh.check("w1aw")
        for _ in 0..<10 { await Task.yield() }
        expect(fresh.status(for: "W1AW") == .notPublished)
        fresh.reset()
        expect(fresh.status(for: "W1AW") == .unchecked)
        let page = EmailFixturePage()
        for (html, expected) in [
            ("<td id='csdata'><span class='hamcall'>W1AW</span><p>Email: (none)</p></td>", QRZIncomingEmailStatus.notPublished),
            ("<td id='csdata'><span class='hamcall'>W1AW</span><p>Email: Login required to view</p></td>", .signInRequired),
            ("<td id='csdata'><span class='hamcall'>W1AW</span><p>Email: <span id='qem'>operator@example.org</span></p></td>", .available("operator@example.org")),
            ("<td id='csdata'><span class='hamcall'>W1AW</span><p>Email: <span id='qem'></span></p></td>", .unavailable),
            ("<td id='csdata'><span class='hamcall'>W1AW</span></td><div id='biodata'><p>Email: none</p></div>", .unavailable),
            ("<td id='csdata'><span class='hamcall'>W1AW</span><p>Email: none</p></td><div id='biodata'>unrelated@example.org</div>", .notPublished),
            ("<td id='csdata'><span class='hamcall'>K1ABC</span><p>Email: none</p></td>", .unavailable),
            ("<td id='csdata'><span class='hamcall'>W1AW</span><p>Email: none</p></td><form id='challenge-form'></form>", .unavailable)
        ] {
            let evidence = await page.read(html)
            expect(QRZIncomingEmailEvidence.status(call: "W1AW", url: URL(string: "https://www.qrz.com/db/W1AW"),
                profileCall: evidence["profileCall"] as? String ?? "", fieldExists: evidence["fieldExists"] as? Bool ?? false,
                fieldText: evidence["fieldText"] as? String ?? "", encodedEmail: evidence["encodedEmail"] as? String ?? "",
                blocked: evidence["blocked"] as? Bool ?? true, authenticated: true) == expected)
        }
        for (html, expected) in [
            ("<div id='qrztop'><div style='display:none'><a href='https://www.qrz.com/manager'>Account</a><a href='https://www.qrz.com/logout/fixturetoken'>Logout</a></div></div>", true),
            ("<div id='qrztop'><a href='https://www.qrz.com/login'>Login</a></div>", false),
            ("<div id='qrztop'><a href='https://www.qrz.com/manager'>Account</a><a style='display:none' href='https://www.qrz.com/logout'>Logout</a></div>", false),
            ("<div id='qrztop'><a href='https://evil.example/manager'>Account</a><a style='display:none' href='https://evil.example/logout/fixturetoken'>Logout</a></div>", false),
            ("<div id='biodata'><a href='https://www.qrz.com/manager'>Account</a><a style='display:none' href='https://www.qrz.com/logout/fixturetoken'>Logout</a></div>", false)
        ] {
            let auth = await page.read(html, script: QRZAuthenticationPolicy.inspectionScript)
            expect((auth["logout"] as? Bool ?? false) == expected)
        }
        print("QRZ Incoming email: \(checks) checks passed (absence vs failure, source/identity, hostile input, cancellation and station reset).")
    }
}

@MainActor final class EmailFixturePage: NSObject, WKNavigationDelegate {
    private let view: WKWebView = {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: config)
    }()
    private var ready: CheckedContinuation<Void, Never>?
    func read(_ html: String, script: String = QRZIncomingEmailEvidence.script) async -> [String: Any] {
        view.navigationDelegate = self
        await withCheckedContinuation { continuation in
            ready = continuation
            view.loadHTMLString("<html><body><table><tr>" + html + "</tr></table></body></html>", baseURL: nil)
        }
        return (try? await view.evaluateJavaScript(script)) as? [String: Any] ?? [:]
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready?.resume(); ready = nil }
}
