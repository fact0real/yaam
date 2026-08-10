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
    
    @State private var selectedTemplate: String = "QSL Card Request"
    @State private var emailSubject: String = ""
    @State private var emailBody: String = ""
    @State private var isSending: Bool = false
    
    // Debugger States
    @State private var showDebugLog: Bool = false
    @State private var smtpDebugOutput: String = ""
    
    let templates = ["QSL Card Request", "Sked Request", "LoTW/QRZ Confirmation"]
    
    // DIRECT RESOLVER: Always prioritize the exact clicked row record!
    private var currentQSO: QSORecordModel? {
        if let exactQSO = appState.selectedEmailQSO {
            return exactQSO
        }
        
        let targetCall = appState.selectedEmailCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !targetCall.isEmpty else { return nil }
        
        return appState.qsoRecords.first(where: {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == targetCall &&
            (appState.selectedEmailAddress.isEmpty || $0["EMAIL"] == appState.selectedEmailAddress)
        }) ?? appState.qsoRecords.first(where: {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == targetCall
        })
    }
    
    // Strict Callsign Resolver for My Station
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
                
                // Show exact clicked QSO details badge
                if let qso = currentQSO {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                        Text("\(qso["BAND"]) / \(qso["MODE"])")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)
                }
                
                Spacer()
                
                Picker("Template:", selection: $selectedTemplate) {
                    ForEach(templates, id: \.self) { tmpl in
                        Text(tmpl).tag(tmpl)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250) // ⭐️ FIX: Expanded width to fit long template names
                .onChange(of: selectedTemplate) { _, newValue in
                    loadTemplate(newValue)
                }
            }
            
            Divider()
            
            TextField("Subject", text: $emailSubject)
                .textFieldStyle(.roundedBorder)
            
            if showDebugLog {
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
                
                Button("Cancel") {
                    appState.selectedEmailQSO = nil
                    dismiss()
                }
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
        .frame(width: 580, height: showDebugLog ? 500 : 450)
        .onAppear {
            loadTemplate(selectedTemplate)
        }
        .onChange(of: appState.selectedEmailCallsign) { _, _ in
            loadTemplate(selectedTemplate)
        }
    }
    
    // MARK: - Template Engine with Exact QSO Details Extractor
    private func loadTemplate(_ template: String) {
        let myCall = resolvedMyCallsign
        let targetCall = appState.selectedEmailCallsign
        
        let qso = currentQSO
        let qsoBand = qso?["BAND"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qsoMode = qso?["MODE"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawDate = qso?["QSO_DATE"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qsoTime = qso?["TIME_ON"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qsoFreq = qso?["FREQ"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        let formattedDate = formatDate(rawDate)
        
        var qsoDetailsBlock = ""
        if qso != nil {
            var items: [String] = []
            if !formattedDate.isEmpty { items.append("- Date: \(formattedDate)") }
            if !qsoTime.isEmpty { items.append("- Time: \(qsoTime) UTC") }
            if !qsoBand.isEmpty { items.append("- Band: \(qsoBand)") }
            if !qsoMode.isEmpty { items.append("- Mode: \(qsoMode)") }
            if !qsoFreq.isEmpty { items.append("- Freq: \(qsoFreq) MHz") }
            
            if !items.isEmpty {
                qsoDetailsBlock = "\n\nQSO Details:\n" + items.joined(separator: "\n")
            }
        }
        
        let bandMention = !qsoBand.isEmpty ? " on \(qsoBand)" : ""
        let bandTag = !qsoBand.isEmpty ? " (\(qsoBand))" : ""
        
        switch template {
        case "QSL Card Request":
            emailSubject = "QSL Card Request for our QSO\(bandMention) - \(myCall)"
            emailBody = """
            Hello \(targetCall),

            Thanks for the nice QSO\(bandMention). I would love to exchange QSL cards with you. Please let me know if you prefer direct or via bureau.\(qsoDetailsBlock)

            73,
            \(myCall)
            """
            
        case "Sked Request":
            let skedBands = !qsoBand.isEmpty ? qsoBand : "20m or 15m"
            emailSubject = "Sked Request - \(myCall)"
            emailBody = """
            Hi \(targetCall),

            I am trying to work your DXCC. Are you available for a sked on \(skedBands) sometime this week?

            Best 73,
            \(myCall)
            """
            
        case "LoTW/QRZ Confirmation":
            emailSubject = "LoTW/QRZ Confirmation Reminder\(bandTag) - \(myCall)"
            emailBody = """
            Hello \(targetCall),

            Just a quick reminder regarding our QSO\(bandMention):
            Could you please upload our QSO to LoTW or QRZ? It would help me a lot with my DXCC and Band awards.\(qsoDetailsBlock)

            Thank you & 73,
            \(myCall)
            """
            
        default:
            break
        }
    }
    
    private func formatDate(_ rawDate: String) -> String {
        guard rawDate.count == 8 else { return rawDate }
        let y = rawDate.prefix(4)
        let m = rawDate.dropFirst(4).prefix(2)
        let d = rawDate.suffix(2)
        return "\(y)-\(m)-\(d)"
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
                    self.appState.selectedEmailQSO = nil
                    self.dismiss()
                } else {
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
                Button("Save & Close") {
                    UserDefaults.standard.set(stationCallsign, forKey: "stationCallsign")
                    UserDefaults.standard.set(smtpHost.isEmpty ? "smtp.gmail.com" : smtpHost, forKey: "smtpHost")
                    UserDefaults.standard.set(smtpPort.isEmpty ? "465" : smtpPort, forKey: "smtpPort")
                    UserDefaults.standard.set(smtpUser, forKey: "smtpUser")
                    UserDefaults.standard.set(smtpPass, forKey: "smtpPass")
                    
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
