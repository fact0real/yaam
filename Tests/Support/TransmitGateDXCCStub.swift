// DigitalModemEngine asks DXCCDatabase for a country; the real database is a large file of its own. The
// behaviour test of the CW keyer, the contest Enter key and RTTY/PSK uses this empty one. The FT8 test links
// the real YAAM/DXCCDatabase.swift instead and does not compile this file.
import Foundation

struct StubDXCC { var entityName = ""; var flagEmoji = ""; var continent = "" }
enum DXCCDatabase {
    static func resolve(callsign: String) -> StubDXCC { StubDXCC() }
}
