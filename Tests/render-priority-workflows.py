"""Render the actual changed SwiftUI surfaces with isolated, inert service fixtures."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/yaam-priority-visual')
out.mkdir(parents=True, exist_ok=True)
login = (root / 'YAAM/QRZLoginView.swift').read_text().split('// MARK: - WKWebView Representable')[0]
login = login.replace('@State private var authState = QRZAuthenticationState.signIn', '@State private var authState = QRZAuthenticationState.challenge')
login = login.replace('Please log in to QRZ.com (supports MFA/2FA)...', 'Complete the verification code on QRZ. This window stays open until authentication is verified.')
settings = (root / 'YAAM/DataSafetySettingsView.swift').read_text()
settings = settings[settings.index('    private var credentialSecuritySection:'):settings.index('    /// What QRZ, eQSL')]
row = (root / 'YAAM/OperatorDeskView.swift').read_text()
row = row[row.index('private struct RecentQSORowView:'):row.index('private struct QuickLogPanel:')]
source = r'''
import AppKit
import SwiftUI
import WebKit
struct QSORecordModel: Identifiable { var id = UUID(); var fields: [String:String] = [:]; var isConfirmed = false; subscript(_ key: String) -> String { fields[key] ?? "" } }
@MainActor final class AppState: ObservableObject {
 func appendLog(_ text: String) {}
 func saveQRZSessionCookies(_ cookies: [HTTPCookie]) -> Bool { false }
 func showNativeAlert(title: String, message: String) {}
}
@MainActor enum CredentialVault {
 static var isBiometricLockEnabled = true
 static var isBiometricsAvailable = true
 static var biometryTypeDescription = "Touch ID"
 static var isVaultSessionUnlocked = false
 static func authenticateWithBiometrics(reason: String = "Test") async -> Bool { false }
}
@MainActor enum KeychainStore { static var storageFailure: String? }
extension View { func resizablePresentation(minWidth: CGFloat, minHeight: CGFloat) -> some View { self } }
struct QRZWebViewStore: View {
 @Binding var statusText: String
 @Binding var authState: QRZAuthenticationState
 let saveRequestID: Int
 let reloadRequestID: Int
 var onCookieCaptured: ([HTTPCookie]) -> Bool
 var body: some View {
  VStack(alignment: .leading, spacing: 16) {
   Label("QRZ · Verification", systemImage: "lock.shield").font(.title2.bold())
   Text("Browser area — isolated MFA fixture").foregroundStyle(.secondary)
   Divider()
   Text("Enter the verification code supplied by QRZ.")
   TextField("Verification code", text: .constant("")).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
   Text("No account, network request, Keychain or logbook is used by this visual test.").font(.caption).foregroundStyle(.secondary)
   Spacer()
  }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
 }
}
struct VaultFixture: View {
 @State private var biometricTestStatus = ""
 @State private var biometricTestSucceeded: Bool?
 @State private var isBiometricsEnabled = true
 var body: some View { credentialSecuritySection }
''' + settings + '\n}\n' + login + '\n' + row + r'''
@MainActor func snapshot<V: View>(_ root: V, name: String, width: CGFloat, height: CGFloat, dark: Bool) throws {
 let app = NSApplication.shared; app.setActivationPolicy(.accessory)
 let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
 app.appearance = appearance
 let view = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light).background(Color(nsColor: .windowBackgroundColor)))
 view.appearance = appearance
 let size = CGSize(width: width, height: height)
 let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
 window.contentView = view; view.frame = CGRect(origin: .zero, size: size)
 window.makeKeyAndOrderFront(nil)
 RunLoop.current.run(until: Date().addingTimeInterval(0.2))
 view.layoutSubtreeIfNeeded(); window.display()
 let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
 view.cacheDisplay(in: view.bounds, to: bitmap)
 try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
 window.orderOut(nil)
}
@main struct Main {
 @MainActor static func main() throws {
  let record = QSORecordModel(fields: ["CALL":"W1AW", "QSO_DATE":"20261020", "TIME_ON":"123400", "BAND":"20m", "FREQ":"14.074", "MODE":"FT8", "RST_SENT":"-05", "RST_RCVD":"-11"])
  for dark in [false, true] {
   for width in [760.0,1100.0] {
    let suffix = "\(dark ? "dark" : "light")-\(Int(width))"
    KeychainStore.storageFailure = "The credential key is unavailable in the macOS Keychain. Unlock the login Keychain and retry. The saved vault has been preserved."
    try snapshot(ScrollView { VStack(alignment: .leading, spacing: 22) {
     VaultFixture()
     Text("Recent contact · copy as a new draft").font(.headline)
     RecentQSORowView(record: record, isEven: true, onLoad: {}, onDelete: {})
     Text("The New action asks before replacing the draft; it does not edit the original contact.").font(.caption).foregroundStyle(.secondary)
     CloudUploadStatusCard(notice: .needsAttention, message: "QRZ did not acknowledge acceptance. LoTW already accepted this contact. Review QRZ before retrying.", pendingCount: 1, canRetry: true, retry: {}, dismiss: {})
     CloudUploadStatusCard(notice: .waiting, message: "Waiting for a connection; accepted destinations stay complete.", pendingCount: 2, canRetry: false, retry: {}, dismiss: {})
     CloudUploadStatusCard(notice: .accepted, message: "The selected destinations accepted the contact.", pendingCount: 0, canRetry: false, retry: {}, dismiss: {})
    }.padding(24) }, name: "workflows-" + suffix, width: width, height: 850, dark: dark)
   }
   for width in [540.0,760.0] {
    try snapshot(QRZLoginView().environmentObject(AppState()), name: "qrz-mfa-\(dark ? "dark" : "light")-\(Int(width))", width: width, height: 600, dark: dark)
   }
  }
 }
}
'''
with tempfile.TemporaryDirectory(prefix='yaam-priority-render-') as tmp:
    swift = Path(tmp) / 'Review.swift'
    swift.write_text(source)
    binary = Path(tmp) / 'review'
    names = ['CloudUploadStatusCard','UploadFileReader','QRZAuthenticationPolicy','OperatorModels','AmateurBandSettings','PortableActivity','DXCCDatabase','CountryFlagEngine','CountryNameNormalizer','QSOMetadataFormatter']
    subprocess.run(['swiftc','-parse-as-library',str(swift),*[str(root/'YAAM'/f'{x}.swift') for x in names],'-o',str(binary)], check=True)
    subprocess.run([str(binary),str(out)], check=True)
print(out)
