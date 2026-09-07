//
//  AuditLogger.swift
//  YAAM
//
//  Persistent Activity & Change Audit Logger
//  Records all user actions, edits, QSL transmissions, and log mutations
//  to a permanent file for auditing and historical review.
//

import AppKit
import Foundation

final class AuditLogger: @unchecked Sendable {
    static let shared = AuditLogger()

    private let queue = DispatchQueue(label: "org.asis.yaam.audit.logger", qos: .utility)
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return df
    }()

    var logDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("ASIS.YAAM/Logs", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var logFileURL: URL {
        logDirectoryURL.appendingPathComponent("activity_audit.log")
    }

    private init() {
        rotateIfNeeded()
        log(action: "SESSION_START", details: "YAAM session started (PID: \(ProcessInfo.processInfo.processIdentifier))")
    }

    func log(action: String, details: String = "", station: String? = nil) {
        let timestamp = dateFormatter.string(from: Date())
        let stationCall = (station?.isEmpty == false) ? station! : "DEFAULT"
        let cleanDetails = details.replacingOccurrences(of: "\n", with: " ⏎ ")
        let line = "[\(timestamp)] [\(stationCall)] [\(action)] \(cleanDetails)\n"

        queue.async { [weak self] in
            guard let self = self else { return }
            self.write(line: line)
        }
    }

    private func write(line: String) {
        let url = logFileURL
        guard let data = line.data(using: .utf8) else { return }

        if fileManager.fileExists(atPath: url.path) {
            if let fileHandle = try? FileHandle(forWritingTo: url) {
                defer { try? fileHandle.close() }
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func rotateIfNeeded() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let url = self.logFileURL
            guard let attrs = try? self.fileManager.attributesOfItem(atPath: url.path),
                  let fileSize = attrs[.size] as? Int64,
                  fileSize > 15 * 1024 * 1024 else { // 15 MB rotation limit
                return
            }
            let backupURL = url.deletingPathExtension().appendingPathExtension("prev.log")
            try? self.fileManager.removeItem(at: backupURL)
            try? self.fileManager.moveItem(at: url, to: backupURL)
        }
    }

    func revealInFinder() {
        let url = logFileURL
        if !fileManager.fileExists(atPath: url.path) {
            log(action: "AUDIT_LOG_INITIALIZED", details: "Audit log initialized by user action")
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
