import Foundation

// swiftc -parse-as-library Tests/ReleaseEntitlementsRegression.swift -o /tmp/yaam-entitlements
// /tmp/yaam-entitlements [path/to/signed/Release/YAAM.app]
@main
struct ReleaseEntitlementsRegression {
    static func main() throws {
        let source = try Data(contentsOf: URL(fileURLWithPath: "YAAM/YAAM.entitlements"))
        let plist = try PropertyListSerialization.propertyList(from: source, format: nil) as! [String: Any]
        let doc = try String(contentsOfFile: "DEVELOPER_DOCUMENTATION.md", encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?m)^\| `(com\.apple\.[^`]+)` \|"#)
        let ns = doc as NSString
        let documented = Set(regex.matches(in: doc, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
        precondition(Set(plist.keys) == documented, "Each entitlement must have exactly one documented purpose")
        precondition(plist["com.apple.security.get-task-allow"] == nil, "Never put debugger access in the shared signing plist")
        precondition(plist["com.apple.security.app-sandbox"] as? Bool == true)
        let project = try String(contentsOfFile: "YAAM.xcodeproj/project.pbxproj", encoding: .utf8)
        precondition(project.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;"), "Release must prevent Xcode from restoring debugger access")
        precondition(Set(plist["com.apple.security.temporary-exception.files.home-relative-path.read-write"] as! [String]) == Set([
            "/.tqsl/", "/.tqsl", "/Library/Mobile Documents/", "/Library/Mobile Documents"
        ]))
        if CommandLine.arguments.count > 1 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["-d", "--entitlements", ":-", CommandLine.arguments[1]]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0)
            let signed = try PropertyListSerialization.propertyList(from: output, format: nil) as! [String: Any]
            precondition(signed["com.apple.security.get-task-allow"] == nil, "Signed Release has debugger access")
            precondition(signed["com.apple.security.app-sandbox"] as? Bool == true)
            let identifiers: Set<String> = ["com.apple.application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups"]
            precondition(Set(signed.keys).subtracting(documented).isSubset(of: identifiers), "Unexpected effective Release privilege")
            print("Signed Release: sandbox enabled, no debugger access, no undocumented effective privilege")
        }
        print("ReleaseEntitlementsRegression passed: all \(documented.count) source entitlements documented, debugger access excluded")
    }
}
