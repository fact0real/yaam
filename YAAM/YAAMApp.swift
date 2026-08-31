//  In the name of Allah
//  YAAMApp.swift
//
//  Created by factoreal on 7/29/26.
//

import SwiftUI
import Combine

enum YAAMWindowID {
    static let statistics = "statistics-window"
    static let console = "activity-console-window"
    static let help = "help-window"
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
                .frame(minWidth: 750, idealWidth: 900, minHeight: 500, idealHeight: 600)
                .onAppear {
                    appState.loadRecentLogsFromDatabase()
                }
        }
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

                Button("6m Magic Band Watch") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 11
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Contest Calendar") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 9
                }

                Button("Open DX Cluster") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 1
                }

                Button("Club Log Personal Spots") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 10
                }

                Divider()

                Button("Log Statistics...") { openWindow(id: YAAMWindowID.statistics) }
                    .keyboardShortcut("t", modifiers: .command)

                Button("Activity Console...") { openWindow(id: YAAMWindowID.console) }
            }
            
            // MARK: - Application Info & Help Commands
            CommandGroup(replacing: .appInfo) {
                Button("About YAAM") { appState.showAboutDialog() }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") { appState.checkForUpdates() }
            }
            CommandGroup(replacing: .help) {
                Button("ADIF Log Processor Help") { openWindow(id: YAAMWindowID.help) }
            }
        }
        
        // MARK: - Native macOS Settings Window
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(
                    minWidth: 820,
                    idealWidth: 980,
                    maxWidth: .infinity,
                    minHeight: 620,
                    idealHeight: 700,
                    maxHeight: .infinity
                )
                .resizablePresentation(minWidth: 820, minHeight: 620)
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
        Window("ADIF Processor Help & FAQ", id: YAAMWindowID.help) {
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
    }
}
