//
//  CountryNameNormalizer.swift
//  YAAM
//

import Foundation

/// Produces one stable display name for spelling, casing, punctuation, and
/// formal-name variants that represent the same country or DXCC entity.
/// Distinct DXCC entities are intentionally not collapsed into a parent state.
nonisolated enum CountryNameNormalizer {
    private static let aliasGroups: [(canonical: String, aliases: [String])] = [
        ("Germany", [
            "Federal Republic of Germany", "Federal Rep of Germany",
            "Fed. Rep. of Germany", "Fed Rep of Germany", "Deutschland"
        ]),
        ("Italy", ["Italian Republic", "Republic of Italy", "Italia"]),
        ("Bosnia and Herzegovina", [
            "Bosnia-Herzegovina", "Bosnia Herzegovina", "Bosnia & Herzegovina",
            "Bosnia-Herzegovin", "Bosnia and Herzegovin",
            "Republic of Bosnia and Herzegovina"
        ]),
        ("South Africa", ["Republic of South Africa", "RSA"]),
        ("Mount Athos", ["Mt Athos", "Mt. Athos"]),
        ("Rodrigues Island", [
            "Rodrigues Is.", "Rodrigues Is", "Rodrigues Isl.",
            "Rodriguez Island", "Rodriguez Is.",
            "Rodrigez Island", "Rodrigez Is.", "Rodrigez Is"
        ]),
        ("Balearic Islands", ["Balearic Is.", "Balearic Is", "Balearic Island"]),
        ("USA", [
            "United States", "United States of America", "U.S.A.", "U.S.",
            "US", "America"
        ]),
        ("South Korea", [
            "Republic of Korea", "Korea, Republic of", "Korea (Republic of)",
            "ROK"
        ]),
        ("North Korea", [
            "Democratic People's Republic of Korea", "Korea, D.P.R. of",
            "Korea DPR", "DPRK"
        ]),
        ("Kosovo", ["Republic of Kosovo"]),
        ("Slovakia", ["Slovak Republic", "Republic of Slovakia"]),
        ("Vietnam", ["Viet Nam", "Socialist Republic of Vietnam"]),
        ("Fiji", ["Fiji Islands", "Republic of Fiji"]),
        ("Czech Republic", ["Czechia", "Czech Rep.", "Czech Rep"]),
        ("Moldova", ["Republic of Moldova"]),
        ("Ireland", ["Republic of Ireland", "Eire"]),
        ("Iran", ["Islamic Republic of Iran", "Iran, Islamic Republic of"]),
        ("Turkey", ["Turkiye", "Türkiye", "Republic of Turkiye", "Republic of Türkiye"]),
        ("Syria", ["Syrian Arab Republic"]),
        ("Laos", ["Lao PDR", "Lao People's Democratic Republic"]),
        ("Myanmar", ["Burma", "Republic of the Union of Myanmar"]),
        ("Brunei", ["Brunei Darussalam"]),
        ("Cote d'Ivoire", ["Côte d’Ivoire", "Côte d'Ivoire", "Ivory Coast"]),
        ("Tanzania", ["United Republic of Tanzania", "Tanzania, United Republic of"]),
        ("Cape Verde", ["Cabo Verde", "Republic of Cabo Verde"]),
        ("Eswatini", ["Swaziland", "Kingdom of Eswatini"]),
        ("Gambia", ["The Gambia", "Gambia, The", "Republic of the Gambia"]),
        ("Bahamas", ["The Bahamas", "Bahamas, The", "Commonwealth of the Bahamas"]),
        ("Netherlands", ["The Netherlands", "Netherlands, The", "Kingdom of the Netherlands"]),
        ("Vatican", ["Vatican City", "Vatican City State", "Holy See"]),
        ("Macao", ["Macau", "Macao SAR", "Macao Special Administrative Region"]),
        ("Timor-Leste", ["East Timor", "Democratic Republic of Timor-Leste"]),
        ("Micronesia", ["Federated States of Micronesia", "Micronesia, Federated States of"]),
        ("Bolivia", ["Plurinational State of Bolivia", "Bolivia, Plurinational State of"]),
        ("Venezuela", ["Bolivarian Republic of Venezuela", "Venezuela, Bolivarian Republic of"]),
        ("Palestine", ["State of Palestine", "Palestinian Territory", "Palestinian Territories"]),
        ("North Macedonia", [
            "Macedonia", "Republic of North Macedonia",
            "The Former Yugoslav Republic of Macedonia", "FYROM"
        ]),
        ("Republic of the Congo", [
            "Republic of Congo", "Congo Republic", "Congo (Republic of the)",
            "Congo, Republic of the"
        ]),
        ("Democratic Republic of the Congo", [
            "Democratic Republic of Congo", "Congo, Democratic Republic of the",
            "Congo (Democratic Republic of the)", "DR Congo", "DRC", "Zaire"
        ]),
        ("Curacao", ["Curaçao"]),
        ("Reunion", ["Réunion", "Reunion Island", "Réunion Island"]),
        ("Aland Islands", ["Åland Islands", "Aland Is.", "Åland Is.", "Aland"]),
        ("Sao Tome and Principe", ["São Tomé and Príncipe", "Sao Tome & Principe"]),
        ("Trinidad and Tobago", ["Trinidad & Tobago"]),
        ("United Arab Emirates", ["UAE", "U.A.E."]),
        ("United Nations HQ", ["United Nations Hq", "UN HQ", "United Nations Headquarters"]),
        ("Isle of Man", ["Isle Of Man"])
    ]

    private static let aliasMap: [String: String] = {
        var result: [String: String] = [:]
        for group in aliasGroups {
            for value in [group.canonical] + group.aliases {
                result[rawComparisonKey(value)] = group.canonical
            }
        }
        return result
    }()

    static func canonicalName(_ rawValue: String) -> String {
        let cleaned = cleanedDisplayValue(rawValue)
        guard !cleaned.isEmpty else { return "" }
        if let canonical = aliasMap[rawComparisonKey(cleaned)] {
            return canonical
        }
        return normalizedFallbackCase(cleaned)
    }

    /// Stable key for grouping, filtering, and lookups after alias resolution.
    static func canonicalKey(_ rawValue: String) -> String {
        rawComparisonKey(canonicalName(rawValue))
    }

    static func normalizedFields(_ fields: [String: String]) -> (fields: [String: String], changed: Bool) {
        var result = fields
        var changed = false
        for key in Array(fields.keys) where ["COUNTRY", "MY_COUNTRY"].contains(key.uppercased()) {
            guard let value = fields[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let canonical = canonicalName(value)
            if canonical != value {
                result[key] = canonical
                changed = true
            }
        }
        return (result, changed)
    }

    private static func cleanedDisplayValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2012}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rawComparisonKey(_ value: String) -> String {
        let folded = cleanedDisplayValue(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")

        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func normalizedFallbackCase(_ value: String) -> String {
        let letters = value.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let hasUppercase = letters.contains { CharacterSet.uppercaseLetters.contains($0) }
        let hasLowercase = letters.contains { CharacterSet.lowercaseLetters.contains($0) }
        guard !(hasUppercase && hasLowercase) else { return value }

        var titled = value.lowercased().capitalized(with: Locale(identifier: "en_US_POSIX"))
        for word in ["And", "Of", "The", "In"] {
            titled = titled.replacingOccurrences(of: " \(word) ", with: " \(word.lowercased()) ")
        }
        return titled
    }
}

nonisolated func canonicalCountryName(_ country: String) -> String {
    CountryNameNormalizer.canonicalName(country)
}
