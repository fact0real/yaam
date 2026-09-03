//
//  MailAndSettingsViews.swift
//  YAAM
//
//  Created by EP2AES on 8/8/26.
//

import SwiftUI
import AppKit

// MARK: - Email Composer Sheet
struct EmailComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var selectedTemplate: String = "QSL Card Request"
    @State private var emailSubject: String = ""
    @State private var emailBody: String = ""
    @State private var isSending: Bool = false
    @AppStorage("qslCardDeliveryEmailSubject") private var qslCardDeliveryEmailSubject = "QSL Card for our QSO - {CALLSIGN} de {MY_CALL}"
    @AppStorage("qslCardDeliveryEmailBody") private var qslCardDeliveryEmailBody = """
Hello {NAME},

It was a genuine pleasure to meet you on the air. I have attached my QSL card for our confirmed contact.{QSO_DETAILS}

Thank you for the QSO. This card was prepared with YAAM.

Warm 73,
{MY_CALL}
"""
    
    // Debugger States
    @State private var showDebugLog: Bool = false
    @State private var smtpDebugOutput: String = ""
    
    let templates = ["QSL Card Request", "Sked Request", "LoTW/QRZ Confirmation", "QRZ Rank Congratulations & QSL", "QRZ Incoming Details", "QSL Card Delivery"]
    
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

    private var unconfirmedQSOsForRequest: [QSORecordModel] {
        if !appState.selectedEmailUnconfirmedQSOs.isEmpty {
            return appState.selectedEmailUnconfirmedQSOs
        }

        let targetCall = appState.selectedEmailCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !targetCall.isEmpty else { return [] }

        return appState.qsoRecords.filter {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == targetCall &&
            !$0.isConfirmed
        }
    }

    private var isIncomingDetailsDraft: Bool {
        selectedTemplate == "QRZ Incoming Details"
    }

    private var hasUsableRecipient: Bool {
        let address = appState.selectedEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }

    private var isLookingUpIncomingRecipient: Bool {
        isIncomingDetailsDraft && appState.incomingEmailLookupCallsign == appState.selectedEmailCallsign
    }
    
    // Strict Callsign Resolver for My Station
    private var resolvedMyCallsign: String {
        let active = appState.currentStationCallsign
        if !active.isEmpty && active != "DEFAULT" { return active }

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

        return "NOCALL"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isIncomingDetailsDraft ? "Request Missing QSO Details" : "Send Email to \(appState.selectedEmailCallsign)")
                        .font(.headline)
                    if isIncomingDetailsDraft, let incoming = appState.selectedEmailIncomingRequest {
                        Text("\(incoming.callsign) · QSO \(incoming.qsoDate.isEmpty ? "date not reported" : incoming.qsoDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Picker("Template:", selection: $selectedTemplate) {
                    ForEach(templates, id: \.self) { tmpl in
                        Text(tmpl).tag(tmpl)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250)
                .onChange(of: selectedTemplate) { _, newValue in
                    loadTemplate(newValue)
                }
            }

            HStack(spacing: 8) {
                Text("To:")
                    .fontWeight(.bold)

                TextField("operator@example.com", text: $appState.selectedEmailAddress)
                    .textFieldStyle(.roundedBorder)

                if isIncomingDetailsDraft {
                    Button {
                        openQRZProfile()
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.bordered)
                    .help("Open \(appState.selectedEmailCallsign) on QRZ.com")
                }
                
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
            }

            if isIncomingDetailsDraft {
                HStack(spacing: 8) {
                    if isLookingUpIncomingRecipient {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: hasUsableRecipient ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasUsableRecipient ? .green : .orange)
                    }
                    Text(appState.incomingEmailDraftNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Draft · Not sent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .padding(10)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.blue.opacity(0.16)))
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
                    resetDraftContext()
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
                .disabled(
                    isSending ||
                    !hasUsableRecipient ||
                    emailSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    emailBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(20)
        .frame(
            minWidth: 580,
            idealWidth: 760,
            maxWidth: .infinity,
            minHeight: 430,
            idealHeight: showDebugLog ? 620 : (isIncomingDetailsDraft ? 560 : 500),
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 580, minHeight: 430)
        .onAppear {
            if let requestedTemplate = appState.selectedEmailTemplate, templates.contains(requestedTemplate) {
                selectedTemplate = requestedTemplate
            } else if let qso = currentQSO, qso.isConfirmed {
                selectedTemplate = "QSL Card Delivery"
            }
            loadTemplate(selectedTemplate)
        }
        .onChange(of: appState.selectedEmailCallsign) { _, _ in
            loadTemplate(selectedTemplate)
        }
        .onDisappear {
            resetDraftContext()
        }
    }
    
    // MARK: - Template Engine with Exact QSO Details Extractor
    private func loadTemplate(_ template: String) {
        let myCall = resolvedMyCallsign
        let targetCall = appState.selectedEmailCallsign
        let requestQSOs = unconfirmedQSOsForRequest

        if !requestQSOs.isEmpty && (template == "QSL Card Request" || template == "LoTW/QRZ Confirmation") {
            let message = appState.confirmationRequestMessage(callsign: targetCall, templateName: template, qsos: requestQSOs)
            emailSubject = message.subject
            emailBody = message.body
            return
        }
        
        let qso = currentQSO
        let qsoBand = qso?["BAND"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qsoMode = qso?["MODE"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawDate = qso?["QSO_DATE"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qsoTime = qso?["TIME_ON"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qsoFreq = qso?["FREQ"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        let formattedDate = formatDate(rawDate)
        let formattedTime = formatTime(qsoTime)
        
        var qsoDetailsBlock = ""
        if qso != nil {
            var items: [String] = []
            if !formattedDate.isEmpty { items.append("- Date: \(formattedDate)") }
            if !formattedTime.isEmpty { items.append("- Time: \(formattedTime) UTC") }
            if !qsoBand.isEmpty { items.append("- Band: \(qsoBand)") }
            if !qsoMode.isEmpty { items.append("- Mode: \(qsoMode)") }
            if !qsoFreq.isEmpty { items.append("- Freq: \(qsoFreq) MHz") }
            
            if !items.isEmpty {
                qsoDetailsBlock = "\n\nQSO Details:\n" + items.joined(separator: "\n")
            }
        }
        
        let bandMention = !qsoBand.isEmpty ? " on \(qsoBand)" : ""
        let bandTag = !qsoBand.isEmpty ? " (\(qsoBand))" : ""
        let greetingName = appState.resolveFirstName(for: targetCall, explicitName: qso?["NAME"])
        
        switch template {
        case "QSL Card Request":
            emailSubject = "QSL Card Request for our QSO\(bandMention) - \(myCall)"
            emailBody = """
            Hello \(greetingName),

            Thanks for the nice QSO\(bandMention). I would love to exchange QSL cards with you. Please let me know if you prefer direct or via bureau.\(qsoDetailsBlock)

            73,
            \(myCall)
            """
            
        case "Sked Request":
            let skedBands = !qsoBand.isEmpty ? qsoBand : "20m or 15m"
            emailSubject = "Sked Request - \(myCall)"
            emailBody = """
            Hi \(greetingName),

            I am trying to work your DXCC. Are you available for a sked on \(skedBands) sometime this week?

            Best 73,
            \(myCall)
            """
            
        case "LoTW/QRZ Confirmation":
            emailSubject = "LoTW/QRZ Confirmation Reminder\(bandTag) - \(myCall)"
            emailBody = """
            Hello \(greetingName),

            Just a quick reminder regarding our QSO\(bandMention):
            Could you please upload our QSO to LoTW or QRZ? It would help me a lot with my DXCC and Band awards.\(qsoDetailsBlock)

            Thank you & 73,
            \(myCall)
            """

        case "QRZ Rank Congratulations & QSL":
            let matchedRank = appState.qrzComparisonRankData.first { $0.callsign?.uppercased() == targetCall.uppercased() }
            let qsoRankVal = formatRankDisplay(qso?["RANK_QSO"]) ?? formatRankDisplay(matchedRank?.rank_qso) ?? "#40,829"
            let bandRankVal = formatRankDisplay(qso?["RANK_BAND"]) ?? formatRankDisplay(matchedRank?.rank_band) ?? "#33,425"
            let dxccRankVal = formatRankDisplay(qso?["RANK_DXCC"]) ?? formatRankDisplay(matchedRank?.rank_countries) ?? "#41,100"

            let confirmationBlock: String
            if qso?.isConfirmed == true {
                confirmationBlock = "Our QSO is already confirmed, and I have attached my QSL card for you. I hope you enjoy it."
            } else {
                confirmationBlock = "When convenient, could you please confirm our QSO in QRZ Logbook and/or LoTW? I would be very grateful. I have attached my QSL card for you. I hope you enjoy it."
            }

            var qsoDetailsLines: [String] = []
            if !formattedDate.isEmpty { qsoDetailsLines.append("Date: \(formattedDate)") }
            if !formattedTime.isEmpty { qsoDetailsLines.append("Time: \(formattedTime) UTC") }
            if !qsoBand.isEmpty { qsoDetailsLines.append("Band: \(qsoBand.uppercased())") }
            if !qsoMode.isEmpty { qsoDetailsLines.append("Mode: \(qsoMode.uppercased())") }
            if !qsoFreq.isEmpty { qsoDetailsLines.append("Freq: \(qsoFreq) MHz") }

            let qsoDetailsFormatted = qsoDetailsLines.isEmpty ? "" : "QSO Details:\n" + qsoDetailsLines.joined(separator: "\n")

            emailSubject = "Great QSO\(bandMention) / QSL & QRZ note - \(myCall)"

            emailBody = """
            Hi \(greetingName),
            
            Thanks for the excellent QSO\(bandMention)! It was a real pleasure catching you on the air.
            \(confirmationBlock)
            \(qsoDetailsFormatted)
            
            After our contact, I checked your profile on QRZ and was genuinely impressed by your standings:
              • QSO World Rank: \(qsoRankVal)
              • Bands World Rank: \(bandRankVal)
              • DXCC World Rank: \(dxccRankVal)
            
            Reaching results like this clearly reflects consistent operating, broad band coverage, and disciplined logging. As someone working toward that kind of steady performance, I would love to learn from your experience. What habits, operating style, or station setup have helped you build such a strong record?
            
            Speaking of logging, your progress is a huge motivation for a personal project of mine. I keep my station log, confirmations, and award tracking in YAAM—a lightweight amateur-radio logbook software that I am developing and use every day.
            If you'd like to take a look: 
              • Overview & Features: https://ep2aes.asis.sh 
              • Source Code (GitHub): https://github.com/fact0real/yaam
            
            I would be honored to hear any feedback from an experienced operator like you—whether about YAAM or general operating advice.
            Thanks again for the contact, \(greetingName). Hope to work you on the bands again soon!
            
            Best 73, 
            \(myCall)
            """

        case "QRZ Incoming Details":
            let incoming = appState.selectedEmailIncomingRequest
            let requestedDate = incoming?.qsoDate.isEmpty == false ? incoming!.qsoDate : "the date shown in QRZ Logbook"
            let receivedNote = incoming?.requestedAt.isEmpty == false
                ? " I received the QRZ request on \(incoming!.requestedAt)."
                : ""
            emailSubject = "Could you help me recover our QSO details? - \(myCall)"
            emailBody = """
            Hello \(targetCall),

            I noticed your incoming QRZ Logbook confirmation request for our QSO on \(requestedDate).\(receivedNote) Unfortunately, that entry appears to be missing from my local log, and I would rather ask you than guess any of the details.

            When you have a moment, would you please send me the time in UTC, band or frequency, mode, and the reports we exchanged? I will reconstruct the contact carefully and confirm it in QRZ as soon as I have the matching details.

            I am sorry for the extra step, and I appreciate your help. I am glad you reached out.

            Best 73,
            \(myCall)
            """
            
        case "QSL Card Delivery":
            let sentRst = qso?["RST_SENT"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rcvdRst = qso?["RST_RCVD"].trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let qsoRst = [sentRst, rcvdRst].filter { !$0.isEmpty }.joined(separator: "/")
            
            var detailsBlock = ""
            if qso != nil {
                var items: [String] = []
                if !formattedDate.isEmpty { items.append("- Date: \(formattedDate)") }
                if !formattedTime.isEmpty { items.append("- Time: \(formattedTime) UTC") }
                if !qsoBand.isEmpty { items.append("- Band: \(qsoBand)") }
                if !qsoMode.isEmpty { items.append("- Mode: \(qsoMode)") }
                if !qsoFreq.isEmpty { items.append("- Freq: \(qsoFreq) MHz") }
                if !qsoRst.isEmpty { items.append("- RST (Sent/Rcvd): \(qsoRst)") }
                
                if !items.isEmpty {
                    detailsBlock = "\n\nQSO Details:\n" + items.joined(separator: "\n")
                }
            }
            
            emailSubject = applyingQSLDeliveryTokens(
                qslCardDeliveryEmailSubject,
                callsign: targetCall,
                name: greetingName,
                myCall: myCall,
                details: detailsBlock
            )
            emailBody = applyingQSLDeliveryTokens(
                qslCardDeliveryEmailBody,
                callsign: targetCall,
                name: greetingName,
                myCall: myCall,
                details: detailsBlock
            )
            
        default:
            break
        }
    }

    private func applyingQSLDeliveryTokens(
        _ template: String,
        callsign: String,
        name: String,
        myCall: String,
        details: String
    ) -> String {
        template
            .replacingOccurrences(of: "{CALLSIGN}", with: callsign)
            .replacingOccurrences(of: "{NAME}", with: name)
            .replacingOccurrences(of: "{MY_CALL}", with: myCall)
            .replacingOccurrences(of: "{QSO_DETAILS}", with: details)
            .replacingOccurrences(of: "{YAAM_APP}", with: "YAAM")
    }
    
    private func formatDate(_ rawDate: String) -> String {
        guard rawDate.count == 8 else { return rawDate }
        let y = rawDate.prefix(4)
        let m = rawDate.dropFirst(4).prefix(2)
        let d = rawDate.suffix(2)
        return "\(y)-\(m)-\(d)"
    }

    private func formatRankDisplay(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.starts(with: "#") { return raw }
        if let num = Int(raw.filter(\.isNumber)) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let formatted = formatter.string(from: NSNumber(value: num)) ?? "\(num)"
            return "#\(formatted)"
        }
        return raw
    }

    private func formatTime(_ rawTime: String) -> String {
        let clean = rawTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = clean.filter { $0.isNumber }
        guard digits.count >= 4 else { return clean }
        let hours = digits.prefix(2)
        let minutes = digits.dropFirst(2).prefix(2)
        return "\(hours):\(minutes)"
    }
    
    private func sendMail() {
        if let previous = appState.latestEmailHistory(for: appState.selectedEmailCallsign) {
            let alert = NSAlert()
            alert.messageText = "Email Already Sent"
            alert.informativeText = """
            You already emailed \(appState.selectedEmailCallsign) on \(appState.formattedEmailHistoryDate(previous.date)).

            Previous subject:
            \(previous.subject)

            Do you still want to send another email?
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Send Again")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        performSendMail()
    }

    private func performSendMail() {
        isSending = true
        showDebugLog = false
        
        let shouldAttach = (["QSL Card Delivery", "QRZ Rank Congratulations & QSL"].contains(selectedTemplate) && currentQSO?.isConfirmed == true)
        let targetQSO = currentQSO
        let recipient = appState.selectedEmailAddress
        let subject = emailSubject
        let body = emailBody
        
        let myCall = resolvedMyCallsign
        let profile = appState.activeStationProfile
        let resolvedStation = QSLCardStationInfo(
            callsign: myCall,
            grid: profile?.normalizedGrid ?? "",
            radio: profile?.radioModel ?? "",
            antenna: profile?.antennaDescription ?? "",
            powerWatts: profile?.powerWatts ?? 100
        )
        
        var attachmentData: Data? = nil
        var attachmentName: String? = nil
        
        if shouldAttach, let qso = targetQSO {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            do {
                try QSLCardRenderer.exportPDF(record: qso, station: resolvedStation, to: tempURL)
                attachmentData = try Data(contentsOf: tempURL)
                try? FileManager.default.removeItem(at: tempURL)
                
                let cleanCall = QSLCardRenderer.cleanFileComponent(qso["CALL"])
                attachmentName = "\(myCall)_QSL_\(cleanCall).pdf"
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                isSending = false
                appState.alertTitle = "QSL Card Export Failed"
                appState.alertMessage = "The QSL card PDF could not be generated, so the email was not sent.\n\n\(error.localizedDescription)"
                appState.showAlert = true
                return
            }
        }
        
        appState.sendEmail(
            to: recipient,
            subject: subject,
            body: body,
            attachmentData: attachmentData,
            attachmentName: attachmentName
        ) { success, log in
            DispatchQueue.main.async {
                self.isSending = false
                if success {
                    self.appState.alertTitle = "Email Sent Successfully 🚀"
                    self.appState.alertMessage = "Your email has been dispatched via SMTP."
                    self.appState.showAlert = true
                    self.resetDraftContext()
                    self.dismiss()
                } else {
                    self.smtpDebugOutput = log
                    self.showDebugLog = true
                }
            }
        }
    }

    private func openQRZProfile() {
        let callsign = appState.selectedEmailCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !callsign.isEmpty,
              let url = URL(string: "https://www.qrz.com/db/\(callsign)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func resetDraftContext() {
        appState.selectedEmailQSO = nil
        appState.selectedEmailTemplate = nil
        appState.selectedEmailUnconfirmedQSOs = []
        appState.selectedEmailIncomingRequest = nil
        appState.incomingEmailDraftNotice = ""
    }
}

// MARK: - SMTP & Station Settings Sheet
struct SMTPSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    var embeddedInSettings = false
    @AppStorage("smtpHost") private var smtpHost = "smtp.gmail.com"
    @AppStorage("smtpPort") private var smtpPort = "465"
    @AppStorage("smtpUser") private var smtpUser = ""
    @State private var smtpPass = ""
    @State private var saveStatus = ""
    @AppStorage("qslCardDeliveryEmailSubject") private var qslCardDeliveryEmailSubject = "QSL Card for our QSO - {CALLSIGN} de {MY_CALL}"
    @AppStorage("qslCardDeliveryEmailBody") private var qslCardDeliveryEmailBody = """
Hello {NAME},

It was a genuine pleasure to meet you on the air. I have attached my QSL card for our confirmed contact.{QSO_DETAILS}

Thank you for the QSO. This card was prepared with YAAM.

Warm 73,
{MY_CALL}
"""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("SMTP & Station Configuration")
                    .font(.headline)
            }
            
            Text("Configure SMTP delivery. For Gmail / Google Workspace, use your 16-character App Password.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Form {
                LabeledContent("Active station:", value: appState.currentStationCallsign)
                TextField("SMTP Host (e.g. smtp.gmail.com):", text: $smtpHost)
                TextField("SMTP Port (465 for SSL or 587 for TLS):", text: $smtpPort)
                TextField("Email Address:", text: $smtpUser)
                SecureField("New App Password (blank keeps the saved password):", text: $smtpPass)
            }
            .padding(.vertical, 8)

            if embeddedInSettings {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("QSL Card Delivery Template", systemImage: "envelope.badge")
                        .font(.headline)
                    TextField("Subject", text: $qslCardDeliveryEmailSubject)
                    TextEditor(text: $qslCardDeliveryEmailBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    Text("Available: {CALLSIGN}, {NAME}, {MY_CALL}, {QSO_DETAILS}, {YAAM_APP}. Changes apply to the next QSL email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if embeddedInSettings {
                Label("Server settings update immediately. Save the app password once after editing it.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        saveSettings(closeWhenFinished: false)
                    } label: {
                        Label("Save Email Password", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove Password", role: .destructive) {
                        let removed = CredentialVault.delete(.smtpPassword)
                        if removed { smtpPass = "" }
                        saveStatus = removed ? "Removed" : "Keychain could not remove this password"
                    }

                    if !saveStatus.isEmpty {
                        Text(saveStatus)
                            .font(.caption)
                            .foregroundStyle(["Saved", "Removed"].contains(saveStatus) ? .green : .orange)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("Save & Close") {
                        saveSettings(closeWhenFinished: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: embeddedInSettings ? nil : 480)
    }

    private func saveSettings(closeWhenFinished: Bool) {
        UserDefaults.standard.set(smtpHost.isEmpty ? "smtp.gmail.com" : smtpHost, forKey: "smtpHost")
        UserDefaults.standard.set(smtpPort.isEmpty ? "465" : smtpPort, forKey: "smtpPort")
        UserDefaults.standard.set(smtpUser, forKey: "smtpUser")
        let cleanPassword = smtpPass.replacingOccurrences(of: " ", with: "")
        let didSave = cleanPassword.isEmpty || CredentialVault.set(cleanPassword, for: .smtpPassword)
        if didSave, !cleanPassword.isEmpty { smtpPass = "" }
        saveStatus = didSave ? "Saved" : "Keychain could not save this password"
        if didSave, closeWhenFinished { dismiss() }
    }
}
