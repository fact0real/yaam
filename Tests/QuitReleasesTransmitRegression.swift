import AppKit
import Foundation

// Behaviour test of quitting (Y-001): YAAMAppDelegate.applicationShouldTerminate releases every path registered with
// TransmitShutdown that is transmitting, not only CW, and then waits (.terminateLater) so that releases sent over the
// network or a queue can go out. With nothing transmitting it quits at once (.terminateNow). Before this change only
// the CW keyer was stopped on quit: FT8 and the digital modes, Radio Control, TCI and the serial radios were left as
// they were.
// It runs the real YAAMAppDelegate with the real CWKeyerService against the recording stand-ins of Tests/Support/,
// and a test path registered with TransmitShutdown. The test checks the reply and the release, and ends before the
// wait is over, so the app is never asked to terminate. Nothing is keyed.
// Build and run from the repository root (Tests/run-cw-safety-regressions.sh does it).

private var failures = 0

private func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("PASS \(name)")
    } else {
        let more = detail()
        print("FAIL \(name)\(more.isEmpty ? "" : "   [\(more)]")")
        failures += 1
    }
}

final class TestPath {
    var transmitting = false
    var released = 0
}

@main
struct QuitReleasesTransmitRegression {
    static func main() {
        let app = NSApplication.shared
        let path = TestPath()
        TransmitShutdown.register("Test path", isTransmitting: { path.transmitting }, release: {
            path.transmitting = false
            path.released += 1
        })

        let sleeping=YAAMAppDelegate()
        path.transmitting=true
        sleeping.releaseBeforeSleep()
        check("Sleep releases active paths without entering permanent shutdown",path.released==1 && !path.transmitting && !TransmitShutdown.isShuttingDown)
        check("Sleep leaves a persistent receive-uncertainty notice",TransmitNotices.shared.notices.contains{$0.text.contains("before Mac sleep")})
        path.released=0
        let idle = YAAMAppDelegate()
        let reply = idle.applicationShouldTerminate(app)
        check("with nothing transmitting, YAAM quits at once", reply == .terminateNow, "\(reply.rawValue)")
        check("and releases nothing", path.released == 0)

        path.transmitting = true
        let busy = YAAMAppDelegate()
        let busyReply = busy.applicationShouldTerminate(app)
        check("with a path transmitting, it is released at once", path.released == 1 && !path.transmitting)
        check("and YAAM waits before quitting, so the release can go out", busyReply == .terminateLater,
              "\(busyReply.rawValue)")
        check("a second quit request while waiting releases nothing again",
              busy.applicationShouldTerminate(app) == .terminateLater && path.released == 1)

        if failures > 0 {
            print("Quit releases transmit regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Quit releases transmit regression passed")
        exit(0) // before the wait ends: the app is never asked to terminate
    }
}
