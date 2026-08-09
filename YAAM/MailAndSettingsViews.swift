//
//  MailAndSettingsViews.swift
//  YAAM
//
//  Created by EP2AES on 8/8/26.
//

import SwiftUI

// MARK: - Email Composer Sheet
struct EmailComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @AppStorage("stationCallsign") private var savedStationCallsign: String = ""
    @AppStorage("qrzUsername") private var qrzUser: String = ""
    @AppStorage("lotwUsername") private var lotwUser: String = ""
    
    @State private var selectedTemplate: String = "QSL Request"
    @State private var emailSubject: String = ""
    @State private var emailBody: String = ""
    @State private var isSending: Bool = false
    
    // Debugger States
    @State private var showDebugLog: Bool = false
    @State private var smtpDebugOutput: String = ""
    
    let templates = ["QSL Request", "Sked Request", "LoTW Confirmation"]
    
    // Strict Callsign Resolver
    private var resolvedMyCallsign: String {
        let saved = savedStationCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty && !saved.contains("@") { return saved.uppercased() }

        let qrz = qrzUser.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qrz.isEmpty && !qrz.contains("@") { return qrz.uppercased() }

        let lotw = lotwUser.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lotw.isEmpty && !lotw.contains("@") { return lotw.uppercased() }

        if let recCall = appState.qsoRecords.first(where: {
            let c = $0["STATION_CALLSIGN"].trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && !c.contains("@")
        })?["STATION_CALLSIGN"] {
            return recCall.uppercased()
        }

        if let recOp = appState.qsoRecords.first(where: {
            let o = $0["OPERATOR"].trimmingCharacters(in: .whitespaces)
            return !o.isEmpty && !o.contains("@")
        })?["OPERATOR"] {
            return recOp.uppercased()
        }

        return "EP2AES"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send Email to \(appState.selectedEmailCallsign)")
                .font(.headline)
            
            HStack {
                Text("To:")
                    .fontWeight(.bold)
                Text(appState.selectedEmailAddress)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Picker("Template:", selection: $selectedTemplate) {
                    ForEach(templates, id: \.self) { tmpl in
                        Text(tmpl).tag(tmpl)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: selectedTemplate) { _, newValue in
                    loadTemplate(newValue)
                }
            }
            
            Divider()
            
            TextField("Subject", text: $emailSubject)
                .textFieldStyle(.roundedBorder)
            
            if showDebugLog {
                // MARK: - Debug Terminal Console
                VStack(alignment: .leading) {
                    Text("SMTP Connection Log:")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.red)
                    TextEditor(text: $smtpDebugOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)
                        .background(Color.black.opacity(0.8))
                        .frame(minHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red, lineWidth: 1))
                }
            } else {
                TextEditor(text: $emailBody)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }
            
            HStack {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Authenticating & Sending...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") { dismiss() }
                    .disabled(isSending)
                
                Button(action: sendMail) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text(showDebugLog ? "Retry Sending" : "Send Email")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isSending || appState.selectedEmailAddress.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580, height: showDebugLog ? 500 : 430)
        .onAppear {
            loadTemplate(selectedTemplate)
        }
    }
    
    private func loadTemplate(_ template: String) {
        let myCall = resolvedMyCallsign
        let targetCall = appState.selectedEmailCallsign
        
        switch template {
        case "QSL Request":
            emailSubject = "QSL Request for our QSO - \(myCall)"
            emailBody = "Hello \(targetCall),\n\nThanks for the nice QSO. I would love to exchange QSL cards with you. Please let me know if you prefer direct or via bureau.\n\n73,\n\(myCall)"
        case "Sked Request":
            emailSubject = "Sked Request - \(myCall)"
            emailBody = "Hi \(targetCall),\n\nI am trying to work your DXCC. Are you available for a sked on 20m or 15m sometime this week?\n\nBest 73,\n\(myCall)"
        case "LoTW Confirmation":
            emailSubject = "LoTW Confirmation Reminder - \(myCall)"
            emailBody = "Hello \(targetCall),\n\nJust a quick reminder: could you please upload our recent QSO to LoTW? It would help me a lot with my DXCC award.\n\nThank you & 73,\n\(myCall)"
        default:
            break
        }
    }
    
    private func sendMail() {
        isSending = true
        showDebugLog = false
        
        appState.sendEmail(to: appState.selectedEmailAddress, subject: emailSubject, body: emailBody) { success, log in
            DispatchQueue.main.async {
                self.isSending = false
                if success {
                    self.appState.alertTitle = "Email Sent Successfully 🚀"
                    self.appState.alertMessage = "Your email has been dispatched via SMTP."
                    self.appState.showAlert = true
                    self.dismiss()
                } else {
                    // Show raw debug terminal inline!
                    self.smtpDebugOutput = log
                    self.showDebugLog = true
                }
            }
        }
    }
}

// MARK: - SMTP & Station Settings Sheet
struct SMTPSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("stationCallsign") private var stationCallsign = "EP2AES"
    @AppStorage("smtpHost") private var smtpHost = "smtp.gmail.com"
    @AppStorage("smtpPort") private var smtpPort = "465"
    @AppStorage("smtpUser") private var smtpUser = ""
    @AppStorage("smtpPass") private var smtpPass = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("SMTP & Station Configuration")
                    .font(.headline)
            }
            
            Text("Enter your station callsign and SMTP settings. For Gmail / Google Workspace, use your 16-character App Password.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Form {
                TextField("My Station Callsign (e.g. EP2AES):", text: $stationCallsign)
                TextField("SMTP Host (e.g. smtp.gmail.com):", text: $smtpHost)
                TextField("SMTP Port (465 for SSL or 587 for TLS):", text: $smtpPort)
                TextField("Email Address:", text: $smtpUser)
                SecureField("App Password (spaces auto-removed):", text: $smtpPass)
            }
            .padding(.vertical, 8)
            
            HStack {
                Spacer()
                Button("Save & Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
