//  In the name of Allah
//  YAAMApp.swift
//  ADIF to Excel
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
                Button("Import ADIF Log...") {
                    appState.importADIFDialog()
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
                .frame(width: 450, height: 350)
        }
        #endif

        // MARK: - Help Secondary Window Scene
        Window("ADIF Processor Help & FAQ", id: "help-window") {
            HelpView()
                .frame(width: 540, height: 480)
        }
        .windowResizability(.contentSize)
    }
}
