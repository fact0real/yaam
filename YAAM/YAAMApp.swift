//  In the name of Allah
//  YAAMApp.swift
//
//  Created by factoreal on 7/29/26.
//

import AppIntents
import SwiftUI
import Combine

enum YAAMWindowID {
    static let statistics = "statistics-window"
    static let console = "activity-console-window"
    static let help = "help-window"
    static let feedback = "feedback-window"
    static let hamClock = "hamclock-kiosk-window"
    static let transceiverEmulator = "transceiver-emulator-window"
    static let multiRigFT8 = "multi-rig-ft8-window"
}

// MARK: - Main Application Entry Point & Global Menu Commands
@main
struct YAAMApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("YAAM - Yet Another ADIF Manager") {
            ContentView()
                .environmentObject(appState)
                .frame(
                    minWidth: 760,
                    idealWidth: 1620,
                    maxWidth: .infinity,
                    minHeight: 500,
                    idealHeight: 940,
                    maxHeight: .infinity
                )
                .onAppear {
                    appState.loadRecentLogsFromDatabase()
                }
        }
        .defaultSize(width: 1620, height: 940)
        .windowResizability(.contentMinSize)
        .commands {
            // MARK: - File Menu Commands
            CommandGroup(replacing: .newItem) {
                Button("Import Log File...") {
                    appState.importLogDialog()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Save Log") { appState.saveCurrentLog() }
                    .keyboardShortcut("s", modifiers: .command)
                
                Button("Save As...") { appState.saveAsCurrentLog() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                
                Button("Export Filtered Log As...") { appState.exportFilteredLogAs() }
                    .keyboardShortcut("s", modifiers: [.command, .option])

                Divider()

                Button("Export Database Logs...") { appState.openDatabaseExport() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // MARK: - Edit Menu Selection Commands
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Select All QSOs") {
                    appState.selectAllRecords()
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(appState.qsoRecords.isEmpty)

                Button("Deselect All") {
                    appState.clearSelection()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(appState.selectedRecordIDs.isEmpty)
            }
            
            // MARK: - Log & QSL Operations Menu
            CommandMenu("Log") {
                Button("Download LoTW Cloud Logbook...") {
                    appState.confirmAndFetchCloudLogbook()
                }

                Button("Sync Confirmations (LoTW & QRZ)") {
                    appState.syncConfirmations()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Confirmation Reconciliation...") {
                    appState.showConfirmationReconciliationSheet = true
                }

                Button("QRZ Incoming Requests...") {
                    appState.showQRZIncomingSheet = true
                }

                Divider()

                Button("Enrich QSOs") {
                    if !appState.selectedRecordIDs.isEmpty {
                        appState.enrichSelectedRecords()
                    } else {
                        appState.enrichLogData()
                    }
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Backfill Missing QRZ Names & Emails") {
                    appState.backfillMissingQRZEmailsNow()
                }

                Button("Enrich All Contacts (QRZ Emails)...") {
                    if !appState.isBulkQRZEnriching {
                        appState.bulkQRZCompleted = false
                    }
                    appState.showBulkQRZEnrichmentSheet = true
                }
                .disabled(appState.qsoRecords.isEmpty || appState.isEnriching)

                Button("Daily Rank Backfill") {
                    appState.fetchDailyQRZRankBackfill()
                }
                .disabled(appState.isEnriching || appState.dailyRankBackfillCandidateCount == 0 || appState.dailyRankRequestsRemaining == 0)

                Button("Log Assistant...") {
                    appState.showLogAssistantSheet = true
                }

                Divider()

                Button("Send Recent QSL Cards Batch...") {
                    appState.sendRecentConfirmedQSLCardsBatch()
                }
                .disabled(appState.recentConfirmedQSLBatchCandidateCount() == 0 || appState.isSendingBatchMail)

                Button("Remind Recent Unconfirmed Batch...") {
                    appState.sendRecentUnconfirmedReminderBatch()
                }
                .disabled(appState.recentUnconfirmedReminderBatchRecipientCount() == 0 || appState.isSendingBatchMail)

                Divider()

                Button("Review Duplicate QSOs...") {
                    appState.prepareDuplicateReview()
                }
                .disabled(appState.qsoRecords.isEmpty || appState.isAnalyzingDuplicates)

                Button("QRZ Login...") {
                    appState.forceQRZReLogin()
                }
            }

            // MARK: - Tools & Desks Menu
            CommandMenu("Tools") {
                ForEach(OperatorDeskGroup.allCases) { group in
                    Menu {
                        ForEach(group.destinations) { destination in
                            Button {
                                appState.openOperatorDesk(destination)
                            } label: {
                                Label(destination.title, systemImage: destination.icon)
                            }
                            .keyboardShortcut(destination.deskShortcut)
                        }
                    } label: {
                        Label(group.title, systemImage: group.icon)
                    }
                }

                Divider()

                Menu("Open in Separate Window") {
                    Button("Shack Clock") { openWindow(id: YAAMWindowID.hamClock) }
                    Button("Transceiver Emulator") { openWindow(id: YAAMWindowID.transceiverEmulator) }
                    Button("Multi-Rig FT8") { openWindow(id: YAAMWindowID.multiRigFT8) }
                        .keyboardShortcut("8", modifiers: [.command, .option])
                }

                Divider()

                Button("Log Statistics") {
                    appState.selectedTab = 6
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Log Statistics in Separate Window...") {
                    openWindow(id: YAAMWindowID.statistics)
                }

                Button("Activity Console...") { openWindow(id: YAAMWindowID.console) }
            }
            
            // MARK: - Application Info & Help Commands
            CommandGroup(replacing: .appInfo) {
                Button("About YAAM") { appState.showAboutDialog() }
            }
            CommandGroup(after: .appInfo) {
                Button("Submit Feedback & Suggestions...") {
                    appState.showFeedbackSheet = true
                }
                Button("Check for Updates...") { appState.checkForUpdates() }
            }
            CommandGroup(replacing: .help) {
                Button("YAAM User Guide & Documentation") { openWindow(id: YAAMWindowID.help) }
                    .keyboardShortcut("?", modifiers: .command)

                Button("Submit Feedback & Suggestions...") {
                    appState.showFeedbackSheet = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Open Feedback in Separate Window...") {
                    openWindow(id: YAAMWindowID.feedback)
                }
                
                Divider()

                Button("Reveal Activity Audit Log in Finder...") {
                    AuditLogger.shared.revealInFinder()
                }
            }

            CommandGroup(after: .windowArrangement) {
                Button("Fit Window to Screen Width") {
                    fitMainWindowToScreen()
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
            }
        }
        
        // MARK: - Native macOS Settings Window
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(
                    minWidth: 1080,
                    idealWidth: 1280,
                    maxWidth: .infinity,
                    minHeight: 620,
                    idealHeight: 740,
                    maxHeight: .infinity
                )
                .resizablePresentation(minWidth: 1080, minHeight: 620)
        }
        #endif

        Window("Log Statistics & Confirmation Breakdown", id: YAAMWindowID.statistics) {
            StatisticsView()
                .environmentObject(appState)
                .frame(
                    minWidth: 900,
                    idealWidth: 1180,
                    maxWidth: .infinity,
                    minHeight: 620,
                    idealHeight: 780,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)

        Window("YAAM Activity Console", id: YAAMWindowID.console) {
            ActivityConsoleView()
                .environmentObject(appState)
                .frame(
                    minWidth: 720,
                    idealWidth: 980,
                    maxWidth: .infinity,
                    minHeight: 420,
                    idealHeight: 640,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 980, height: 640)
        .windowResizability(.contentMinSize)

        // MARK: - Help Secondary Window Scene
        Window("YAAM Help & FAQ", id: YAAMWindowID.help) {
            HelpView()
                .frame(
                    minWidth: 820,
                    idealWidth: 980,
                    maxWidth: .infinity,
                    minHeight: 600,
                    idealHeight: 700,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)

        // MARK: - Feedback Window Scene
        Window("YAAM Feedback & Suggestions", id: YAAMWindowID.feedback) {
            FeedbackView()
                .environmentObject(appState)
                .frame(
                    minWidth: 700,
                    idealWidth: 800,
                    maxWidth: 950,
                    minHeight: 550,
                    idealHeight: 700,
                    maxHeight: 850
                )
        }
        .defaultSize(width: 800, height: 700)
        .windowResizability(.contentMinSize)

        // MARK: - HamClock Shack Mission Control Standalone Window Scene
        Window("YAAM Shack Clock & Mission Control", id: YAAMWindowID.hamClock) {
            HamClockShackView(isEmbedded: false)
                .environmentObject(appState)
                .frame(
                    minWidth: 1100,
                    idealWidth: 1440,
                    maxWidth: .infinity,
                    minHeight: 680,
                    idealHeight: 900,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)

        // MARK: - Network Transceiver Emulator Standalone Window Scene
        Window("Network Transceiver Emulator", id: YAAMWindowID.transceiverEmulator) {
            NetworkTransceiverEmulatorView(emulator: appState.transceiverEmulator)
                .environmentObject(appState)
                .frame(
                    minWidth: 1000,
                    idealWidth: 1250,
                    maxWidth: .infinity,
                    minHeight: 650,
                    idealHeight: 850,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 1250, height: 850)
        .windowResizability(.contentMinSize)

        // MARK: - Multi-Rig FT8 Cluster Standalone Window Scene
        Window("Multi-Rig FT8 Cluster (SO3R)", id: YAAMWindowID.multiRigFT8) {
            MultiRigFT8View(hub: appState.multiRigFT8Hub)
                .environmentObject(appState)
                .frame(
                    minWidth: 1000,
                    idealWidth: 1540,
                    maxWidth: .infinity,
                    minHeight: 650,
                    idealHeight: 900,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 1540, height: 900)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Window Screen Adaptation Helpers
@MainActor
func fitMainWindowToScreen() {
    guard let window = NSApp.windows.first(where: {
        $0.styleMask.contains(.titled) && ($0.title.contains("YAAM") || $0.canBecomeMain) && !($0 is NSPanel) && !$0.isSheet
    }) else { return }

    let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let screenFrame = screen?.visibleFrame else { return }

    let targetWidth = min(screenFrame.width - 40, max(1560, screenFrame.width * 0.94))
    let targetHeight = min(screenFrame.height - 40, max(880, screenFrame.height * 0.90))

    var newFrame = window.frame
    newFrame.size.width = targetWidth
    newFrame.size.height = max(newFrame.size.height, targetHeight)
    window.setFrame(newFrame, display: true, animate: true)
    window.center()
}
