//  In the name of Allah
//  YAAMApp.swift
//
//  Created by factoreal on 7/29/26.
//

import SwiftUI
import Combine

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
            }
            
            // MARK: - Tools Menu Commands
            CommandMenu("Tools") {
                Button("Quick Log QSO") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 0
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Open DX Cluster") {
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 1
                }

                Divider()

                Button("Log Statistics...") { appState.showStatsSheet = true }
                    .keyboardShortcut("t", modifiers: .command)
                
                Button("Sync Confirmations (LoTW & QRZ)") { appState.syncConfirmations() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            
            // MARK: - Application Info & Help Commands
            CommandGroup(replacing: .appInfo) {
                Button("About YAAM") { appState.showAboutDialog() }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") { appState.checkForUpdates() }
            }
            CommandGroup(replacing: .help) {
                Button("ADIF Log Processor Help") { openWindow(id: "help-window") }
            }
        }
        
        // MARK: - Native macOS Settings Window
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 980, height: 700)
        }
        #endif

        // MARK: - Help Secondary Window Scene
        Window("ADIF Processor Help & FAQ", id: "help-window") {
            HelpView()
                .frame(minWidth: 820, idealWidth: 980, minHeight: 600, idealHeight: 700)
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)
    }
}
