//
//  TQSLService.swift
//  YAAM
//
//  Direct macOS TQSL CLI Engine for LoTW (Logbook of the World)
//  Discovers local TrustedQSL app installation, signs ADIF files locally,
//  and submits signed .tq8 packages directly to ARRL LoTW servers in 1 click.
//

import AppKit
import Combine
import Foundation

@MainActor
public final class TQSLService: ObservableObject {
    public static let shared = TQSLService()

    @Published public var isTQSLInstalled: Bool = false
    @Published public var tqslBinaryPath: String? = nil
    @Published public var isProcessing: Bool = false
    @Published public var lastLogOutput: String = ""
    @Published public var lastError: String? = nil

    public init() {
        checkTQSLInstallation()
    }

    // MARK: - Installation Discovery

    public func checkTQSLInstallation() {
        let potentialPaths = [
            "/Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl",
            "/Applications/tqsl.app/Contents/MacOS/tqsl",
            "/usr/local/bin/tqsl",
            "/opt/homebrew/bin/tqsl",
            "/usr/bin/tqsl"
        ]

        for path in potentialPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                self.isTQSLInstalled = true
                self.tqslBinaryPath = path
                return
            }
        }

        self.isTQSLInstalled = false
        self.tqslBinaryPath = nil
    }

    // MARK: - Sign & Upload Batch to ARRL LoTW

    public func signAndUpload(
        adifFileURL: URL,
        stationLocation: String = "",
        certificatePassword: String = ""
    ) async throws -> (success: Bool, output: String) {
        guard let binaryPath = tqslBinaryPath, FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw NSError(domain: "TQSLService", code: 404, userInfo: [NSLocalizedDescriptionKey: "TrustedQSL (tqsl) is not installed on this Mac. Please install TQSL from arrl.org."])
        }

        self.isProcessing = true
        self.lastError = nil
        self.lastLogOutput = "Executing TQSL: \(binaryPath)..."

        defer { self.isProcessing = false }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)

                var arguments: [String] = ["-d", "-u", "-x"]
                if !stationLocation.isEmpty {
                    arguments.append(contentsOf: ["-l", stationLocation])
                }
                if !certificatePassword.isEmpty {
                    arguments.append(contentsOf: ["-p", certificatePassword])
                }
                arguments.append(adifFileURL.path)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    DispatchQueue.main.async {
                        self.lastLogOutput = output
                        if process.terminationStatus == 0 {
                            continuation.resume(returning: (true, output))
                        } else {
                            let error = NSError(domain: "TQSLService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "TQSL exited with code \(process.terminationStatus):\n\(output)"])
                            self.lastError = error.localizedDescription
                            continuation.resume(throwing: error)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
