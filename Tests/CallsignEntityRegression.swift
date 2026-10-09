//
//  CallsignEntityRegression.swift
//  YAAM
//
//  Which DXCC entity a callsign written with "/" belongs to.
//  Run from the repository root:
//    swiftc -parse-as-library Tests/CallsignEntityRegression.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift \
//      YAAM/CountryNameNormalizer.swift -o cer && ./cer
//  It checks the shared rule, the built-in resolver (DXCCDatabase.resolve) case by case, and that the CTY file
//  resolver (CTYDatabaseManager.lookup) uses the same rule; that one reads its data from Application Support, so
//  here it is checked in its source. Nothing opens a file outside the repository, a port or a device.
//  The operators in the checks are EA3JIC and EP2AES. A prefix before the callsign is the visited country (CEPT
//  T/R 61-01, 2.3); indicators after it (/P, /M, /QRP ...) say how the station operates; /MM (maritime mobile) and /AM
//  (aeronautical mobile) count for no DXCC entity (ARRL DXCC rules; ADIF DXCC code 0, None).
//

import Foundation

@main
struct CallsignEntityRegression {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            passes += 1
            print("PASS \(label)")
        } else {
            failures += 1
            let extra = detail()
            print("FAIL \(label)" + (extra.isEmpty ? "" : "   [\(extra)]"))
        }
    }

    static func main() {
        // 1. The shared rule
        for call in ["EA3JIC/MM", "EP2AES/AM", "GM/EA3JIC/MM", "ea3jic/mm "] {
            check("\(call) is maritime or aeronautical mobile: in no DXCC entity", CallsignEntityRule.isOutsideAnyEntity(call))
        }
        for call in ["EA3JIC", "EA3JIC/P", "EA3JIC/M", "MM/EA3JIC", "", "MM"] {
            check("\"\(call)\" is not maritime or aeronautical mobile", !CallsignEntityRule.isOutsideAnyEntity(call))
        }
        let stripped: [(String, String)] = [
            ("F/EA3JIC/P", "F/EA3JIC"), ("EA3JIC/EA6/P", "EA3JIC/EA6"), ("W4/EP2AES/P/QRP", "W4/EP2AES"),
            ("EA3JIC/P", "EA3JIC/P"), ("EA3JIC", "EA3JIC"), ("EA8/EA3JIC", "EA8/EA3JIC")
        ]
        for (call, expected) in stripped {
            let got = CallsignEntityRule.withoutTrailingIndicators(call)
            check("\(call) is read as \(expected)", got == expected, got)
        }

        // 2. The built-in resolver, case by case
        let entities: [(String, String)] = [
            ("EA3JIC", "Spain"), ("EA3JIC/P", "Spain"), ("EA3JIC/QRP", "Spain"), ("EA3JIC/M", "Spain"),
            ("EA3JIC/MM", "Unknown"), ("EA3JIC/AM", "Unknown"), ("EP2AES/MM", "Unknown"), ("GM/EA3JIC/MM", "Unknown"),
            ("EA3JIC/EA6", "Balearic Islands"), ("EA3JIC/EA6/P", "Balearic Islands"),
            ("F/EA3JIC", "France"), ("F/EA3JIC/P", "France"),
            ("W4/EP2AES/P", "United States"), ("W4/EP2AES/P/QRP", "United States"),
            ("EA8/EA3JIC/P", "Canary Islands"), ("KH6/EA3JIC", "Hawaii"),
            ("MM/EA3JIC", "Scotland"), ("M/EA3JIC", "England"), ("FF/EA3JIC", "France"),
            ("SV/A", "Mount Athos")
        ]
        for (call, expected) in entities {
            let entity = DXCCDatabase.resolve(callsign: call)
            check("\(call) resolves to \(expected)", entity.entityName == expected, entity.entityName)
        }
        for call in ["EA3JIC/MM", "EP2AES/AM"] {
            let entity = DXCCDatabase.resolve(callsign: call)
            check("\(call) gets no country code and no zones", entity.countryCode == "--" && entity.cqZone == 0 && entity.ituZone == 0,
                  "\(entity.countryCode) CQ \(entity.cqZone) ITU \(entity.ituZone)")
        }

        // 3. The CTY file resolver uses the same rule (checked in its source)
        let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        let ctyPath = URL(fileURLWithPath: root).appendingPathComponent("YAAM/CTYDatabaseManager.swift").path
        guard let cty = try? String(contentsOfFile: ctyPath, encoding: .utf8),
              let start = cty.range(of: "public func lookup(callsign: String)"),
              let end = cty.range(of: "public func lookup(grid: String)", range: start.upperBound..<cty.endIndex) else {
            check("CTYDatabaseManager.swift is readable and has lookup(callsign:)", false, ctyPath)
            finish()
            return
        }
        let lookup = String(cty[start.lowerBound..<end.lowerBound])
        check("CTY lookup: maritime or aeronautical mobile gives no entity",
              lookup.contains("CallsignEntityRule.isOutsideAnyEntity(clean)") && lookup.contains("return nil"))
        check("CTY lookup: trailing indicators are dropped before the prefix is chosen",
              lookup.contains("CallsignEntityRule.withoutTrailingIndicators(clean)"))
        check("CTY lookup: one list of indicators, shared with the built-in resolver",
              lookup.contains("CallsignEntityRule.operatingIndicators") && !lookup.contains("Set<String> = [\"P\""))
        check("CTY lookup: a part before the callsign is always read as a prefix (MM/EA3JIC is Scotland)",
              !lookup.contains("!portableSuffixes.contains(firstPart)"))
        finish()
    }

    static func finish() {
        print("CallsignEntityRegression: \(passes) checks pass, \(failures) fail")
        if failures > 0 { exit(1) }
        print("Callsign entity regression passed")
    }
}
