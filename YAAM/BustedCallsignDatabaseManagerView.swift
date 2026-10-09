//
//  BustedCallsignDatabaseManagerView.swift
//  YAAM
//
//  Busted Callsign Intelligence & Multi-Source Database Manager
//  ("مدیریت پایگاه‌های داده اعتبارسنجی و تصحیح هوشمند کال‌ساین")
//  Allows 1-click downloading, updating, and calibrating databases from
//  Super Check Partial (SCP), ARRL LoTW, Club Log, and interactive error testing.
//

import AppKit
import Combine
import SwiftUI

struct BustedCallsignDatabaseManagerView: View {
    @ObservedObject private var engine = BustedCallsignEngine.shared
    @EnvironmentObject var appState: AppState

    // Interactive Testing Sandbox State
    @State private var testCallsign: String = ""
    @State private var testMode: String = "CW"
    @State private var testResult: BustedCallsignSuggestion? = nil

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header Banner
                headerBanner

                // Master Multi-Source Status & Update Button
                masterSyncCard

                // Individual Database Cards
                databaseSourcesSection

                // Algorithm Tuning & Sensitivity Controls
                algorithmTuningSection

                // Interactive Error Testing Sandbox
                interactiveTestingSandbox
            }
            .padding(18)
        }
    }

    // MARK: - 1. Header Banner
    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                BustedCallsignIconView(size: 24, isSelected: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Busted Callsign Intelligence & Verification Databases")
                        .font(.headline)
                    Text("Multi-source database downloading and acoustic/Morse error correction")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Enable Detection", isOn: $engine.isEnabled)
                    .toggleStyle(.switch)
            }
        }
    }

    // MARK: - 2. Master Sync Card
    private var masterSyncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(engine.totalVerifiedCallsigns > 0 ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text("\(engine.totalVerifiedCallsigns.formatted()) VERIFIED CALLSIGNS LOADED")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.primary)
                    }

                    if let lastUpdated = engine.lastUpdatedDate {
                        Text("Last updated: \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Using bundled verified starter database. Update from web recommended.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task {
                        await engine.updateAllDatabases()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if engine.isDownloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(engine.isDownloading ? "Downloading..." : "Update All Databases Now")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.orange)
                .disabled(engine.isDownloading)
            }

            if engine.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: engine.downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)

                    Text(engine.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }

    // MARK: - 3. Database Sources Section
    private var databaseSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AUTHORITATIVE DATA SOURCES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            // Super Check Partial Card
            databaseCard(
                title: "Super Check Partial (SCP)",
                subtitle: "Active contest and DXpedition callsigns community database",
                sourceTag: "MASTER.SCP",
                recordCount: engine.scpCallCount > 0 ? "\(engine.scpCallCount.formatted()) callsigns" : "Built-in fallback",
                urlText: "https://www.supercheckpartial.com/MASTER.SCP",
                icon: "star.shield.fill",
                color: .blue
            ) {
                Task {
                    await engine.downloadSCP()
                    engine.loadStoredDatabases()
                }
            }

            // ARRL LoTW User Activity Card
            databaseCard(
                title: "ARRL Logbook of The World (LoTW)",
                subtitle: "Active worldwide stations uploading digital QSL confirmations",
                sourceTag: "lotw-user-activity.csv",
                recordCount: engine.lotwCallCount > 0 ? "\(engine.lotwCallCount.formatted()) active users" : "Not yet downloaded",
                urlText: "https://lotw.arrl.org/lotw-user-activity.csv",
                icon: "checkmark.seal.fill",
                color: .green
            ) {
                Task {
                    await engine.downloadLoTW()
                    engine.loadStoredDatabases()
                }
            }

            // Local Logbook & Call History
            HStack(spacing: 12) {
                Image(systemName: "book.fill")
                    .font(.title2)
                    .foregroundStyle(Color.purple)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Local Master Log & Call History")
                            .font(.subheadline.bold())
                        Text("INTERNAL")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(Color.purple)
                    }

                    Text("Automatically cross-references your own \(appState.qsoRecords.count.formatted()) logged QSOs to boost confidence for repeat contacts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(appState.qsoRecords.count.formatted()) QSOs")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.2), lineWidth: 1))
        }
    }

    private func databaseCard(
        title: String,
        subtitle: String,
        sourceTag: String,
        recordCount: String,
        urlText: String,
        icon: String,
        color: Color,
        onDownload: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(sourceTag)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(color)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(urlText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(recordCount)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.primary)

                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(engine.isDownloading)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - 4. Algorithm Tuning & Sensitivity Controls
    private var algorithmTuningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ERROR DETECTION SENSITIVITY & ALERTS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(spacing: 14) {
                // CW Morse Dit/Dah Sensitivity
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CW Morse Rhythm & Dit/Dah Tolerance")
                            .font(.caption.bold())
                        Text("Controls sensitivity to dropped/extra dits and split letter spacing errors.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Slider(value: $engine.cwSensitivity, in: 0.5...1.0, step: 0.05)
                        .frame(width: 140)

                    Text("\(Int(engine.cwSensitivity * 100))%")
                        .font(.caption.monospaced().bold())
                        .frame(width: 36, alignment: .trailing)
                }

                Divider()

                // Voice Phonetic Confusion Sensitivity
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Phonetic Mishear Sensitivity (SSB/AM)")
                            .font(.caption.bold())
                        Text("Sensitivity to rhyming plosives (B/D/V/P/T), nasals (M/N), and static friction.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Slider(value: $engine.voiceSensitivity, in: 0.5...1.0, step: 0.05)
                        .frame(width: 140)

                    Text("\(Int(engine.voiceSensitivity * 100))%")
                        .font(.caption.monospaced().bold())
                        .frame(width: 36, alignment: .trailing)
                }

                Divider()

                // Audio Chime Toggle
                Toggle("Play Audio Alert Chime when Busted Call is Detected", isOn: $engine.audioChimeEnabled)
                    .font(.caption)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 5. Interactive Testing Sandbox
    private var interactiveTestingSandbox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INTERACTIVE TEST SANDBOX")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Type any suspected callsign below to test the engine's diagnosis and proposed correction in real-time:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Callsign to test", text: $testCallsign)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .frame(maxWidth: 240)

                    Picker("Mode", selection: $testMode) {
                        Text("📻 CW (Morse)").tag("CW")
                        Text("🎙 Voice (SSB)").tag("SSB")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Button("Analyze") {
                        testResult = engine.evaluate(callsign: testCallsign, mode: testMode, logRecords: appState.qsoRecords)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                // Result Box
                if let result = testResult {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("PROPOSED CORRECTION:")
                                .font(.caption.bold())
                            Text(result.country.flagEmoji)
                            Text(result.suggestedCall)
                                .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                            Text("— \(result.country.entityName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(result.confidencePercentage)% Confidence")
                                .font(.caption.monospaced().bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(result.confidenceColor.opacity(0.2), in: Capsule())
                                .foregroundStyle(result.confidenceColor)
                        }

                        Text("Diagnosis: \(result.explanation)")
                            .font(.caption)
                            .foregroundStyle(.primary)

                        if let morse = result.morseDetail {
                            Text("Morse Structure: \(morse)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let phone = result.phoneticDetail {
                            Text("Phonetic Structure: \(phone)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3), lineWidth: 1))
                } else if !testCallsign.isEmpty {
                    if engine.isVerifiedCallsign(testCallsign) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.green)
                            Text("'\(testCallsign)' is an exact verified callsign in the active database. No error detected.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                            Text("No high-confidence correction found for '\(testCallsign)'.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
        }
        .onAppear {
            testResult = engine.evaluate(callsign: testCallsign, mode: testMode, logRecords: appState.qsoRecords)
        }
    }
}
