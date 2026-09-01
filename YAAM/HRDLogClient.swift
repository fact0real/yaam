//
//  HRDLogClient.swift
//  YAAM
//
//  HRDLog.net REST API Client & Live Cloud Logbook Synchronizer
//  Direct HTTP POST auto-upload on QSO save and batch ADIF synchronization.
//

import Combine
import Foundation
import SwiftUI

@MainActor
public final class HRDLogClient: ObservableObject {
    public static let shared = HRDLogClient()

    // MARK: - Published State
    @Published public var isUploading: Bool = false
    @Published public var autoUploadEnabled: Bool = false
    @Published public var lastUploadStatus: String = "Idle"
    @Published public var lastUploadDate: Date? = nil
    @Published public var lastError: String? = nil

    private let endpointURL = URL(string: "https://hrdlog.net/upload.aspx")!

    public init() {
        self.autoUploadEnabled = UserDefaults.standard.bool(forKey: "hrdlogAutoUploadEnabled")
    }

    public var isConfigured: Bool {
        let call = UserDefaults.standard.string(forKey: "hrdlogCallsign") ?? ""
        let code = CredentialVault.value(for: .hrdlogCode)
        return !call.isEmpty && !code.isEmpty
    }

    // MARK: - Upload Single QSO

    func uploadSingleQSO(record: QSORecordModel, callsign: String? = nil) async -> Bool {
        let adif = record.toADIFRecordString()
        return await uploadADIFString(adif, callsign: callsign)
    }

    // MARK: - Upload Batch Records

    func uploadBatch(records: [QSORecordModel], callsign: String? = nil) async -> (uploaded: Int, failed: Int) {
        guard !records.isEmpty else { return (0, 0) }

        var adifBatch = "<ADIF_VER:5>3.1.4\n<PROGRAMID:4>YAAM\n<EOH>\n"
        for rec in records {
            adifBatch += rec.toADIFRecordString() + "\n"
        }

        self.isUploading = true
        self.lastUploadStatus = "Uploading \(records.count) QSOs to HRDLog.net..."

        let ok = await uploadADIFString(adifBatch, callsign: callsign)
        self.isUploading = false

        if ok {
            self.lastUploadStatus = "Successfully uploaded \(records.count) QSOs to HRDLog.net"
            self.lastUploadDate = Date()
            return (records.count, 0)
        } else {
            self.lastUploadStatus = "Upload failed: \(lastError ?? "Unknown error")"
            return (0, records.count)
        }
    }

    // MARK: - HTTP Form POST Execution

    private func uploadADIFString(_ adifData: String, callsign: String?) async -> Bool {
        let call = callsign ?? UserDefaults.standard.string(forKey: "hrdlogCallsign") ?? "EP2AES"
        let code = CredentialVault.value(for: .hrdlogCode)

        guard !code.isEmpty else {
            self.lastError = "HRDLog Upload Code not configured"
            return false
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0

        let bodyParams: [String: String] = [
            "Callbook": call.uppercased(),
            "Code": code,
            "ADIFData": adifData,
            "Station": "YAAM"
        ]

        let encodedBody = bodyParams
            .map { "\($0.key)=\(urlEncode($0.value))" }
            .joined(separator: "&")

        request.httpBody = encodedBody.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                let responseStr = String(data: data, encoding: .utf8) ?? ""
                if responseStr.lowercased().contains("error") || responseStr.lowercased().contains("invalid") {
                    self.lastError = responseStr
                    return false
                }
                self.lastError = nil
                self.lastUploadDate = Date()
                return true
            } else {
                self.lastError = "Server HTTP status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return false
            }
        } catch {
            self.lastError = error.localizedDescription
            return false
        }
    }

    private func urlEncode(_ str: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return str.addingPercentEncoding(withAllowedCharacters: allowed) ?? str
    }
}
