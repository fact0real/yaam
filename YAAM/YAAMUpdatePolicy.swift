import Foundation

/// Additional product/origin restrictions; Sparkle owns cryptographic validation and installation.
nonisolated enum YAAMUpdatePolicy {
    static let feedURL = URL(string: "https://yaam.asis.sh/updates/appcast.xml")!
    static let maximumArchiveBytes: UInt64 = 512 * 1024 * 1024

    enum Rejection: String, Error {
        case version = "The update has an invalid version or build number."
        case downgrade = "The update is not newer than the installed build."
        case origin = "The update does not point to an approved YAAM release archive."
        case size = "The update archive has an invalid size."
    }

    static func validate(archiveURL: URL?, version: String, build: String, installedBuild: String, bytes: UInt64) throws {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ canonicalInteger(String($0)) != nil }),
              let next = canonicalInteger(build), let installed = canonicalInteger(installedBuild) else {
            throw Rejection.version
        }
        guard next > installed else { throw Rejection.downgrade }
        // Exact comparison also rejects credentials, query strings, fragments, non-default ports,
        // encoded separators, alternate hosts, traversal, and a different product's archive.
        let expected = "https://yaam.asis.sh/releases/YAAM-\(version)-macOS.zip"
        guard archiveURL?.absoluteString == expected else { throw Rejection.origin }
        guard bytes > 0, bytes <= maximumArchiveBytes else { throw Rejection.size }
    }

    private static func canonicalInteger(_ text: String) -> UInt64? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = UInt64(text), String(value) == text else { return nil }
        return value
    }

    static func mayRelaunch(transmitters: [String], cwActive: Bool) -> Bool {
        transmitters.isEmpty && !cwActive
    }
}
