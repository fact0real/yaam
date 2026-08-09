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
    
    @State private var selectedTemplate: String = "QSL Request"
    @State private var emailSubject: String = ""
    @State private var emailBody: String = ""
    @State private var isSending: Bool = false
    
    let templates = ["QSL Request", "Sked Request", "LoTW Confirmation"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send Email to \(appState.selectedEmailCallsign)")
                .font(.headline)
            
            // Recipient & Template Info
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
                .frame(width: 200)
                .onChange(of: selectedTemplate) { _, newValue in
                    loadTemplate(newValue)
                }
            }
            
            Divider()
            
            TextField("Subject", text: $emailSubject)
                .textFieldStyle(.roundedBorder)
            
            TextEditor(text: $emailBody)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            
            HStack {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Sending via SMTP...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") { dismiss() }
                    .disabled(isSending)
                
                Button(action: sendMail) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send Email")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isSending || appState.selectedEmailAddress.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .onAppear {
            loadTemplate(selectedTemplate)
        }
    }
    
    // MARK: - Template Engine
    private func loadTemplate(_ template: String) {
        let myCall = UserDefaults.standard.string(forKey: "stationCallsign") ?? "MYCALL"
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
        appState.sendEmail(to: appState.selectedEmailAddress, subject: emailSubject, body: emailBody) { success, msg in
            DispatchQueue.main.async {
                self.isSending = false
                self.appState.alertTitle = success ? "Email Sent 🚀" : "Email Failed 🔴"
                self.appState.alertMessage = msg
                self.appState.showAlert = true
                if success { dismiss() }
            }
        }
    }
}

// MARK: - SMTP Settings Sheet
struct SMTPSettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
                Text("SMTP Server Configuration")
                    .font(.headline)
            }
            
            Text("Configure your email server to send QSL and Sked requests directly from YAAM. (For Gmail, use an App Password).")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Form {
                TextField("SMTP Host (e.g. smtp.gmail.com):", text: $smtpHost)
                TextField("SMTP Port (e.g. 465 or 587):", text: $smtpPort)
                TextField("Email Address:", text: $smtpUser)
                SecureField("Password (or App Password):", text: $smtpPass)
            }
            .padding(.vertical, 8)
            
            HStack {
                Spacer()
                Button("Save & Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 450)
    }
}
