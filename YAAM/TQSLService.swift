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
        Self.synchronizeTQSLStorage()
        checkTQSLInstallation()
    }

    // MARK: - Storage & Sandbox Synchronization

    public nonisolated static func realUserHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    public nonisolated static func realTQSLDirectory() -> String {
        (realUserHomeDirectory() as NSString).appendingPathComponent(".tqsl")
    }

    public nonisolated static func containerTQSLDirectory() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".tqsl")
    }

    public nonisolated static func hasStationData() -> Bool {
        let fileManager = FileManager.default
        return [realTQSLDirectory(), containerTQSLDirectory()].contains { directory in
            fileManager.fileExists(atPath: (directory as NSString).appendingPathComponent("station_data"))
        }
    }

    @discardableResult
    public nonisolated static func synchronizeTQSLStorage() -> (synced: Bool, message: String) {
        let fileManager = FileManager.default
        let realTQSL = realTQSLDirectory()
        let containerTQSL = containerTQSLDirectory()

        if realTQSL == containerTQSL {
            return (true, "Direct access: \(realTQSL)")
        }

        let realStationData = (realTQSL as NSString).appendingPathComponent("station_data")
        let containerStationData = (containerTQSL as NSString).appendingPathComponent("station_data")

        let sourceDir: String
        let targetDir: String

        if fileManager.fileExists(atPath: realStationData) {
            sourceDir = realTQSL
            targetDir = containerTQSL
        } else if fileManager.fileExists(atPath: containerStationData) {
            sourceDir = containerTQSL
            targetDir = realTQSL
        } else {
            return (false, "No station_data found")
        }

        do {
            if !fileManager.fileExists(atPath: targetDir) {
                try fileManager.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
            }

            let items = try fileManager.contentsOfDirectory(atPath: sourceDir)
            var count = 0
            for item in items {
                // Never copy active SQLite database files, WAL journals, lock files, logs, or temporary files
                let lower = item.lowercased()
                if lower.starts(with: "uploaded.db") ||
                   lower.starts(with: "dblock") ||
                   lower.starts(with: "dberr") ||
                   lower.starts(with: "curl") ||
                   lower.hasSuffix(".tq8") ||
                   lower.hasSuffix(".adi") ||
                   lower.hasSuffix(".log") ||
                   lower.starts(with: "yaam_lotw") ||
                   lower.starts(with: "yaam-lotw") {
                    continue
                }

                let srcItem = (sourceDir as NSString).appendingPathComponent(item)
                let dstItem = (targetDir as NSString).appendingPathComponent(item)

                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: srcItem, isDirectory: &isDir) {
                    if isDir.boolValue {
                        if !fileManager.fileExists(atPath: dstItem) {
                            try? fileManager.copyItem(atPath: srcItem, toPath: dstItem)
                            count += 1
                        } else {
                            let subItems = (try? fileManager.contentsOfDirectory(atPath: srcItem)) ?? []
                            for sub in subItems {
                                let subSrc = (srcItem as NSString).appendingPathComponent(sub)
                                let subDst = (dstItem as NSString).appendingPathComponent(sub)
                                if !fileManager.fileExists(atPath: subDst) {
                                    try? fileManager.copyItem(atPath: subSrc, toPath: subDst)
                                    count += 1
                                }
                            }
                        }
                    } else {
                        let srcAttrs = try? fileManager.attributesOfItem(atPath: srcItem)
                        let dstAttrs = try? fileManager.attributesOfItem(atPath: dstItem)
                        let srcMod = (srcAttrs?[.modificationDate] as? Date) ?? Date.distantPast
                        let dstMod = (dstAttrs?[.modificationDate] as? Date) ?? Date.distantPast

                        if !fileManager.fileExists(atPath: dstItem) || srcMod > dstMod {
                            try? fileManager.removeItem(atPath: dstItem)
                            try? fileManager.copyItem(atPath: srcItem, toPath: dstItem)
                            count += 1
                        }
                    }
                }
            }
            return (true, "Synchronized \(count) items to \(targetDir)")
        } catch {
            return (false, "Sync failed: \(error.localizedDescription)")
        }
    }

    public nonisolated static func tqslProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let realHome = realUserHomeDirectory()
        let realTQSL = realTQSLDirectory()
        let containerTQSL = containerTQSLDirectory()

        if FileManager.default.fileExists(atPath: (realTQSL as NSString).appendingPathComponent("station_data")) {
            env["TQSLDIR"] = realTQSL
            env["HOME"] = realHome
        } else if FileManager.default.fileExists(atPath: (containerTQSL as NSString).appendingPathComponent("station_data")) {
            env["TQSLDIR"] = containerTQSL
        }
        return env
    }

    // MARK: - Installation Discovery

    public func checkTQSLInstallation() {
        var customCandidates: [String] = []
        if let bookmark = UserDefaults.standard.data(forKey: "tqslExecutableBookmark") {
            var stale = false
            if let scopedURL = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if scopedURL.startAccessingSecurityScopedResource() {
                    customCandidates.append(scopedURL.path)
                    scopedURL.stopAccessingSecurityScopedResource()
                }
            }
        }
        let configuredPath = (UserDefaults.standard.string(forKey: "tqslExecutablePath") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            customCandidates.append(configuredPath)
        }

        let potentialPaths = customCandidates + [
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

        let outcome = await TQSLCoordinator.shared.execute(
            adifFileURL: adifFileURL,
            stationLocation: stationLocation,
            certificatePassword: certificatePassword,
            customExecutablePath: binaryPath
        )

        self.lastLogOutput = outcome.message
        if outcome.success {
            return (true, outcome.message)
        } else {
            let error = NSError(domain: "TQSLService", code: 1, userInfo: [NSLocalizedDescriptionKey: outcome.message])
            self.lastError = outcome.message
            throw error
        }
    }
}
