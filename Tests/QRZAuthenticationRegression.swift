// swiftc -parse-as-library Tests/QRZAuthenticationRegression.swift YAAM/QRZAuthenticationPolicy.swift -o /tmp/yaam-qrz-auth && /tmp/yaam-qrz-auth
import Foundation
@main struct QRZAuthenticationRegression {
    static func main() {
        func state(_ path: String = "/db/W1AW", logout: Bool = false, login: Bool = false, challenge: Bool = false, cookie: Bool = false, host: String = "www.qrz.com", scheme: String = "https") -> QRZAuthenticationState {
            QRZAuthenticationPolicy.evaluate(url: URL(string: "\(scheme)://\(host)\(path)"), logout: logout, loginForm: login, challenge: challenge, sessionCookie: cookie)
        }
        precondition(state(cookie: true) == .signIn, "A pre-auth cookie cannot close sign-in")
        precondition(state("/login", logout: true, cookie: true) == .signIn)
        precondition(state("/mfa", logout: true, cookie: true) == .challenge)
        precondition(state(logout: true, challenge: true, cookie: true) == .challenge)
        precondition(state(logout: true, login: true, cookie: true) == .signIn)
        precondition(state(logout: true) == .signIn, "An expired/missing cookie must not succeed")
        precondition(state(logout: true, cookie: true) == .authenticated)
        precondition(state(logout: true, cookie: true, host: "qrz.com.attacker.test") == .failed)
        precondition(state(logout: true, cookie: true, host: "notqrz.com") == .failed)
        precondition(state(logout: true, cookie: true, scheme: "http") == .failed)
        precondition(QRZAuthenticationPolicy.evaluate(url: nil, logout: true, loginForm: false, challenge: false, sessionCookie: true) == .failed)
        precondition(QRZAuthenticationPolicy.trustedHost(".logbook.qrz.com"))
        var attempt = QRZAuthenticationAttempt()
        let oldTicket = attempt.generation
        attempt.navigate(); precondition(!attempt.canCapture(ticket: oldTicket), "Ignore a late cookie/script callback after navigation")
        let ticket = attempt.generation; precondition(attempt.canCapture(ticket: ticket))
        attempt.saved(false); precondition(attempt.canCapture(ticket: ticket), "A failed vault save remains retryable")
        attempt.saved(true); precondition(!attempt.canCapture(ticket: ticket), "Only deliver a successful session once")
        var cancelled = QRZAuthenticationAttempt(); cancelled.cancel()
        precondition(!cancelled.canCapture(ticket: cancelled.generation), "No callbacks after Cancel or sheet dismissal")
        print("PASS QRZ auth: pre-auth, MFA, logged-out, expired, trusted success, hostile host and insecure navigation")
    }
}
