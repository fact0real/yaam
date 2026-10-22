import Foundation

// Transmit-safety regression (Y-001, B-018): the notices kept in TransmitNotices (a PTT safety timer released a
// radio) must be on screen where the operator transmits: the FT8 station, the digital modes station and the Radio
// Control popover, with the triangle on the Radio Control button. Only the operator closes one; nothing closes it on
// a timer. SwiftUI screens cannot be rendered here, so this test builds TransmitNoticesView with the real model and
// reads the screens' source (comments removed, so a comment that mentions the view does not count).
// Build and run from the repository root (Tests/run-cw-safety-regressions.sh does it):
//   swiftc <flags> -module-name YAAM Tests/TransmitNoticesShownRegression.swift YAAM/TransmitNotices.swift \
//     YAAM/TransmitNoticesView.swift -o tns && ./tns

@main
struct TransmitNoticesShownRegression {
    static var failures = 0

    static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if !condition { failures += 1 }
    }

    /// The file without its string literals and `//` comments, so neither a comment nor a text that mentions the
    /// view counts.
    static func code(_ file: String) -> String? {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let noStrings = String(line).replacingOccurrences(of: #""([^"\\]|\\.)*""#, with: "\"\"",
                                                              options: .regularExpression)
            return noStrings.range(of: "//").map { String(noStrings[..<$0.lowerBound]) } ?? noStrings
        }.joined(separator: "\n")
    }

    /// The part of `text` from `start` up to `end`, or "" if either is missing.
    static func section(_ text: String, from start: String, to end: String) -> String {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return "" }
        return String(text[a.upperBound..<b.lowerBound])
    }

    static func main() {
        // The view uses the shared model, and closing a notice removes that one only.
        let view = TransmitNoticesView()
        check(view.notices === TransmitNotices.shared, "the view shows TransmitNotices.shared")
        TransmitNotices.shared.post(TransmitNotices.Source(name: "TX-500"), text: "TX-500: PTT had been on for 181 s")
        TransmitNotices.shared.post(TransmitNotices.Source(name: "rigctld"), text: "rigctld: PTT had been on for 181 s")
        let first = TransmitNotices.shared.notices[0]
        TransmitNotices.shared.dismiss(first.id)
        check(TransmitNotices.shared.notices.map(\.source.name) == ["rigctld"], "closing one notice leaves the other")

        for file in ["YAAM/FT8StationView.swift", "YAAM/DigitalModemStationView.swift", "YAAM/RigControlToolbarView.swift"] {
            guard let text = code(file) else {
                check(false, "\(file): the file can be read (run from the repository root)")
                continue
            }
            check(text.contains("TransmitNoticesView()"), "\(file) shows TransmitNoticesView")
        }
        if let ft8 = code("YAAM/FT8StationView.swift") {
            // The connection panel folds away once the radio is connected, which is when a safety timer fires, and the
            // controls above the waterfall scroll: the notice goes above them, where it stays in sight.
            check(section(ft8, from: "GeometryReader { geometry in", to: "upperStationControls").contains("TransmitNoticesView()"),
                  "FT8 shows the notices above the controls that scroll (and the connection panel in them)")
            check(!section(ft8, from: "var upperStationControls", to: "var radioConnectionPanel").contains("TransmitNoticesView()"),
                  "FT8 does not show them inside the controls that scroll")
            check(!section(ft8, from: "var radioConnectionPanel", to: "private var tx500Settings").contains("TransmitNoticesView()"),
                  "FT8 does not show them (only) inside the connection panel")
        }
        if let toolbar = code("YAAM/RigControlToolbarView.swift") {
            check(toolbar.contains("|| !transmitNotices.notices.isEmpty {"),
                  "the Radio Control button shows its triangle while a notice is kept")
            check(toolbar.contains("transmitNotices.notices.last?.text ??"),
                  "the Radio Control button's help tag shows the notice")
        }
        if let source = code("YAAM/TransmitNoticesView.swift") {
            check(source.contains("ForEach(notices.notices)"), "the view lists every notice")
            check(source.contains("notices.dismiss(notice.id)"), "the view's button closes that notice")
            let timers = ["Timer", "asyncAfter", "Task.sleep", ".task", "onAppear", "lineLimit"]
                .filter { source.contains($0) }
            check(timers.isEmpty, "nothing closes or shortens a notice without the operator"
                  + (timers.isEmpty ? "" : " (found: \(timers.joined(separator: ", ")))"))
        }
        if failures > 0 { print("Transmit notices shown regression FAILED (\(failures))"); exit(1) }
        print("Transmit notices shown regression passed")
    }
}
