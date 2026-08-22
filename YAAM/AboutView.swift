//
//  AboutView.swift
//  YAAM
//
//  Created by EP2AES on 8/8/26.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    // Helper property to fetch Build Number from Info.plist
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 10) {
            // 1. App Icon with macOS Shadow
            if let nsImage = NSApplication.shared.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 76, height: 76)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 3)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)
            }

            // 2. App Name
            Text("YAAM")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 2)

            // 3. Version & Build String
            Text("Version \(appState.currentVersion) (Build \(buildNumber))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // 4. Description Text (Fix truncation with lineLimit & fixedSize)
            Text("Advanced Amateur Radio Logbook & QSL Manager for macOS featuring offline confirmation caching, LoTW cloud sync, and real-time QRZ leaderboard analytics.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            // 5. Links Section
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("Official GitHub Repository:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Link("https://github.com/fact0real/yaam", destination: URL(string: "https://github.com/fact0real/yaam")!)
                        .font(.system(size: 12))
                }

                VStack(spacing: 2) {
                    Text("QRZ Leaderboard Standings:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Link("https://qrz-rank.asis.sh/", destination: URL(string: "https://qrz-rank.asis.sh/")!)
                        .font(.system(size: 12))
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 8)

            // 6. Copyright Footer
            VStack(spacing: 2) {
                Text("Developed by EP2AES (fact0real)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("Copyright © 2026 EP2AES. All rights reserved.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // 7. Action Button
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(
            minWidth: 360,
            idealWidth: 420,
            maxWidth: .infinity,
            minHeight: 450,
            idealHeight: 520,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 360, minHeight: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
