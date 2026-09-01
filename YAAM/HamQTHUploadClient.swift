//
//  HamQTHUploadClient.swift
//  YAAM
//
//  HamQTH.com Online Logbook Upload API Client
//  Automatic real-time QSO push and batch ADIF logbook uploads to HamQTH.
//

import Combine
import Foundation
import SwiftUI

@MainActor
public final class HamQTHUploadClient: ObservableObject {
    public static let shared = HamQTHUploadClient()

    // MARK: - Published State
    @Published public var isUploading: Bool = false
    @Published public var autoUploadEnabled: Bool = false
    @Published public var lastUploadStatus: String = "Idle"
    @Published public var lastUploadDate: Date? = nil
    @Published public var lastError: String? = nil

    private let uploadEndpointURL = URL(string: "https://www.hamqth.com/adif_upload.php")!

    public init() {
        self.autoUploadEnabled = UserDefaults.standard.bool(forKey: "hamqthAutoUploadEnabled")
    }

    public var isConfigured: Bool {
        let user = UserDefaults.standard.string(forKey: "hamqthUsername") ?? ""
        let pass = CredentialVault.value(for: .hamqthPassword)
        return !user.isEmpty && !pass.isEmpty
    }

    // MARK: - Upload Single QSO

    func uploadSingleQSO(record: QSORecordModel) async -> Bool {
        let adif = "<ADIF_VER:5>3.1.4\n<PROGRAMID:4>YAAM\n<EOH>\n" + record.toADIFRecordString() + "\n"
        return await uploadADIFString(adif)
    }

    // MARK: - Upload Batch Records

    func uploadBatch(records: [QSORecordModel]) async -> (uploaded: Int, failed: Int) {
        guard !records.isEmpty else { return (0, 0) }

        var adifBatch = "<ADIF_VER:5>3.1.4\n<PROGRAMID:4>YAAM\n<EOH>\n"
        for rec in records {
            adifBatch += rec.toADIFRecordString() + "\n"
        }

        self.isUploading = true
        self.lastUploadStatus = "Uploading \(records.count) QSOs to HamQTH..."

        let ok = await uploadADIFString(adifBatch)
        self.isUploading = false

        if ok {
            self.lastUploadStatus = "Successfully uploaded \(records.count) QSOs to HamQTH"
            self.lastUploadDate = Date()
            return (records.count, 0)
        } else {
            self.lastUploadStatus = "Upload failed: \(lastError ?? "Unknown error")"
            return (0, records.count)
        }
    }

    // MARK: - HTTP Multipart Execution

    private func uploadADIFString(_ adifData: String) async -> Bool {
        let username = UserDefaults.standard.string(forKey: "hamqthUsername") ?? ""
        let password = CredentialVault.value(for: .hamqthPassword)

        guard !username.isEmpty, !password.isEmpty else {
            self.lastError = "HamQTH credentials not configured in Preferences"
            return false
        }

        var request = URLRequest(url: uploadEndpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Username
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"user\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(username)\r\n".data(using: .utf8)!)

        // Password
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"password\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(password)\r\n".data(using: .utf8)!)

        // ADIF file payload
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"adif\"; filename=\"yaam_log.adi\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(adifData.data(using: .utf8) ?? Data())
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

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
}
