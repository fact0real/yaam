//
//  DataSafetySettingsView.swift
//  YAAM
//

import AppKit
import SwiftUI

struct DataSafetySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var backupToRestore: BackupSnapshot?
    @State private var isBiometricsEnabled: Bool = CredentialVault.isBiometricLockEnabled
    @State private var biometricTestStatus: String = ""
    @AppStorage("uploadShareNameAndQTH") private var uploadShareNameAndQTH = false
    @AppStorage("uploadShareContactDetails") private var uploadShareContactDetails = false
    @AppStorage("uploadShareFreeText") private var uploadShareFreeText = false

    var body: some View {
        VStack(spacing: 0) {
            safetyHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    credentialSecuritySection
                    PublicDataFeedSettingsView()
                    personalDataSection
                    restorePoints
                    auditTrail
                }
                .padding(18)
            }
        }
        .onAppear { appState.refreshDatabaseSafetyState() }
        .alert("Restore This Version?", isPresented: Binding(
            get: { backupToRestore != nil },
            set: { if !$0 { backupToRestore = nil } }
        )) {
            Button("Cancel", role: .cancel) { backupToRestore = nil }
            Button("Restore", role: .destructive) {
                if let snapshot = backupToRestore {
                    appState.restoreDatabaseBackup(snapshot)
                }
                backupToRestore = nil
            }
        } message: {
            Text("YAAM will first create an automatic rollback point, then restore profiles and QSOs from the selected version.")
        }
    }

    private var safetyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 40, height: 40)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protected Master Log")
                        .font(.headline)
                    Text(appState.databaseStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    appState.checkDatabaseIntegrity()
                } label: {
                    Label("Verify", systemImage: "checkmark.shield")
                }
                Button {
                    appState.createManualDatabaseBackup()
                } label: {
                    Label("New Restore Point", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderedProminent)
            }

            if let url = appState.protectedDatabaseURL {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text(url.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show database in Finder")
                }
            }
        }
        .padding(16)
    }

    private var restorePoints: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Restore Points", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if appState.backupSnapshots.isEmpty {
                Text("No restore points yet. YAAM creates them daily and before imports, migrations, and restores.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.backupSnapshots) { snapshot in
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snapshot.reason)
                                    .font(.callout.weight(.medium))
                                Text("\(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: snapshot.sizeBytes, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                backupToRestore = snapshot
                            } label: {
                                Label("Restore", systemImage: "arrow.counterclockwise")
                            }
                        }
                        .padding(.vertical, 9)
                        if snapshot.id != appState.backupSnapshots.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var auditTrail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Safety Activity", systemImage: "list.bullet.clipboard")
                .font(.headline)

            if appState.recentDatabaseAuditEvents.isEmpty {
                Text("No database activity has been recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    ForEach(appState.recentDatabaseAuditEvents.prefix(20)) { event in
                        GridRow {
                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(event.action.replacingOccurrences(of: "-", with: " ").capitalized)
                                .font(.caption.weight(.semibold))
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var credentialSecuritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Secure Vault & Biometrics", systemImage: "lock.shield.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "touchid")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Hardware-Bound AES-256-GCM Vault")
                                .font(.callout.weight(.semibold))
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        Text("Passwords and API secrets are protected by machine hardware UUID and AES-256-GCM encryption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if CredentialVault.isBiometricsAvailable {
                        Toggle(isOn: $isBiometricsEnabled) {
                            Text("Unlock with \(CredentialVault.biometryTypeDescription)")
                                .font(.callout.weight(.medium))
                        }
                        .toggleStyle(.switch)
                        .onChange(of: isBiometricsEnabled) { _, newValue in
                            CredentialVault.isBiometricLockEnabled = newValue
                            if newValue {
                                Task {
                                    let ok = await CredentialVault.authenticateWithBiometrics()
                                    if !ok {
                                        isBiometricsEnabled = false
                                        CredentialVault.isBiometricLockEnabled = false
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Multi-prompt Keychain loops permanently eliminated. Zero password dialogs on recompile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if CredentialVault.isBiometricsAvailable {
                        Button {
                            Task {
                                biometricTestStatus = "Authenticating..."
                                let success = await CredentialVault.authenticateWithBiometrics(reason: "Testing Touch ID sensor functionality for YAAM")
                                biometricTestStatus = success ? "Verified successfully" : "Authentication failed or cancelled"
                            }
                        } label: {
                            Label("Test \(CredentialVault.biometryTypeDescription)", systemImage: "touchid")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !biometricTestStatus.isEmpty {
                    Text(biometricTestStatus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(biometricTestStatus.contains("successfully") ? .green : .orange)
                        .transition(.opacity)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    /// What QRZ, eQSL, Club Log, HRDLog, HamQTH and Wavelog may receive of the other station's personal data
    /// (QSLUploadStatus.uploadFields). LoTW never receives it.
    private var personalDataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Logbook upload privacy", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $uploadShareNameAndQTH) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload the other station's name and QTH")
                            .font(.callout.weight(.medium))
                        Text("Shares NAME and QTH with QRZ, eQSL, Club Log, HRDLog, HamQTH and Wavelog.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $uploadShareContactDetails) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload contact details and precise locations")
                            .font(.callout.weight(.medium))
                        Text("Shares the other station’s e-mail, postal address, web page, notes, QSL route and precise location, plus your own street address, postal code and precise location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $uploadShareFreeText) {
                    Text("Upload comments and QSL messages")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                Text("Free text can contain personal information. YAAM’s internal comment tags are always removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("All sharing switches are off by default. Callsigns, QSO details, award locations and grids up to 6 characters are still uploaded. LoTW receives only signing fields; its station location is also controlled by TrustedQSL. Local exports keep the full record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }
}
