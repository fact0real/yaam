import AppKit
import Foundation
import WebKit

// Regression for the QRZ Awards analysis script (QRZAwardsScraper.awardAnalysisScript).
//
// QRZ answers each "analyze" request with an HTML fragment. parseAnalysis() must:
//   - reject a login / expired-session page ("QRZ session expired during award analysis");
//   - parse a normal fragment into earned == false plus the reported progress.
// `earned` must follow `issued` (null for every award that was sent to QRZ for analysis).
//
// The test does not keep a copy of the script. It reads YAAM/QRZAwardsScraper.swift, takes the
// text of the `awardAnalysisScript` raw string, cuts it before the first statement that touches
// the award page (`var issuedByID`) and evaluates the helper functions, including parseAnalysis,
// in a WKWebView, because the script needs DOMParser. The fixtures are made-up HTML; there is no
// network access.
//
// Needs a macOS login session (WebKit).
//
// Standalone, from the repository root (an optional argument is the path of QRZAwardsScraper.swift):
//   swiftc -parse-as-library Tests/QRZAwardAnalysisRegression.swift -o /tmp/qaa && /tmp/qaa
@main
struct QRZAwardAnalysisRegression {
    static let sessionExpired = "QRZ session expired during award analysis"

    struct Fixture {
        let name: String
        let html: String
        let issued: [String: String]?
        let expect: Expectation
    }

    enum Expectation {
        case error(String)
        case result(earned: Bool, percent: Double, status: String, achievement: String, progressAvailable: Bool)
    }

    static let fixtures: [Fixture] = [
        // (A) A normal analysis fragment: no login form, progress "45 / 100".
        Fixture(
            name: "A normal fragment",
            html: """
            <div class="awardSummary">Achievement: 45 / 100 entities confirmed</div>
            <table><tr><td>Confirmed</td><td>45</td></tr></table>
            """,
            issued: nil,
            expect: .result(earned: false, percent: 45, status: "In progress",
                            achievement: "45 / 100", progressAvailable: true)
        ),
        // (B) Login pages must be rejected, with or without the "Please Sign In" wording.
        Fixture(
            name: "B1 login form with sign-in text",
            html: """
            <form id="login-form" action="/login" method="post">
              <input type="text" name="username"><input type="password" name="password">
              <button type="submit">Sign in</button>
            </form>
            <p>Please Sign In to QRZ</p>
            """,
            issued: nil,
            expect: .error(sessionExpired)
        ),
        Fixture(
            name: "B2 login form without the sign-in text",
            html: """
            <form id="login-form"><input name="username"><input type="password" name="password"></form>
            <p>Continue to the logbook</p>
            """,
            issued: nil,
            expect: .error(sessionExpired)
        ),
        Fixture(
            name: "B3 sign-in text without a form",
            html: "<p>Please Sign In to QRZ</p>",
            issued: nil,
            expect: .error(sessionExpired)
        ),
        // (C) issued == null must not make the award earned.
        Fixture(
            name: "C1 no progress reported, issued null",
            html: "<p>Analysis complete. No matching contacts were found for this award.</p>",
            issued: nil,
            expect: .result(earned: false, percent: 0, status: "Progress unavailable",
                            achievement: "Not reported", progressAvailable: false)
        ),
        Fixture(
            name: "C2 qualified wording, issued null",
            html: "<div class=\"awardSummary\">Congratulations, you have achieved 100 / 100 entities. Apply now.</div>",
            issued: nil,
            expect: .result(earned: false, percent: 100, status: "Qualified to apply",
                            achievement: "100 / 100", progressAvailable: true)
        ),
        // earned still follows an issued award when one is passed in. The app always passes null
        // (an issued award returns before the request is sent), so C3 guards the earned flag itself.
        Fixture(
            name: "C3 issued award object",
            html: "<div class=\"awardSummary\">Achievement: 45 / 100 entities confirmed</div>",
            issued: ["id": "101", "books": "1", "title": "Test Award", "info": "Issued by QRZ Logbook Awards"],
            expect: .result(earned: true, percent: 100, status: "Award received",
                            achievement: "Award received", progressAvailable: true)
        )
    ]

    // MARK: - Reading the real script from the Swift source

