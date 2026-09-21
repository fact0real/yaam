//
//  TQSLCoordinator.swift
//  YAAM
//
//  Centralized, Actor-Isolated Execution Coordinator for ARRL TrustedQSL (TQSL).
//  Guarantees:
//  1. Strict mutual exclusion (single TQSL process at any moment across YAAM)
//     to prevent "The uploads database is busy" (exit code 13) lock contention.
//  2. Headless non-interactive execution with `-a compliant` and `-f ignore` to
//     suppress wxWidgets GUI modal dialogs and prompts.
//  3. Automatic retry with exponential backoff if database lock is encountered.
//  4. Watchdog process timeout to terminate any hung processes safely.
//  5. Automatic cleanup of temporary .adi and .tq8 files.
//

import AppKit
import Foundation

public actor TQSLCoordinator {
    public static let shared = TQSLCoordinator()

    private init() {
        Self.cleanStaleTemporaryFiles()
    }

    // MARK: - Binary Resolution

    public static func resolveBinaryPath(
        customPath: String? = nil,
        securityBookmark: Data? = nil
    ) -> (path: String, scopedURL: URL?)? {
        let fileManager = FileManager.default

        var scopedURL: URL?
        let bookmark = securityBookmark ?? UserDefaults.standard.data(forKey: "tqslExecutableBookmark")
        if let bookmark {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if resolved.startAccessingSecurityScopedResource() {
                    scopedURL = resolved
                }
            }
        }

        let userConfigured = (customPath ?? UserDefaults.standard.string(forKey: "tqslExecutablePath") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let candidates = [
            scopedURL?.path ?? "",
            userConfigured,
            "/Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl",
            "/Applications/tqsl.app/Contents/MacOS/tqsl",
            "/opt/homebrew/bin/tqsl",
            "/usr/local/bin/tqsl",
            "/usr/bin/tqsl"
        ].filter { !$0.isEmpty }

        guard let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
            return nil
        }

        return (executable, scopedURL)
    }

    // MARK: - Stale File Cleanup

    public static func cleanStaleTemporaryFiles() {
        let fileManager = FileManager.default
        let directories = [
            TQSLService.realTQSLDirectory(),
            TQSLService.containerTQSLDirectory(),
            fileManager.temporaryDirectory.path
        ]

        for dir in directories {
            guard fileManager.fileExists(atPath: dir),
                  let items = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let lower = item.lowercased()
                if (lower.hasPrefix("yaam_lotw") || lower.hasPrefix("yaam-lotw")) &&
                   (lower.hasSuffix(".tq8") || lower.hasSuffix(".adi")) {
                    let path = (dir as NSString).appendingPathComponent(item)
                    try? fileManager.removeItem(atPath: path)
                }
            }
        }
    }

    // MARK: - Execute TQSL (Serialized & Protected)

    public func execute(
        adifContent: String? = nil,
        adifFileURL: URL? = nil,
        stationLocation: String? = nil,
        certificatePassword: String? = nil,
        customExecutablePath: String? = nil,
        securityBookmark: Data? = nil,
        timeoutSeconds: TimeInterval = 45.0
    ) async -> (success: Bool, message: String) {
        let fileManager = FileManager.default

        guard let resolved = Self.resolveBinaryPath(
            customPath: customExecutablePath,
            securityBookmark: securityBookmark
        ) else {
            return (false, "TrustedQSL (tqsl) binary not found on this Mac. Please install TQSL from arrl.org.")
        }

        let binaryPath = resolved.path
        let scopedURL = resolved.scopedURL
        defer {
            scopedURL?.stopAccessingSecurityScopedResource()
        }

        // Determine working ADIF file URL
        let workingAdifURL: URL
        let shouldDeleteAdif: Bool

        if let adifContent = adifContent {
            let tempURL = fileManager.temporaryDirectory.appendingPathComponent("yaam_lotw_\(UUID().uuidString).adi")
            do {
                try adifContent.write(to: tempURL, atomically: true, encoding: .utf8)
                workingAdifURL = tempURL
                shouldDeleteAdif = true
            } catch {
                return (false, "Failed to write temporary ADIF log: \(error.localizedDescription)")
            }
        } else if let adifFileURL = adifFileURL, fileManager.fileExists(atPath: adifFileURL.path) {
            workingAdifURL = adifFileURL
            shouldDeleteAdif = false
        } else {
            return (false, "No valid ADIF log content or file path provided for LoTW signing.")
        }

        // Potential companion .tq8 package generated by TQSL
        let companionTq8URL = workingAdifURL.deletingPathExtension().appendingPathExtension("tq8")

        defer {
            if shouldDeleteAdif {
                try? fileManager.removeItem(at: workingAdifURL)
            }
            try? fileManager.removeItem(at: companionTq8URL)
        }

        // Resolve Station Location
        var resolvedLocation = (stationLocation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedLocation.isEmpty {
            resolvedLocation = (UserDefaults.standard.string(forKey: "lotwStationLocation") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if resolvedLocation.isEmpty {
            if let db = try? LogbookDatabase(), let profiles = try? db.loadStationProfiles() {
                if let activeID = UserDefaults.standard.string(forKey: "activeStationProfileID").flatMap(UUID.init(uuidString:)),
                   let prof = profiles.first(where: { $0.id == activeID }),
                   !prof.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedLocation = prof.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let firstProf = profiles.first,
                          !firstProf.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedLocation = firstProf.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // Resolve Certificate Password
        var resolvedPassword = (certificatePassword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedPassword.isEmpty {
            resolvedPassword = CredentialVault.value(for: .lotwCertificatePassword).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Prepare Arguments:
        // -d: Suppress date range dialog
        // -u: Direct LoTW upload via internet
        // -x: Batch mode, exit after processing
        // -q: Quiet mode, status to stderr
        // -a compliant: Sign compliant QSOs, do NOT prompt interactive modal dialogs on conflicts/duplicates
        // -f ignore: Ignore MY_* differences with station location without prompting
        var baseArguments: [String] = [
            "-d",
            "-u",
            "-x",
            "-q",
            "-a", "compliant",
            "-f", "ignore"
        ]

        if !resolvedLocation.isEmpty {
            baseArguments.append(contentsOf: ["-l", resolvedLocation])
        }
        if !resolvedPassword.isEmpty {
            baseArguments.append(contentsOf: ["-p", resolvedPassword])
        }
        baseArguments.append(workingAdifURL.path)

        // Retry loop for lock contention (Code 13 / "database is busy")
        let maxAttempts = 3
        var lastExitCode: Int32 = -1
        var lastOutput = ""

        for attempt in 1...maxAttempts {
            // Synchronize configuration safely before process run
            TQSLService.synchronizeTQSLStorage()

            let result = await runProcessWithTimeout(
                binaryPath: binaryPath,
                arguments: baseArguments,
                timeout: timeoutSeconds
            )

            lastExitCode = result.exitCode
            lastOutput = result.output

            // Success condition:
            // Code 0: All submitted QSOs were signed and uploaded
            // Code 8: No QSOs processed because already uploaded / out of range
            // Code 9: Some QSOs processed, already-uploaded ones skipped
            // Code 14: Some QSOs were already uploaded previously
            if result.exitCode == 0 {
                return (true, "Signed & Uploaded to LoTW")
            }

            if result.exitCode == 8 || result.exitCode == 9 || result.exitCode == 14 {
                let note = result.exitCode == 0 ? "Accepted" : "Already uploaded / compliant"
                return (true, "LoTW: \(note) (TQSL code \(result.exitCode))")
            }

            // Detect database lock contention:
            // Code 13: "When signing a log, the TQSL upload tracking database was locked"
            let lower = result.output.lowercased()
            let isBusy = result.exitCode == 13 ||
                         lower.contains("database is busy") ||
                         lower.contains("dblocked") ||
                         lower.contains("database was locked") ||
                         lower.contains("uploads database error")

            if isBusy {
                if attempt < maxAttempts {
                    let backoffSeconds = Double(attempt) * 1.5
                    try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                    continue
                } else {
                    return (false, "LoTW signing temporarily unavailable: TQSL database was busy after \(maxAttempts) retries (another TQSL instance is open).")
                }
            }

            // Connection / network failure:
            if result.exitCode == 11 || lower.contains("connection error") || lower.contains("unreachable") {
                return (false, "LoTW connection error: ARRL server is unreachable or offline (Code 11)")
            }

            // General error
            let cleanMsg = Self.cleanErrorOutput(result.output, exitCode: result.exitCode)
            return (false, cleanMsg)
        }

        return (false, Self.cleanErrorOutput(lastOutput, exitCode: lastExitCode))
    }

    // MARK: - Process Runner with Watchdog

    private func runProcessWithTimeout(
        binaryPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> (exitCode: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.environment = TQSLService.tqslProcessEnvironment()
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                var isCompleted = false
                let lock = NSLock()

                // Watchdog timer to kill process if it hangs
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    lock.lock()
                    defer { lock.unlock() }
                    if !isCompleted && process.isRunning {
                        process.terminate()
                    }
                }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()

                    lock.lock()
                    isCompleted = true
                    timer.cancel()
                    lock.unlock()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (process.terminationStatus, output))
                } catch {
                    lock.lock()
                    isCompleted = true
                    timer.cancel()
                    lock.unlock()

                    continuation.resume(returning: (-1, error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Output Formatter

    private static func cleanErrorOutput(_ raw: String, exitCode: Int32) -> String {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("TQSL Version") }

        if let lastLine = lines.last(where: { $0.contains("Final Status:") || $0.contains("Error") || $0.contains("error") }) {
            return lastLine
        }

        if let first = lines.first {
            return first
        }

        return "TQSL stopped with exit code \(exitCode)"
    }
}
