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
                    minWidth: 1000,
                    idealWidth: 1620,
                    maxWidth: .infinity,
                    minHeight: 620,
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
                Button("Quick Log QSO") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 0
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Digital Call Roster (Live FT8)") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 20
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("CW Keyer Memories Console") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 14
                    appState.cwWorkstationSection = 0
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("CW Academy & Trainer") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 14
                    appState.cwWorkstationSection = 1
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("CW Q-Codes & Prosigns Reference") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 14
                    appState.cwWorkstationSection = 2
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])

                Button("Real-Time CW Audio Decoder") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 14
                    appState.cwWorkstationSection = 3
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("3D Globe & Grid Tracker") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 12
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("6m Magic Band Watch") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 11
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Contest Operations & Cabrillo") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 4
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Contest Calendar") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 9
                }

                Button("Open DX Cluster") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 1
                }

                Button("Bandmap Studio") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 13
                }
                .keyboardShortcut("b", modifiers: [.command, .option])

                Button("Club Log Personal Spots") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 10
                }

                Button("DX News & Intelligence") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 21
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Sync Center (LoTW & QRZ)") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 2
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("ON4KST Chat & Skeds") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 17
                }

                Button("QSL Labels Studio") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 19
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Connected Station (Ecosystem)") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 8
                }

                Button("Shack Clock & Mission Control (HamClock)") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 22
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button("Open Shack Clock in Separate Window...") {
                    openWindow(id: YAAMWindowID.hamClock)
                }

                Divider()

                Button("Network Transceiver Emulator (IC-705 LAN)") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 24
                }
                .keyboardShortcut("e", modifiers: [.command, .option])

                Button("Open Transceiver Emulator in Separate Window...") {
                    openWindow(id: YAAMWindowID.transceiverEmulator)
                }

                Divider()

                Button("Multi-Rig FT8 Cluster (SO3R)...") {
                    openWindow(id: YAAMWindowID.multiRigFT8)
                }
                .keyboardShortcut("8", modifiers: [.command, .option])

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
                    minWidth: 1200,
                    idealWidth: 1360,
                    maxWidth: .infinity,
                    minHeight: 640,
                    idealHeight: 740,
                    maxHeight: .infinity
                )
                .resizablePresentation(minWidth: 1200, minHeight: 640)
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
