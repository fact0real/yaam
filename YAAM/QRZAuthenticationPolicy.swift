import Foundation

nonisolated enum QRZAuthenticationState: Equatable, Sendable {
    case loading, signIn, challenge, authenticated, failed
    var title: String {
        switch self {
        case .loading: return "Checking QRZ sign-in"
        case .signIn: return "Sign in to QRZ"
        case .challenge: return "Complete verification on QRZ"
        case .authenticated: return "Authenticated session verified"
        case .failed: return "Sign-in needs attention"
        }
    }
    var symbol: String {
        switch self {
        case .loading: return "arrow.triangle.2.circlepath"
        case .signIn: return "person.crop.circle.badge.key"
        case .challenge: return "lock.shield"
        case .authenticated: return "checkmark.shield.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
nonisolated enum QRZAuthenticationPolicy {
    static func trustedHost(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "qrz.com" || host.hasSuffix(".qrz.com")
    }
    static func evaluate(url: URL?, logout: Bool, loginForm: Bool, challenge: Bool, sessionCookie: Bool) -> QRZAuthenticationState {
        guard let url, url.scheme == "https", trustedHost(url.host ?? "") else { return .failed }
        let path = url.path.lowercased()
        if challenge || ["mfa", "2fa", "challenge", "verify"].contains(where: path.contains) { return .challenge }
        if loginForm || path.contains("login") { return .signIn }
        return logout && sessionCookie ? .authenticated : .signIn
    }
    static let inspectionScript = #"""
    (() => {
      const visible = e => !!e && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
      const inputs = Array.from(document.querySelectorAll('input')).filter(visible);
      const loginForm = inputs.some(e => e.type === 'password');
      const challenge = inputs.some(e => e.autocomplete === 'one-time-code' || /^(otp|totp|mfa|authcode|verification_code)$/i.test(e.name)) ||
        Array.from(document.querySelectorAll('iframe')).filter(visible).some(e => /captcha|challenge/.test(e.src)) ||
        /verify you are human|checking your browser|complete the security check/i.test(document.body?.innerText || '');
      const logout = Array.from(document.querySelectorAll('a[href],form[action]')).some(e => {
        try { const u = new URL(e.href || e.action, location.href);
          return u.protocol === 'https:' && (u.hostname === 'qrz.com' || u.hostname.endsWith('.qrz.com')) && /^\/(logout|signout)(\/|$)/i.test(u.pathname) && visible(e);
        } catch { return false; }
      });
      return {logout, loginForm, challenge};
    })()
    """#
}

nonisolated struct QRZAuthenticationAttempt {
    private(set) var generation = 0
    private(set) var cancelled = false
    private(set) var delivered = false
    mutating func navigate() { generation += 1 }
    mutating func cancel() { cancelled = true; generation += 1 }
    func canCapture(ticket: Int) -> Bool { !cancelled && !delivered && generation == ticket }
    mutating func saved(_ success: Bool) { if success { delivered = true } }
}
