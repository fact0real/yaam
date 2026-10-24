import SwiftUI
import UniformTypeIdentifiers

struct LoTWVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var call = ""
    @State private var password = ""
    @State private var file: URL?
    @State private var choosingFile = false
    @State private var consent = false
    @State private var working = false
    @State private var error: String?
    @State private var success: String?
    private let signer = LoTWProofSigner()
    let service: SKEDMessagingService
    let tokenProvider: () -> String
    let completed: () -> Void

    #if MESSAGING_REGRESSION
    func preview(_ state: String) -> Self {
        var view = self
        if state != "empty" {
            view._call = State(initialValue: "K1ABC")
            view._file = State(initialValue: URL(fileURLWithPath: "/tmp/Synthetic-certificate-backup.p12"))
            view._consent = State(initialValue: true)
        }
        if state == "working" { view._working = State(initialValue: true) }
        if state == "error" { view._error = State(initialValue: SKEDMessagingError.certificateVerificationRefused.localizedDescription) }
        if state == "success" { view._success = State(initialValue: "Verified K1ABC. Close this window, then enable messaging when you are ready.") }
        return view
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Verify callsign with LoTW", systemImage: "checkmark.shield").font(.title2)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("In TQSL, select your current callsign certificate and save a certificate backup (.p12). Choose that file below. Its private key is opened in memory on this Mac for this verification only.")
                    Text("The public certificate may contain your name and email address. YAAM sends it and a one-time signature to qrz-rank for verification. Your private key, backup file and password are never sent. No QSO is created or uploaded to LoTW.")
                        .foregroundStyle(.secondary)
                    TextField("Callsign on this certificate", text: $call).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Choose certificate backup…") { choosingFile = true }
                        Text(file?.lastPathComponent ?? "No file selected").lineLimit(2).truncationMode(.middle)
                    }
                    SecureField("Certificate backup password", text: $password).textFieldStyle(.roundedBorder)
                    Toggle("Verify this callsign for my QRZ Rank account", isOn: $consent)
                    Text("Use your newest certificate. Expired, replaced, historical-call and unsupported certificates require administrator review. LoTW must be reachable. Messaging remains off after verification until you enable it.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                    if let success { Label(success, systemImage: "checkmark.circle").foregroundStyle(.primary) }
                }.disabled(working || success != nil)
            }
            HStack {
                Link("LoTW certificate validity guide", destination: URL(string: "https://lotw.arrl.org/lotw-help/certificatevalidity/")!)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button(success == nil ? "Cancel" : "Done") { dismiss() }.disabled(working).keyboardShortcut(.cancelAction)
                if success == nil {
                    Button("Sign and verify") { Task { await verify() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(working || file == nil || !consent || !SKEDMessagingContract.validCallsign(normalizedCall))
                }
            }
        }
        .padding(20).frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data,
            UTType(filenameExtension: "pfx") ?? .data]) { result in
            if case let .success(url) = result { file = url; error = nil; password = "" }
        }
        .onDisappear { password = ""; Task { await signer.clear() } }
    }

    private var normalizedCall: String { call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    private func verify() async {
        guard !working, consent, let file else { return }
        working = true; error = nil
        let token = tokenProvider(), selectedCall = normalizedCall, passphrase = password
        password = ""
        do {
            let certificate = try await signer.load(url: file, password: passphrase)
            guard tokenProvider() == token, !Task.isCancelled else { throw CancellationError() }
            let challenge = try await service.lotwChallenge(call: selectedCall, certificate: certificate, token: token)
            guard tokenProvider() == token, !Task.isCancelled else { throw CancellationError() }
            let proof = try await signer.sign(challenge, call: selectedCall)
            await signer.clear()
            guard tokenProvider() == token, !Task.isCancelled else { throw CancellationError() }
            let result = try await service.verifyLoTW(challenge: challenge, proof: proof, token: token)
            guard tokenProvider() == token, !Task.isCancelled else { throw CancellationError() }
            guard result.verifiedCallsign == selectedCall, !result.enabled else { throw SKEDMessagingError.invalidResponse }
            success = "Verified \(selectedCall). Close this window, then enable messaging when you are ready."
            completed()
        } catch is CancellationError {
            error = "The account changed or verification was cancelled. Refresh before trying again."
        } catch {
            self.error = error is LoTWProofError || error is SKEDMessagingError ? error.localizedDescription : LoTWProofError.importFailed.localizedDescription
        }
        await signer.clear()
        working = false
    }
}
