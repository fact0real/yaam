//
//  SettingsView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/31/26.
//

import SwiftUI

// MARK: - macOS Preferences & Credentials Settings Sheet
struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, qrz, lotw
    }
    
    @AppStorage("operatorCallsign") private var operatorCallsign = ""
    
    @AppStorage("qrzUsername") private var qrzUsername = ""
    @AppStorage("qrzPassword") private var qrzPassword = ""
    @AppStorage("qrzApiKey") private var qrzApiKey = ""
    
    @AppStorage("lotwUsername") private var lotwUsername = ""
    @AppStorage("lotwPassword") private var lotwPassword = ""

    var body: some View {
        TabView {
            // MARK: - General Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Station Details")
                        .font(.headline)
                    TextField("My Callsign:", text: $operatorCallsign)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("This callsign is used as the default operator station for API queries and log exports.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(Tabs.general)
            
            // MARK: - QRZ.com Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("QRZ.com Integration")
                        .font(.headline)
                    
                    TextField("Username:", text: $qrzUsername)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Password:", text: $qrzPassword)
                        .textFieldStyle(.roundedBorder)
                    
                    Divider()
                    
                    TextField("XML API Key:", text: $qrzApiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("The API Key is required for fetching logbook confirmations. A valid QRZ XML Subscription is required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("QRZ.com", systemImage: "q.circle.fill")
            }
            .tag(Tabs.qrz)
            
            // MARK: - LoTW Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Logbook of The World (LoTW)")
                        .font(.headline)
                    
                    TextField("Username:", text: $lotwUsername)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Password:", text: $lotwPassword)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Credentials are used to securely download your latest TQSL verification records directly from ARRL servers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("LoTW", systemImage: "globe.americas.fill")
            }
            .tag(Tabs.lotw)
        }
        .padding(10)
    }
}