    /// Text of the `awardAnalysisScript` raw string, with the indentation of the closing
    /// delimiter removed the way the Swift compiler does.
    static func extractScript(from source: String) -> String? {
        let lines = source.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("awardAnalysisScript = #\"\"\"") }) else { return nil }
        guard let end = lines[(start + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "\"\"\"#"
        }) else { return nil }
        let closing = lines[end]
        let indent = String(closing.prefix(while: { $0 == " " || $0 == "\t" }))
        return lines[(start + 1)..<end].map { line in
            line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : line.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    /// Everything before the first statement that reads the award page: the helper functions only.
    static func helperFunctions(of script: String) -> String? {
        let lines = script.components(separatedBy: "\n")
        guard let cut = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("var issuedByID") }) else {
            return nil
        }
        let helpers = lines[..<cut].joined(separator: "\n")
        return helpers.contains("function parseAnalysis(") ? helpers : nil
    }

    static func locateSource() -> String? {
        var candidates: [String] = []
        if CommandLine.arguments.count > 1 { candidates.append(CommandLine.arguments[1]) }
        candidates.append("YAAM/QRZAwardsScraper.swift")
        let testURL = URL(fileURLWithPath: #filePath)
        candidates.append(testURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("YAAM/QRZAwardsScraper.swift").path)
        return candidates.first { FileManager.default.isReadableFile(atPath: $0) }
    }

    // MARK: - Evaluating in a WKWebView

    @MainActor
    final class Runner: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        var loaded = false
        var outcome: Result<Any, Error>?

        override init() {
            // A non-persistent store keeps the test from creating WebKit data under ~/Library.
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
            super.init()
            webView.navigationDelegate = self
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loaded = true }

        func spin(timeout: TimeInterval, until condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() && Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }

        func run(helpers: String, cases: [[String: Any]]) -> Result<Any, Error>? {
            webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
            spin(timeout: 30) { self.loaded }
            let driver = """
            var out = [];
            cases.forEach(function(item) {
                var descriptor = { id: "101", title: "Test Award", mode: "Mixed", ribbonURL: "" };
                try {
                    out.push({ name: item.name, error: null, result: parseAnalysis(descriptor, item.html, item.issued) });
                } catch (error) {
                    out.push({ name: item.name, error: String(error && error.message || error), result: null });
                }
            });
            return JSON.stringify(out);
            """
            webView.callAsyncJavaScript(helpers + "\n" + driver, arguments: ["cases": cases], in: nil, in: .page) { result in
                self.outcome = result
            }
            spin(timeout: 60) { self.outcome != nil }
            return outcome
        }
    }

    // MARK: - Main

    @MainActor
    static func main() {
        var failures: [String] = []
        func check(_ ok: Bool, _ message: @autoclosure () -> String) {
            if !ok { failures.append(message()) }
        }

        guard let sourcePath = locateSource(),
              let source = try? String(contentsOfFile: sourcePath, encoding: .utf8) else {
            print("FAIL: cannot read YAAM/QRZAwardsScraper.swift (run from the repository root or pass its path)")
            exit(1)
        }
        guard let script = extractScript(from: source), !script.contains("\\#"),
              let helpers = helperFunctions(of: script) else {
            print("FAIL: cannot find the awardAnalysisScript helper functions in \(sourcePath)")
            exit(1)
        }

        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)

        let cases: [[String: Any]] = fixtures.map { fixture in
            [
                "name": fixture.name,
                "html": fixture.html,
                "issued": fixture.issued ?? NSNull()
            ]
        }
        let runner = Runner()
        guard let outcome = runner.run(helpers: helpers, cases: cases) else {
            print("FAIL: the script did not finish in the web view")
            exit(1)
        }
        let rows: [[String: Any]]
        switch outcome {
        case .success(let value):
            guard let json = value as? String, let data = json.data(using: .utf8),
                  let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
                  decoded.count == fixtures.count else {
                print("FAIL: unexpected script result: \(value)")
                exit(1)
            }
            rows = decoded
        case .failure(let error):
            print("FAIL: script error: \(error.localizedDescription)")
            exit(1)
        }

        for (fixture, row) in zip(fixtures, rows) {
            let before = failures.count
            let error = row["error"] as? String
            let result = row["result"] as? [String: Any]
            func compare<T: Equatable>(_ field: String, _ actual: T?, _ expected: T) {
                check(actual == expected, "\(fixture.name): \(field) is \(actual.map { "\($0)" } ?? "missing"), expected \(expected)")
            }
            switch fixture.expect {
            case .error(let message):
                check(error == message, "\(fixture.name): expected error \"\(message)\", got \(describe(error: error, result: result))")
            case .result(let earned, let percent, let status, let achievement, let progressAvailable):
                check(error == nil, "\(fixture.name): expected a result, got error \"\(error ?? "")\"")
                if let result {
                    compare("earned", result["earned"] as? Bool, earned)
                    compare("percent", (result["percent"] as? NSNumber)?.doubleValue, percent)
                    compare("status", result["status"] as? String, status)
                    compare("achievement", result["achievement"] as? String, achievement)
                    compare("progressAvailable", result["progressAvailable"] as? Bool, progressAvailable)
                }
            }
            print((failures.count == before ? "PASS " : "FAIL ") + fixture.name + ": " + describe(error: error, result: result))
        }

        if failures.isEmpty {
            print("QRZ award analysis regression passed: \(fixtures.count) fixtures")
        } else {
            print("QRZ award analysis regression FAILED: \(failures.count) check(s)")
            for failure in failures { print("  - \(failure)") }
            exit(1)
        }
    }

    static func describe(error: String?, result: [String: Any]?) -> String {
        if let error { return "error \"\(error)\"" }
        guard let result else { return "no result" }
        let earned = result["earned"] as? Bool == true
        let percent = (result["percent"] as? NSNumber)?.doubleValue ?? -1
        return "earned=\(earned) percent=\(percent) status=\"\(result["status"] as? String ?? "?")\""
    }
}
