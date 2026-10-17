import Foundation

@main
struct CWTextSecurityRegression {
    static func main() {
        precondition(MorseTiming.safeText("CQ;TX;") == nil)
        precondition(MorseTiming.safeText("CQ\nT 1\n\\send_morse") == nil)
        precondition(MorseTiming.safeText("CQ\u{001B}2") == nil)
        precondition(MorseTiming.safeText("CQ\u{0000}") == nil)
        precondition(MorseTiming.safeText("CQ\u{007F}") == nil)
        precondition(MorseTiming.safeText("CQ\u{0085}TX") == nil)
        precondition(MorseTiming.safeText("CQ\u{202E}TX") == nil)
        precondition(MorseTiming.safeText("OP JOSÉ\tQTH GIRONA\r\n73") == "OP JOSE QTH GIRONA 73")
        precondition(MorseTiming.safeText(String(repeating: "E", count: 1024)) != nil)
        precondition(MorseTiming.safeText(String(repeating: "E", count: 1025)) == nil)
        precondition(MorseTiming.chunks(of: "CQ", limit: 0).isEmpty)
        precondition(MorseTiming.chunks(of: "CQ", limit: -1).isEmpty)
        let text = "CQ TEST EA3JIC EA3JIC TEST"
        let pieces = MorseTiming.chunks(of: text, limit: 24)
        precondition(pieces.allSatisfy { $0.count <= 24 && !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        precondition(pieces.joined(separator: " ") == text)
        precondition(MorseTiming.duration(of: "T", wpm: 24) > MorseTiming.duration(of: "E", wpm: 24))
        print("CW text security regression passed (15 assertions).")
    }
}
