import SwiftUI

struct SoftwareUpdateSettingsView: View {
    @ObservedObject private var updater = YAAMUpdater.shared

    var body: some View {
        Form {
            Section("Software Updates") {
                LabeledContent("Installed version") {
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                        .monospacedDigit().textSelection(.enabled)
                }
                Toggle("Automatically check for updates daily", isOn: Binding(
                    get: { updater.automaticallyChecks }, set: { updater.setAutomaticChecks($0) }))
                Toggle("Automatically download updates and install when YAAM quits", isOn: Binding(
                    get: { updater.automaticallyDownloads }, set: { updater.setAutomaticDownloads($0) }))
                    .disabled(!updater.automaticallyChecks)
                Text("Automatic downloads are optional. You can always review an available update and install it from the update window.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let date = updater.lastCheck {
                        Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(updater.status).font(.callout).accessibilityLabel("Update status: \(updater.status)")
            }
            Section("Verified delivery") {
                Label("Signed feed and update archives", systemImage: "checkmark.shield")
                Text("Updates come from yaam.asis.sh over HTTPS. Sparkle verifies the publisher's Ed25519 signature before extracting a package and installs through its macOS installer service. Restart waits while a registered radio transmitter or CW Auto-CQ is active.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Update checks do not send your callsign, station location, credentials or logbook. The server receives ordinary connection metadata; system profiling is disabled by default.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Release downloads & installation help", destination: URL(string: "https://yaam.asis.sh/#download")!)
            }
        }
        .formStyle(.grouped)
        .onAppear { updater.start() }
    }
}
