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
import Darwin
import Foundation

public actor TQSLCoordinator {
    public static let shared = TQSLCoordinator()

    private var isExecuting = false
    private var executionWaiters: [CheckedContinuation<Void, Never>] = []

    init(cleanStaleFiles: Bool = true) {
        if cleanStaleFiles { Self.cleanStaleTemporaryFiles() }
    }

    private func acquireExecution() async {
        if isExecuting {
            await withCheckedContinuation { executionWaiters.append($0) }
        } else {
            isExecuting = true
        }
    }

    private func releaseExecution() {
        if executionWaiters.isEmpty { isExecuting = false }
        else { executionWaiters.removeFirst().resume() }
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

    public static func cleanStaleTemporaryFiles(in directory: URL = FileManager.default.temporaryDirectory) {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for item in items {
            let name = item.lastPathComponent
            guard name.hasPrefix("yaam-lotw-"), UUID(uuidString: String(name.dropFirst("yaam-lotw-".count))) != nil,
                  let values = try? item.resourceValues(forKeys: keys), values.isDirectory == true,
                  values.isSymbolicLink != true, let modified = values.contentModificationDate, modified < cutoff,
                  let attributes = try? fileManager.attributesOfItem(atPath: item.path),
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { continue }
            try? fileManager.removeItem(at: item)
        }
        // Never sweep .tqsl storage or arbitrary ADIF/TQ8 filenames: they can be user files or a live process's input.
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
        // Actor methods reenter at await: an explicit gate keeps actual TQSL processes mutually exclusive.
        await acquireExecution()
        defer { releaseExecution() }
        guard !Task.isCancelled else { return (false, "LoTW upload cancelled before signing.") }
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

        // Always sign a private, filtered copy, including when a caller supplies a local ADIF file.
        // Do not let TQSL create/delete a .tq8 beside the operator's original file.
        let input: String
        do {
            if let adifContent {
                input = adifContent
            } else if let adifFileURL {
                let data = try UploadFileReader.read(adifFileURL)
                guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    return (false, "Could not decode the ADIF file for LoTW signing.")
                }
                input = decoded
            } else {
                return (false, "No ADIF log was provided for LoTW signing.")
            }
        } catch {
            return (false, "Could not read the ADIF file for LoTW signing: \(error.localizedDescription)")
        }
        let (_, records) = parseADIF(content: input)
        guard !records.isEmpty else { return (false, "No QSOs found for LoTW signing.") }
        let safeRecords = records.map { QSLUploadStatus.uploadFields($0, for: .lotw) }
        let safeADIF = generateADIF(originalContent: "", records: safeRecords)
        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent("yaam-lotw-" + UUID().uuidString, isDirectory: true)
        let workingAdifURL = workingDirectory.appendingPathComponent("upload.adi")
        do {
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try safeADIF.write(to: workingAdifURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: workingAdifURL.path)
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            return (false, "Failed to prepare a private ADIF file for LoTW signing.")
        }
        defer { try? fileManager.removeItem(at: workingDirectory) }

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
            guard !Task.isCancelled else { return (false, "LoTW upload cancelled before signing.") }
            // Synchronize configuration safely before process run
            TQSLService.synchronizeTQSLStorage()

            let result = await runProcessWithTimeout(
                binaryPath: binaryPath,
                arguments: baseArguments,
                timeout: timeoutSeconds
            )

            lastExitCode = result.exitCode
            lastOutput = result.output

            // Only zero proves that every submitted QSO was signed and uploaded. Codes 8/9 also cover
            // certificate date exclusions; even 14 cannot prove which records were previously accepted.
            if result.exitCode == 0 {
                return (true, "Signed & Uploaded to LoTW")
            }
            if [8, 9, 14].contains(result.exitCode) {
                let detail = Self.cleanErrorOutput(result.output, exitCode: result.exitCode)
                return (false, "LoTW upload is not fully confirmed (TQSL code \(result.exitCode)). No QSOs were marked uploaded. Review the TQSL result and LoTW log before retrying. \(detail)")
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
                var timedOut = false
                let lock = NSLock()

                // Watchdog timer to kill process if it hangs
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
                timer.schedule(deadline: .distantFuture)
                timer.setEventHandler {
                    lock.lock()
                    defer { lock.unlock() }
                    if !isCompleted && process.isRunning {
                        timedOut = true
                        process.terminate()
                        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2) {
                            lock.lock()
                            defer { lock.unlock() }
                            if !isCompleted && process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                }
                timer.resume()

                do {
                    try process.run()
                    // Arm only after launch: a short deadline firing while Process is not running
                    // would otherwise be consumed without terminating the child or recording a timeout.
                    let boundedTimeout = timeout.isFinite && timeout > 0 ? timeout : 45
                    let started = ProcessInfo.processInfo.systemUptime
                    timer.schedule(deadline: .now() + boundedTimeout)
                    // Drain while the child runs so verbose TQSL output cannot fill the pipe and deadlock it.
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    lock.lock()
                    isCompleted = true
                    // A delayed timer must not turn an over-deadline exit into confirmed acceptance.
                    let didTimeOut = timedOut || ProcessInfo.processInfo.systemUptime - started >= boundedTimeout
                    timer.cancel()
                    lock.unlock()

                    let output = String(data: data, encoding: .utf8) ?? ""
                    if didTimeOut {
                        continuation.resume(returning: (-1, "TQSL timed out before upload acceptance was confirmed."))
                    } else {
                        continuation.resume(returning: (process.terminationReason == .exit ? process.terminationStatus : -1, output))
                    }
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
