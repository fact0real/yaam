import Foundation

@main
struct WebSDRReplyRegression {
    static func main() {
        let target = "EP2AES"
        let grid = WebSDRReplyPlanner.plan(for: "EP2AES K1ABC FN42", targetCallsign: target)!
        precondition(grid.partner == "K1ABC")
        precondition(grid.draft == "K1ABC EP2AES [REPORT]")
        precondition(!WebSDRReplyPlanner.isReady(grid.draft, for: grid, targetCallsign: target))
        precondition(WebSDRReplyPlanner.isReady("K1ABC EP2AES -12", for: grid,
                                                 targetCallsign: target))
        precondition(!WebSDRReplyPlanner.isReady("K1ABC EP2AES R-12", for: grid,
                                                  targetCallsign: target))

        let report = WebSDRReplyPlanner.plan(for: "EP2AES K1ABC -07", targetCallsign: target)!
        precondition(report.draft == "K1ABC EP2AES R[REPORT]")
        precondition(!WebSDRReplyPlanner.isReady(report.draft, for: report, targetCallsign: target))
        precondition(WebSDRReplyPlanner.isReady("K1ABC EP2AES R-14", for: report,
                                                 targetCallsign: target))
        precondition(!WebSDRReplyPlanner.isReady("K1ABC EP2AES -14", for: report,
                                                  targetCallsign: target))

        precondition(WebSDRReplyPlanner.plan(for: "EP2AES K1ABC R-07", targetCallsign: target)?.draft
                     == "K1ABC EP2AES RR73")
        precondition(WebSDRReplyPlanner.plan(for: "EP2AES K1ABC RR73", targetCallsign: target)?.draft
                     == "K1ABC EP2AES 73")
        precondition(WebSDRReplyPlanner.plan(for: "EP2AES K1ABC 73", targetCallsign: target) == nil)
        precondition(WebSDRReplyPlanner.plan(for: "K1ABC EP2AES -07", targetCallsign: target) == nil,
                     "Own outgoing text must never be treated as a partner reply")
        precondition(WebSDRReplyPlanner.plan(for: "CQ K1ABC FN42", targetCallsign: target) == nil)
        print("WebSDR reply sequence regression passed")
    }
}
