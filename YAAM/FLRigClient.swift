//
//  FLRigClient.swift
//  YAAM
//
//  Native XML-RPC Client for FLRig (W1HKJ Transceiver Control)
//  Connects over local HTTP XML-RPC to http://127.0.0.1:12345
//  Supports VFO A/B frequency polling, Mode, PTT, S-meter, and 1-click QSY.
//

import Combine
import Foundation

@MainActor
public final class FLRigClient: ObservableObject {
    public static let shared = FLRigClient()

    // MARK: - Published State
    @Published public var isConnected: Bool = false
    @Published public var host: String = "127.0.0.1"
    @Published public var port: Int = 12345
    @Published public var rigName: String = "FLRig Transceiver"
    @Published public var frequencyHz: Double = 14_074_000
    @Published public var mode: String = "USB"
    @Published public var isPTTActive: Bool = false
    @Published public var sMeter: Double = 0.0
    @Published public var powerWatts: Double = 100.0
    @Published public var lastError: String? = nil
    @Published public var pollingInterval: TimeInterval = 0.5

    private var pollTimer: Timer?
    private var isPollingInProgress: Bool = false
    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 3.0
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Connect & Disconnect

    public func connect(host: String = "127.0.0.1", port: Int = 12345) {
        self.host = host
        self.port = port
        self.lastError = nil
        startPolling()
    }

    public func disconnect() {
        stopPolling()
        isConnected = false
    }

    public func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollRigStatus()
            }
        }
        Task { @MainActor in
            await self.pollRigStatus()
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Status Polling Loop

    public func pollRigStatus() async {
        guard !isPollingInProgress else { return }
        isPollingInProgress = true
        defer { isPollingInProgress = false }

        do {
            // 1. Get VFO frequency
            let freqStr = try await sendXMLRPC(method: "rig.get_vfo")
            if let freq = Double(cleanXMLValue(freqStr)), freq > 0 {
                self.frequencyHz = freq
                self.isConnected = true
            }

            // 2. Get Mode
            let modeVal = try await sendXMLRPC(method: "rig.get_mode")
            let cleanMode = cleanXMLValue(modeVal)
            if !cleanMode.isEmpty {
                self.mode = cleanMode
            }

            // 3. Get S-Meter
            if let smeterVal = try? await sendXMLRPC(method: "rig.get_smeter"),
               let sm = Double(cleanXMLValue(smeterVal)) {
                self.sMeter = sm
            }

            // 4. Get PTT status
            if let pttVal = try? await sendXMLRPC(method: "rig.get_ptt"),
               let pttInt = Int(cleanXMLValue(pttVal)) {
                self.isPTTActive = (pttInt == 1)
            }

            self.lastError = nil
        } catch {
            if isConnected {
                self.isConnected = false
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Control Commands (1-Click QSY & Mode)

    public func setFrequency(hz: Double) async throws {
        _ = try await sendXMLRPC(method: "rig.set_vfo", paramDouble: hz)
        self.frequencyHz = hz
    }

    public func setMode(_ newMode: String) async throws {
        _ = try await sendXMLRPC(method: "rig.set_mode", paramString: newMode)
        self.mode = newMode
    }

    public func setPTT(active: Bool) async throws {
        _ = try await sendXMLRPC(method: "rig.set_ptt", paramInt: active ? 1 : 0)
        self.isPTTActive = active
    }

    // MARK: - XML-RPC Transport

    private func sendXMLRPC(
        method: String,
        paramString: String? = nil,
        paramDouble: Double? = nil,
        paramInt: Int? = nil
    ) async throws -> String {
        guard let url = URL(string: "http://\(host):\(port)") else {
            throw URLError(.badURL)
        }

        var xmlBody = "<?xml version=\"1.0\"?><methodCall><methodName>\(method)</methodName>"
        if paramString != nil || paramDouble != nil || paramInt != nil {
            xmlBody += "<params><param><value>"
            if let paramString {
                xmlBody += "<string>\(paramString)</string>"
            } else if let paramDouble {
                xmlBody += "<double>\(paramDouble)</double>"
            } else if let paramInt {
                xmlBody += "<i4>\(paramInt)</i4>"
            }
            xmlBody += "</value></param></params>"
        } else {
            xmlBody += "<params></params>"
        }
        xmlBody += "</methodCall>"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("YAAM-macOS-FLRigClient/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = xmlBody.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func cleanXMLValue(_ xml: String) -> String {
        let pattern = "<value>(?:<[^>]+>)?(.*?)(?:<\\/[^>]+>)?<\\/value>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
            let nsString = xml as NSString
            if let match = regex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    return nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        // Fallback simple XML strip
        return xml
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
