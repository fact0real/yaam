import Foundation

// swiftc -parse-as-library YAAM/YAAMUpdatePolicy.swift Tests/SoftwareUpdateRegression.swift -o /tmp/yaam-update-policy
@main
struct SoftwareUpdateRegression {
    static func main() throws {
        let good = "https://yaam.asis.sh/releases/YAAM-1.37.56-macOS.zip"
        func validate(_ raw: String = good, version: String = "1.37.56", build: String = "206", installed: String = "205", bytes: UInt64 = 30_000_000) throws {
            try YAAMUpdatePolicy.validate(archiveURL: URL(string: raw), version: version, build: build, installedBuild: installed, bytes: bytes)
        }
        func rejects(_ name: String, _ body: () throws -> Void) {
            do { try body(); fatalError("Accepted unsafe update: \(name)") }
            catch is YAAMUpdatePolicy.Rejection { }
            catch { fatalError("Wrong error for \(name): \(error)") }
        }
        try validate()
        try validate("https://yaam.asis.sh/releases/YAAM-1.37.57-macOS.zip", version: "1.37.57", build: "207", installed: "206")
        for url in [
            good.replacingOccurrences(of: "https:", with: "http:"),
            good.replacingOccurrences(of: "yaam.asis.sh", with: "yaam.asis.sh.evil.test"),
            good.replacingOccurrences(of: "yaam.asis.sh", with: "evil.test@yaam.asis.sh"),
            good.replacingOccurrences(of: "yaam.asis.sh", with: "yaam.asis.sh:443"),
            good + "?alternate=evil", good + "#fragment",
            good.replacingOccurrences(of: "/releases/", with: "/releases/../other/"),
            good.replacingOccurrences(of: "/YAAM-", with: "/%59AAM-"),
            good.replacingOccurrences(of: "YAAM-", with: "FX-Utility-"),
            good.replacingOccurrences(of: ".zip", with: ".pkg")
        ] { rejects(url) { try validate(url) } }
        rejects("wrong marketing version") { try validate(version: "1.37.57") }
        rejects("same build") { try validate(build: "205") }
        rejects("downgrade") { try validate(build: "99") }
        rejects("build suffix") { try validate(build: "206-beta") }
        rejects("overflow") { try validate(build: "18446744073709551616") }
        rejects("leading zero") { try validate(build: "0206") }
        rejects("invalid installed build") { try validate(installed: "unknown") }
        rejects("missing size") { try validate(bytes: 0) }
        rejects("oversized package") { try validate(bytes: YAAMUpdatePolicy.maximumArchiveBytes + 1) }
        precondition(YAAMUpdatePolicy.mayRelaunch(transmitters: [], cwActive: false))
        precondition(!YAAMUpdatePolicy.mayRelaunch(transmitters: ["rigctld"], cwActive: false))
        precondition(!YAAMUpdatePolicy.mayRelaunch(transmitters: [], cwActive: true))
        precondition(!YAAMUpdatePolicy.mayRelaunch(transmitters: ["FT8", "TCI"], cwActive: true))

        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: "AppInfo.plist")), format: nil) as! [String: Any]
        for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableInstallerLauncherService"] {
            precondition(plist[key] as? Bool == true, "Missing security setting: \(key)")
        }
        precondition(plist["SUSignedFeedFailureExpirationInterval"] as? Int == 0)
        precondition(plist["SUEnableSystemProfiling"] as? Bool == false)
        precondition(plist["SUEnableJavaScript"] as? Bool == false)
        precondition(plist["SUFeedURL"] as? String == YAAMUpdatePolicy.feedURL.absoluteString)
        precondition(Data(base64Encoded: plist["SUPublicEDKey"] as! String)?.count == 32)
        print("SoftwareUpdateRegression passed: origin, product, downgrade, size, TX/CW gate and signed-feed configuration")
    }
}
