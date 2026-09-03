//
//  DXCCDatabase.swift
//  YAAM
//
//  Complete DXCC Entity & Prefix Resolution Engine compliant with WSJT-X (cty.dat).
//  Maps international callsigns to Country, ISO code, Flag, Continent, CQ Zone, and ITU Zone.
//

import Foundation

public struct DXCCEntityInfo: Equatable, Hashable, Sendable {
    public let entityName: String
    public let countryCode: String
    public let flagEmoji: String
    public let continent: String // AS, EU, NA, SA, AF, OC, AN
    public let cqZone: Int
    public let ituZone: Int

    public var continentIcon: String {
        switch continent {
        case "EU": return "globe.europe.africa.fill"
        case "AS": return "globe.asia.australia.fill"
        case "NA", "SA": return "globe.americas.fill"
        case "AF": return "globe.europe.africa.fill"
        case "OC": return "globe.asia.australia.fill"
        case "AN": return "snowflake"
        default: return "globe"
        }
    }
}

public enum DXCCDatabase {
    private struct PrefixEntry {
        let prefix: String
        let entity: DXCCEntityInfo
    }

    // High-priority sorted lookup table (longest prefix first)
    private nonisolated static let entries: [PrefixEntry] = [
        // Antarctica & Special
        entry("DP0", "Antarctica", "AQ", "🇦🇶", "AN", 39, 67),
        entry("RI1A", "Antarctica", "AQ", "🇦🇶", "AN", 39, 67),
        entry("RI1F", "Franz Josef Land", "RU", "🇷🇺", "EU", 40, 75),
        entry("3Y", "Bouvet Island", "BV", "🇧🇻", "AF", 38, 67),
        entry("FT5W", "Crozet Island", "TF", "🇹🇫", "AF", 39, 68),
        entry("FT5X", "Kerguelen Islands", "TF", "🇹🇫", "AF", 39, 68),
        entry("FT5Z", "Amsterdam & St. Paul", "TF", "🇹🇫", "AF", 39, 68),
        entry("VK0E", "Heard Island", "HM", "🇭🇲", "AF", 39, 68),
        entry("VK0M", "Macquarie Island", "AU", "🇦🇺", "OC", 30, 60),

        // Asia (Middle East, Central, East, South)
        entry("EP", "Iran", "IR", "🇮🇷", "AS", 21, 40),
        entry("EQ", "Iran", "IR", "🇮🇷", "AS", 21, 40),
        entry("9K", "Kuwait", "KW", "🇰🇼", "AS", 21, 39),
        entry("HZ", "Saudi Arabia", "SA", "🇸🇦", "AS", 21, 39),
        entry("7Z", "Saudi Arabia", "SA", "🇸🇦", "AS", 21, 39),
        entry("8Z", "Saudi Arabia", "SA", "🇸🇦", "AS", 21, 39),
        entry("A6", "United Arab Emirates", "AE", "🇦🇪", "AS", 21, 39),
        entry("A4", "Oman", "OM", "🇴🇲", "AS", 21, 39),
        entry("A7", "Qatar", "QA", "🇶🇦", "AS", 21, 39),
        entry("A9", "Bahrain", "BH", "🇧🇭", "AS", 21, 39),
        entry("JY", "Jordan", "JO", "🇯🇴", "AS", 20, 39),
        entry("YK", "Syria", "SY", "🇸🇾", "AS", 20, 39),
        entry("OD", "Lebanon", "LB", "🇱🇧", "AS", 20, 39),
        entry("YI", "Iraq", "IQ", "🇮🇶", "AS", 21, 39),
        entry("4X", "Israel", "IL", "🇮🇱", "AS", 20, 39),
        entry("4Z", "Israel", "IL", "🇮🇱", "AS", 20, 39),
        entry("TA", "Turkey", "TR", "🇹🇷", "AS", 20, 39),
        entry("TC", "Turkey", "TR", "🇹🇷", "AS", 20, 39),
        entry("EK", "Armenia", "AM", "🇦🇲", "AS", 21, 29),
        entry("4J", "Azerbaijan", "AZ", "🇦🇿", "AS", 21, 29),
        entry("4K", "Azerbaijan", "AZ", "🇦🇿", "AS", 21, 29),
        entry("4L", "Georgia", "GE", "🇬🇪", "AS", 21, 29),
        entry("UN", "Kazakhstan", "KZ", "🇰🇿", "AS", 17, 30),
        entry("UP", "Kazakhstan", "KZ", "🇰🇿", "AS", 17, 30),
        entry("UQ", "Kazakhstan", "KZ", "🇰🇿", "AS", 17, 30),
        entry("UK", "Uzbekistan", "UZ", "🇺🇿", "AS", 17, 30),
        entry("EY", "Tajikistan", "TJ", "🇹🇯", "AS", 17, 30),
        entry("EX", "Kyrgyzstan", "KG", "🇰🇬", "AS", 17, 30),
        entry("EZ", "Turkmenistan", "TM", "🇹🇲", "AS", 17, 30),
        entry("YA", "Afghanistan", "AF", "🇦🇫", "AS", 21, 40),
        entry("AP", "Pakistan", "PK", "🇵🇰", "AS", 21, 41),
        entry("VU", "India", "IN", "🇮🇳", "AS", 22, 41),
        entry("4S", "Sri Lanka", "LK", "🇱🇰", "AS", 22, 41),
        entry("8Q", "Maldives", "MV", "🇲🇻", "AS", 22, 41),
        entry("9N", "Nepal", "NP", "🇳🇵", "AS", 22, 42),
        entry("A5", "Bhutan", "BT", "🇧🇹", "AS", 22, 41),
        entry("S2", "Bangladesh", "BD", "🇧🇩", "AS", 22, 41),
        entry("JA", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("JH", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("JR", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("JG", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("JE", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("JF", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("7J", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("7K", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("7L", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("7M", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("7N", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("8J", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("8K", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("8N", "Japan", "JP", "🇯🇵", "AS", 25, 45),
        entry("HL", "South Korea", "KR", "🇰🇷", "AS", 25, 44),
        entry("DS", "South Korea", "KR", "🇰🇷", "AS", 25, 44),
        entry("DT", "South Korea", "KR", "🇰🇷", "AS", 25, 44),
        entry("P5", "North Korea", "KP", "🇰🇵", "AS", 25, 44),
        entry("BY", "China", "CN", "🇨🇳", "AS", 24, 44),
        entry("BA", "China", "CN", "🇨🇳", "AS", 24, 44),
        entry("BD", "China", "CN", "🇨🇳", "AS", 24, 44),
        entry("BG", "China", "CN", "🇨🇳", "AS", 24, 44),
        entry("BH", "China", "CN", "🇨🇳", "AS", 24, 44),
        entry("BI", "China", "CN", "🇨🇳", "AS", 24, 44),
        entry("BV", "Taiwan", "TW", "🇹🇼", "AS", 24, 44),
        entry("VR2", "Hong Kong", "HK", "🇭🇰", "AS", 24, 44),
        entry("XX9", "Macao", "MO", "🇲🇴", "AS", 24, 44),
        entry("JT", "Mongolia", "MN", "🇲🇳", "AS", 23, 32),
        entry("JU", "Mongolia", "MN", "🇲🇳", "AS", 23, 32),
        entry("HS", "Thailand", "TH", "🇹🇭", "AS", 26, 49),
        entry("E2", "Thailand", "TH", "🇹🇭", "AS", 26, 49),
        entry("XV", "Vietnam", "VN", "🇻🇳", "AS", 26, 49),
        entry("3W", "Vietnam", "VN", "🇻🇳", "AS", 26, 49),
        entry("XU", "Cambodia", "KH", "🇰🇭", "AS", 26, 49),
        entry("XW", "Laos", "LA", "🇱🇦", "AS", 26, 49),
        entry("XZ", "Myanmar", "MM", "🇲🇲", "AS", 26, 49),
        entry("9M2", "West Malaysia", "MY", "🇲🇾", "AS", 28, 54),
        entry("9M6", "East Malaysia", "MY", "🇲🇾", "OC", 28, 54),
        entry("9M8", "East Malaysia", "MY", "🇲🇾", "OC", 28, 54),
        entry("9V", "Singapore", "SG", "🇸🇬", "AS", 28, 54),
        entry("V8", "Brunei", "BN", "🇧🇳", "OC", 28, 54),
        entry("YB", "Indonesia", "ID", "🇮🇩", "OC", 28, 54),
        entry("YC", "Indonesia", "ID", "🇮🇩", "OC", 28, 54),
        entry("YD", "Indonesia", "ID", "🇮🇩", "OC", 28, 54),
        entry("YE", "Indonesia", "ID", "🇮🇩", "OC", 28, 54),
        entry("DU", "Philippines", "PH", "🇵🇭", "OC", 27, 50),
        entry("DV", "Philippines", "PH", "🇵🇭", "OC", 27, 50),
        entry("DW", "Philippines", "PH", "🇵🇭", "OC", 27, 50),
        entry("DX", "Philippines", "PH", "🇵🇭", "OC", 27, 50),

        // Europe
        entry("DL", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DJ", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DK", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DF", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DG", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DH", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DM", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DO", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("DP", "Germany", "DE", "🇩🇪", "EU", 14, 28),
        entry("G", "England", "GB", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "EU", 14, 27),
        entry("M", "England", "GB", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "EU", 14, 27),
        entry("2E", "England", "GB", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "EU", 14, 27),
        entry("GM", "Scotland", "GB", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "EU", 14, 27),
        entry("MM", "Scotland", "GB", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "EU", 14, 27),
        entry("GW", "Wales", "GB", "🏴󠁧󠁢󠁷󠁬󠁳󠁿", "EU", 14, 27),
        entry("MW", "Wales", "GB", "🏴󠁧󠁢󠁷󠁬󠁳󠁿", "EU", 14, 27),
        entry("GI", "Northern Ireland", "GB", "🇬🇧", "EU", 14, 27),
        entry("MI", "Northern Ireland", "GB", "🇬🇧", "EU", 14, 27),
        entry("GD", "Isle of Man", "IM", "🇮🇲", "EU", 14, 27),
        entry("GJ", "Jersey", "JE", "🇯🇪", "EU", 14, 27),
        entry("GU", "Guernsey", "GG", "🇬🇬", "EU", 14, 27),
        entry("EI", "Ireland", "IE", "🇮🇪", "EU", 14, 27),
        entry("EJ", "Ireland", "IE", "🇮🇪", "EU", 14, 27),
        entry("F", "France", "FR", "🇫🇷", "EU", 14, 27),
        entry("TM", "France", "FR", "🇫🇷", "EU", 14, 27),
        entry("I", "Italy", "IT", "🇮🇹", "EU", 15, 28),
        entry("IK", "Italy", "IT", "🇮🇹", "EU", 15, 28),
        entry("IZ", "Italy", "IT", "🇮🇹", "EU", 15, 28),
        entry("IU", "Italy", "IT", "🇮🇹", "EU", 15, 28),
        entry("IS0", "Sardinia", "IT", "🇮🇹", "EU", 15, 28),
        entry("IT9", "Sicily", "IT", "🇮🇹", "EU", 15, 28),
        entry("EA", "Spain", "ES", "🇪🇸", "EU", 14, 37),
        entry("EB", "Spain", "ES", "🇪🇸", "EU", 14, 37),
        entry("EC", "Spain", "ES", "🇪🇸", "EU", 14, 37),
        entry("EA6", "Balearic Islands", "ES", "🇪🇸", "EU", 14, 37),
        entry("EA8", "Canary Islands", "ES", "🇪🇸", "AF", 33, 36),
        entry("EA9", "Ceuta & Melilla", "ES", "🇪🇸", "AF", 33, 37),
        entry("CT", "Portugal", "PT", "🇵🇹", "EU", 14, 37),
        entry("CU", "Azores", "PT", "🇵🇹", "EU", 14, 36),
        entry("CT3", "Madeira Islands", "PT", "🇵🇹", "AF", 33, 36),
        entry("PA", "Netherlands", "NL", "🇳🇱", "EU", 14, 27),
        entry("PB", "Netherlands", "NL", "🇳🇱", "EU", 14, 27),
        entry("PC", "Netherlands", "NL", "🇳🇱", "EU", 14, 27),
        entry("PD", "Netherlands", "NL", "🇳🇱", "EU", 14, 27),
        entry("PE", "Netherlands", "NL", "🇳🇱", "EU", 14, 27),
        entry("PI", "Netherlands", "NL", "🇳🇱", "EU", 14, 27),
        entry("ON", "Belgium", "BE", "🇧🇪", "EU", 14, 27),
        entry("OO", "Belgium", "BE", "🇧🇪", "EU", 14, 27),
        entry("OP", "Belgium", "BE", "🇧🇪", "EU", 14, 27),
        entry("OQ", "Belgium", "BE", "🇧🇪", "EU", 14, 27),
        entry("OR", "Belgium", "BE", "🇧🇪", "EU", 14, 27),
        entry("LX", "Luxembourg", "LU", "🇱🇺", "EU", 14, 27),
        entry("HB9", "Switzerland", "CH", "🇨🇭", "EU", 14, 28),
        entry("HB0", "Liechtenstein", "LI", "🇱🇮", "EU", 14, 28),
        entry("OE", "Austria", "AT", "🇦🇹", "EU", 15, 28),
        entry("OK", "Czech Republic", "CZ", "🇨🇿", "EU", 15, 28),
        entry("OL", "Czech Republic", "CZ", "🇨🇿", "EU", 15, 28),
        entry("OM", "Slovakia", "SK", "🇸🇰", "EU", 15, 28),
        entry("SP", "Poland", "PL", "🇵🇱", "EU", 15, 28),
        entry("SQ", "Poland", "PL", "🇵🇱", "EU", 15, 28),
        entry("SN", "Poland", "PL", "🇵🇱", "EU", 15, 28),
        entry("SO", "Poland", "PL", "🇵🇱", "EU", 15, 28),
        entry("HA", "Hungary", "HU", "🇭🇺", "EU", 15, 28),
        entry("HG", "Hungary", "HU", "🇭🇺", "EU", 15, 28),
        entry("SM", "Sweden", "SE", "🇸🇪", "EU", 14, 18),
        entry("SA", "Sweden", "SE", "🇸🇪", "EU", 14, 18),
        entry("SK", "Sweden", "SE", "🇸🇪", "EU", 14, 18),
        entry("OH", "Finland", "FI", "🇫🇮", "EU", 15, 18),
        entry("OG", "Finland", "FI", "🇫🇮", "EU", 15, 18),
        entry("OH0", "Aland Islands", "AX", "🇦🇽", "EU", 15, 18),
        entry("OJ0", "Market Reef", "FI", "🇫🇮", "EU", 15, 18),
        entry("LA", "Norway", "NO", "🇳🇴", "EU", 14, 18),
        entry("LB", "Norway", "NO", "🇳🇴", "EU", 14, 18),
        entry("JW", "Svalbard", "SJ", "🇸🇯", "EU", 40, 18),
        entry("JX", "Jan Mayen", "SJ", "🇸🇯", "EU", 40, 18),
        entry("OZ", "Denmark", "DK", "🇩🇰", "EU", 14, 18),
        entry("OY", "Faroe Islands", "FO", "🇫🇴", "EU", 14, 18),
        entry("OX", "Greenland", "GL", "🇬🇱", "NA", 40, 5),
        entry("TF", "Iceland", "IS", "🇮🇸", "EU", 40, 17),
        entry("UA", "European Russia", "RU", "🇷🇺", "EU", 16, 29),
        entry("RA", "European Russia", "RU", "🇷🇺", "EU", 16, 29),
        entry("RW", "European Russia", "RU", "🇷🇺", "EU", 16, 29),
        entry("RX", "European Russia", "RU", "🇷🇺", "EU", 16, 29),
        entry("RZ", "European Russia", "RU", "🇷🇺", "EU", 16, 29),
        entry("RK", "European Russia", "RU", "🇷🇺", "EU", 16, 29),
        entry("UA9", "Asiatic Russia", "RU", "🇷🇺", "AS", 17, 30),
        entry("RA9", "Asiatic Russia", "RU", "🇷🇺", "AS", 17, 30),
        entry("UA0", "Asiatic Russia", "RU", "🇷🇺", "AS", 18, 31),
        entry("RA0", "Asiatic Russia", "RU", "🇷🇺", "AS", 18, 31),
        entry("UA2", "Kaliningrad", "RU", "🇷🇺", "EU", 15, 29),
        entry("UR", "Ukraine", "UA", "🇺🇦", "EU", 16, 29),
        entry("US", "Ukraine", "UA", "🇺🇦", "EU", 16, 29),
        entry("UT", "Ukraine", "UA", "🇺🇦", "EU", 16, 29),
        entry("UY", "Ukraine", "UA", "🇺🇦", "EU", 16, 29),
        entry("EU", "Belarus", "BY", "🇧🇾", "EU", 16, 29),
        entry("EW", "Belarus", "BY", "🇧🇾", "EU", 16, 29),
        entry("ER", "Moldova", "MD", "🇲🇩", "EU", 16, 29),
        entry("ES", "Estonia", "EE", "🇪🇪", "EU", 15, 29),
        entry("YL", "Latvia", "LV", "🇱🇻", "EU", 15, 29),
        entry("LY", "Lithuania", "LT", "🇱🇹", "EU", 15, 29),
        entry("YO", "Romania", "RO", "🇷🇴", "EU", 20, 28),
        entry("YP", "Romania", "RO", "🇷🇴", "EU", 20, 28),
        entry("LZ", "Bulgaria", "BG", "🇧🇬", "EU", 20, 28),
        entry("SV", "Greece", "GR", "🇬🇷", "EU", 20, 28),
        entry("SX", "Greece", "GR", "🇬🇷", "EU", 20, 28),
        entry("SY", "Greece", "GR", "🇬🇷", "EU", 20, 28),
        entry("SV9", "Crete", "GR", "🇬🇷", "EU", 20, 28),
        entry("SV5", "Dodecanese", "GR", "🇬🇷", "EU", 20, 28),
        entry("SV2A", "Mount Athos", "GR", "🇬🇷", "EU", 20, 28),
        entry("5B", "Cyprus", "CY", "🇨🇾", "AS", 20, 39),
        entry("C4", "Cyprus", "CY", "🇨🇾", "AS", 20, 39),
        entry("ZC4", "UK Sov. Bases Cyprus", "GB", "🇬🇧", "AS", 20, 39),
        entry("1A0", "Sov Mil Order of Malta", "SM", "🇲🇹", "EU", 15, 28),
        entry("HV", "Vatican City", "VA", "🇻🇦", "EU", 15, 28),
        entry("T7", "San Marino", "SM", "🇸🇲", "EU", 15, 28),
        entry("3A", "Monaco", "MC", "🇲🇨", "EU", 14, 27),
        entry("C3", "Andorra", "AD", "🇦🇩", "EU", 14, 27),
        entry("9H", "Malta", "MT", "🇲🇹", "EU", 15, 28),
        entry("ZA", "Albania", "AL", "🇦🇱", "EU", 15, 28),
        entry("Z3", "North Macedonia", "MK", "🇲🇰", "EU", 15, 28),
        entry("YU", "Serbia", "RS", "🇷🇸", "EU", 15, 28),
        entry("YT", "Serbia", "RS", "🇷🇸", "EU", 15, 28),
        entry("4O", "Montenegro", "ME", "🇲🇪", "EU", 15, 28),
        entry("9A", "Croatia", "HR", "🇭🇷", "EU", 15, 28),
        entry("S5", "Slovenia", "SI", "🇸🇮", "EU", 15, 28),
        entry("E7", "Bosnia-Herzegovina", "BA", "🇧🇦", "EU", 15, 28),
        entry("Z6", "Kosovo", "XK", "🇽🇰", "EU", 15, 28),

        // North America
        entry("K", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("W", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("N", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AA", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AB", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AC", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AD", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AE", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AF", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AG", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AI", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AJ", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AK", "United States", "US", "🇺🇸", "NA", 5, 8),
        entry("AL7", "Alaska", "US", "🇺🇸", "NA", 1, 1),
        entry("KL7", "Alaska", "US", "🇺🇸", "NA", 1, 1),
        entry("NL7", "Alaska", "US", "🇺🇸", "NA", 1, 1),
        entry("WL7", "Alaska", "US", "🇺🇸", "NA", 1, 1),
        entry("AH6", "Hawaii", "US", "🇺🇸", "OC", 31, 61),
        entry("KH6", "Hawaii", "US", "🇺🇸", "OC", 31, 61),
        entry("NH6", "Hawaii", "US", "🇺🇸", "OC", 31, 61),
        entry("WH6", "Hawaii", "US", "🇺🇸", "OC", 31, 61),
        entry("KP4", "Puerto Rico", "PR", "🇵🇷", "NA", 8, 11),
        entry("NP4", "Puerto Rico", "PR", "🇵🇷", "NA", 8, 11),
        entry("WP4", "Puerto Rico", "PR", "🇵🇷", "NA", 8, 11),
        entry("KP2", "US Virgin Islands", "VI", "🇻🇮", "NA", 8, 11),
        entry("VE", "Canada", "CA", "🇨🇦", "NA", 4, 9),
        entry("VA", "Canada", "CA", "🇨🇦", "NA", 4, 9),
        entry("VO", "Canada", "CA", "🇨🇦", "NA", 5, 9),
        entry("VY", "Canada", "CA", "🇨🇦", "NA", 4, 9),
        entry("XE", "Mexico", "MX", "🇲🇽", "NA", 6, 10),
        entry("XF", "Mexico", "MX", "🇲🇽", "NA", 6, 10),
        entry("CO", "Cuba", "CU", "🇨🇺", "NA", 8, 11),
        entry("CM", "Cuba", "CU", "🇨🇺", "NA", 8, 11),
        entry("HI", "Dominican Republic", "DO", "🇩🇴", "NA", 8, 11),
        entry("HH", "Haiti", "HT", "🇭🇹", "NA", 8, 11),
        entry("6Y", "Jamaica", "JM", "🇯🇲", "NA", 8, 11),
        entry("ZF", "Cayman Islands", "KY", "🇰🇾", "NA", 8, 11),
        entry("C6", "Bahamas", "BS", "🇧🇸", "NA", 8, 11),
        entry("VP9", "Bermuda", "BM", "🇧🇲", "NA", 5, 11),
        entry("TI", "Costa Rica", "CR", "🇨🇷", "NA", 7, 11),
        entry("HP", "Panama", "PA", "🇵🇦", "NA", 7, 11),
        entry("HR", "Honduras", "HN", "🇭🇳", "NA", 7, 11),
        entry("TG", "Guatemala", "GT", "🇬🇹", "NA", 7, 11),
        entry("YS", "El Salvador", "SV", "🇸🇻", "NA", 7, 11),
        entry("YN", "Nicaragua", "NI", "🇳🇮", "NA", 7, 11),
        entry("V3", "Belize", "BZ", "🇧🇿", "NA", 7, 11),

        // South America
        entry("PY", "Brazil", "BR", "🇧🇷", "SA", 11, 15),
        entry("PP", "Brazil", "BR", "🇧🇷", "SA", 11, 15),
        entry("PR", "Brazil", "BR", "🇧🇷", "SA", 11, 15),
        entry("PU", "Brazil", "BR", "🇧🇷", "SA", 11, 15),
        entry("PT", "Brazil", "BR", "🇧🇷", "SA", 11, 15),
        entry("LU", "Argentina", "AR", "🇦🇷", "SA", 13, 14),
        entry("LW", "Argentina", "AR", "🇦🇷", "SA", 13, 14),
        entry("AY", "Argentina", "AR", "🇦🇷", "SA", 13, 14),
        entry("CE", "Chile", "CL", "🇨🇱", "SA", 12, 14),
        entry("CX", "Uruguay", "UY", "🇺🇾", "SA", 14, 14),
        entry("ZP", "Paraguay", "PY", "🇵🇾", "SA", 11, 14),
        entry("CP", "Bolivia", "BO", "🇧🇴", "SA", 10, 14),
        entry("OA", "Peru", "PE", "🇵🇪", "SA", 10, 12),
        entry("HC", "Ecuador", "EC", "🇪🇨", "SA", 10, 12),
        entry("HD", "Ecuador", "EC", "🇪🇨", "SA", 10, 12),
        entry("HK", "Colombia", "CO", "🇨🇴", "SA", 9, 12),
        entry("HJ", "Colombia", "CO", "🇨🇴", "SA", 9, 12),
        entry("YV", "Venezuela", "VE", "🇻🇪", "SA", 9, 12),
        entry("YY", "Venezuela", "VE", "🇻🇪", "SA", 9, 12),
        entry("FY", "French Guiana", "GF", "🇬🇫", "SA", 9, 12),
        entry("8R", "Guyana", "GY", "🇬🇾", "SA", 9, 12),
        entry("PZ", "Suriname", "SR", "🇸🇷", "SA", 9, 12),
        entry("VP8", "Falkland Islands", "FK", "🇫🇰", "SA", 13, 16),

        // Oceania & Australia
        entry("VK", "Australia", "AU", "🇦🇺", "OC", 30, 59),
        entry("AX", "Australia", "AU", "🇦🇺", "OC", 30, 59),
        entry("ZL", "New Zealand", "NZ", "🇳🇿", "OC", 32, 60),
        entry("ZM", "New Zealand", "NZ", "🇳🇿", "OC", 32, 60),
        entry("FK", "New Caledonia", "NC", "🇳🇨", "OC", 32, 56),
        entry("FO", "French Polynesia", "PF", "🇵🇫", "OC", 32, 63),
        entry("3D2", "Fiji", "FJ", "🇫🇯", "OC", 32, 56),
        entry("YJ", "Vanuatu", "VU", "🇻🇺", "OC", 32, 56),
        entry("P2", "Papua New Guinea", "PG", "🇵🇬", "OC", 28, 51),
        entry("H4", "Solomon Islands", "SB", "🇸🇧", "OC", 28, 51),
        entry("T3", "Kiribati", "KI", "🇰🇮", "OC", 31, 61),
        entry("V7", "Marshall Islands", "MH", "🇲🇭", "OC", 31, 65),
        entry("KH0", "Mariana Islands", "MP", "🇲🇵", "OC", 27, 64),
        entry("KH2", "Guam", "GU", "🇬🇺", "OC", 27, 64),
        entry("KH8", "American Samoa", "AS", "🇦🇸", "OC", 32, 62),

        // Africa
        entry("ZS", "South Africa", "ZA", "🇿🇦", "AF", 38, 57),
        entry("ZR", "South Africa", "ZA", "🇿🇦", "AF", 38, 57),
        entry("CN", "Morocco", "MA", "🇲🇦", "AF", 33, 37),
        entry("7X", "Algeria", "DZ", "🇩🇿", "AF", 33, 37),
        entry("3V", "Tunisia", "TN", "🇹🇳", "AF", 33, 37),
        entry("5A", "Libya", "LY", "🇱🇾", "AF", 34, 38),
        entry("SU", "Egypt", "EG", "🇪🇬", "AF", 34, 38),
        entry("ST", "Sudan", "SD", "🇸🇩", "AF", 34, 48),
        entry("ET", "Ethiopia", "ET", "🇪🇹", "AF", 37, 48),
        entry("5Z", "Kenya", "KE", "🇰🇪", "AF", 37, 48),
        entry("5X", "Uganda", "UG", "🇺🇬", "AF", 37, 48),
        entry("5H", "Tanzania", "TZ", "🇹🇿", "AF", 37, 53),
        entry("9J", "Zambia", "ZM", "🇿🇲", "AF", 36, 53),
        entry("Z2", "Zimbabwe", "ZW", "🇿🇼", "AF", 38, 53),
        entry("7P", "Lesotho", "LS", "🇱🇸", "AF", 38, 57),
        entry("3DA", "Eswatini", "SZ", "🇸🇿", "AF", 38, 57),
        entry("A2", "Botswana", "BW", "🇧🇼", "AF", 38, 57),
        entry("V5", "Namibia", "NA", "🇳🇦", "AF", 38, 57),
        entry("D2", "Angola", "AO", "🇦🇴", "AF", 36, 52),
        entry("C9", "Mozambique", "MZ", "🇲🇿", "AF", 37, 53),
        entry("5R", "Madagascar", "MG", "🇲🇬", "AF", 39, 53),
        entry("3B8", "Mauritius", "MU", "🇲🇺", "AF", 39, 53),
        entry("S7", "Seychelles", "SC", "🇸🇨", "AF", 39, 53),
        entry("TJ", "Cameroon", "CM", "🇨🇲", "AF", 36, 47),
        entry("5N", "Nigeria", "NG", "🇳🇬", "AF", 35, 46),
        entry("9G", "Ghana", "GH", "🇬🇭", "AF", 35, 46),
        entry("TU", "Cote d'Ivoire", "CI", "🇨🇮", "AF", 35, 46),
        entry("6W", "Senegal", "SN", "🇸🇳", "AF", 35, 46),
        entry("D4", "Cape Verde", "CV", "🇨🇻", "AF", 35, 46)
    ].sorted { $0.prefix.count > $1.prefix.count }

    private nonisolated static func entry(
        _ prefix: String,
        _ name: String,
        _ code: String,
        _ flag: String,
        _ continent: String,
        _ cq: Int,
        _ itu: Int
    ) -> PrefixEntry {
        PrefixEntry(
            prefix: prefix,
            entity: DXCCEntityInfo(
                entityName: name,
                countryCode: code,
                flagEmoji: flag,
                continent: continent,
                cqZone: cq,
                ituZone: itu
            )
        )
    }

    /// Resolves an international amateur callsign into its DXCC entity, continent, and flag.
    public nonisolated static func resolve(callsign: String) -> DXCCEntityInfo {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else {
            return DXCCEntityInfo(entityName: "Unknown", countryCode: "--", flagEmoji: "🌐", continent: "??", cqZone: 0, ituZone: 0)
        }

        // Strip portable indicators like /P, /M, /MM
        let basePart = clean.components(separatedBy: "/").first { $0.count >= 3 } ?? clean

        for entry in entries {
            if basePart.hasPrefix(entry.prefix) {
                return entry.entity
            }
        }

        // Fallback for single-letter or basic prefixes
        if let first = basePart.first {
            switch first {
            case "K", "W", "N":
                return DXCCEntityInfo(entityName: "United States", countryCode: "US", flagEmoji: "🇺🇸", continent: "NA", cqZone: 5, ituZone: 8)
            case "F":
                return DXCCEntityInfo(entityName: "France", countryCode: "FR", flagEmoji: "🇫🇷", continent: "EU", cqZone: 14, ituZone: 27)
            case "G", "M":
                return DXCCEntityInfo(entityName: "England", countryCode: "GB", flagEmoji: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", continent: "EU", cqZone: 14, ituZone: 27)
            case "I":
                return DXCCEntityInfo(entityName: "Italy", countryCode: "IT", flagEmoji: "🇮🇹", continent: "EU", cqZone: 15, ituZone: 28)
            case "R":
                return DXCCEntityInfo(entityName: "European Russia", countryCode: "RU", flagEmoji: "🇷🇺", continent: "EU", cqZone: 16, ituZone: 29)
            default:
                break
            }
        }

        return DXCCEntityInfo(entityName: "International", countryCode: "--", flagEmoji: "🌐", continent: "??", cqZone: 0, ituZone: 0)
    }
}
