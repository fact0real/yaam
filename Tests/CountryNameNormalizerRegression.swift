import Foundation

@main
struct CountryNameNormalizerRegression {
    static func main() {
        assertAliases("Germany", [
            "Germany", "GERMANY", "Federal Republic of Germany",
            "Fed. Rep. of Germany", "Deutschland"
        ])
        assertAliases("Italy", ["Italy", "ITALY", "italy", "Italian Republic"])
        assertAliases("Bosnia and Herzegovina", [
            "Bosnia-Herzegovina", "Bosnia & Herzegovina",
            "Bosnia-Herzegovin", "Bosnia and Herzegovin"
        ])
        assertAliases("South Africa", ["South Africa", "Republic of South Africa"])
        assertAliases("South Korea", ["Republic Of Korea", "Korea, Republic of", "ROK"])
        assertAliases("Slovakia", ["Slovak Republic", "SLOVAKIA"])
        assertAliases("Vietnam", ["Viet Nam", "VIETNAM"])
        assertAliases("Kosovo", ["Republic Of Kosovo", "Kosovo"])
        assertAliases("Fiji", ["Fiji Islands", "FIJI"])
        assertAliases("Republic of the Congo", ["Congo (Republic of the)", "Republic of Congo"])
        assertAliases("Democratic Republic of the Congo", ["DR Congo", "Zaire"])

        precondition(canonicalCountryName("Crete") != canonicalCountryName("Greece"))
        precondition(canonicalCountryName("European Russia") != canonicalCountryName("Asiatic Russia"))
        precondition(canonicalCountryName("England") != canonicalCountryName("Scotland"))
        precondition(canonicalCountryName("Republic of the Congo") != canonicalCountryName("Democratic Republic of the Congo"))

        let normalized = CountryNameNormalizer.normalizedFields([
            "COUNTRY": "FEDERAL REPUBLIC OF GERMANY",
            "MY_COUNTRY": "islamic republic of iran",
            "COMMENT": "Preserve this value exactly"
        ])
        precondition(normalized.changed)
        precondition(normalized.fields["COUNTRY"] == "Germany")
        precondition(normalized.fields["MY_COUNTRY"] == "Iran")
        precondition(normalized.fields["COMMENT"] == "Preserve this value exactly")

        print("Country name normalization regression tests passed.")
    }

    private static func assertAliases(_ expected: String, _ aliases: [String]) {
        for alias in aliases {
            precondition(
                canonicalCountryName(alias) == expected,
                "Expected '\(alias)' to normalize to '\(expected)', got '\(canonicalCountryName(alias))'."
            )
            precondition(CountryNameNormalizer.canonicalKey(alias) == CountryNameNormalizer.canonicalKey(expected))
        }
    }
}
