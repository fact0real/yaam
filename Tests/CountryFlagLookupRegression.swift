//
//  CountryFlagLookupRegression.swift
//  YAAM Tests
//

import Foundation

@main
struct CountryFlagLookupRegression {
    static func main() {
        print("Running Country Flag Lookup Regression Tests...")
        testUserScreenshotCases()
        testCallsignPrefixFallbacks()
        testSpecialDXCCEntities()
        testISOCodes()
        print("All Country Flag Lookup Regression Tests PASSED successfully!")
    }

    private static func testUserScreenshotCases() {
        // 1. Franz Josef Land
        precondition(countryToFlag("FRANZ JOSEF LAND") == "🇷🇺", "Failed on FRANZ JOSEF LAND")
        precondition(countryToFlag("RI1FJL") == "🇷🇺", "Failed on RI1FJL callsign prefix")

        // 2. Mozambique
        precondition(countryToFlag("MOZAMBIQUE") == "🇲🇿", "Failed on MOZAMBIQUE")
        precondition(countryToFlag("C91CCY") == "🇲🇿", "Failed on C91CCY callsign prefix")

        // 3. San Andres Island
        precondition(countryToFlag("SAN ANDRES ISLAND") == "🇨🇴", "Failed on SAN ANDRES ISLAND")
        precondition(countryToFlag("San Andres & Providencia") == "🇨🇴", "Failed on San Andres & Providencia")
        precondition(countryToFlag("HK0RNR") == "🇨🇴", "Failed on HK0RNR callsign prefix")

        // 4. Antarctica
        precondition(countryToFlag("ANTARCTICA") == "🇦🇶", "Failed on ANTARCTICA")
        precondition(countryToFlag("RI1ANC") == "🇦🇶", "Failed on RI1ANC callsign prefix")
        precondition(countryToFlag("DP0GVN") == "🇦🇶", "Failed on DP0GVN callsign prefix")

        // 5. Papua New Guinea
        precondition(countryToFlag("PAPUA NEW GUINEA") == "🇵🇬", "Failed on PAPUA NEW GUINEA")
        precondition(countryToFlag("P29YY") == "🇵🇬", "Failed on P29YY callsign prefix")

        // 6. Trinidad & Tobago
        precondition(countryToFlag("TRINIDAD & TOBAGO") == "🇹🇹", "Failed on TRINIDAD & TOBAGO")
        precondition(countryToFlag("9Y4DG") == "🇹🇹", "Failed on 9Y4DG callsign prefix")

        // 7. Zimbabwe
        precondition(countryToFlag("ZIMBABWE") == "🇿🇼", "Failed on ZIMBABWE")
        precondition(countryToFlag("Z21ML") == "🇿🇼", "Failed on Z21ML callsign prefix")

        // 8. Nepal
        precondition(countryToFlag("NEPAL") == "🇳🇵", "Failed on NEPAL")
        precondition(countryToFlag("9N/ON0GA") == "🇳🇵", "Failed on 9N/ON0GA callsign prefix")

        // 9. Alaska & Aland
        precondition(countryToFlag("ALASKA") == "🇺🇸", "Failed on ALASKA")
        precondition(countryToFlag("NL8F") == "🇺🇸", "Failed on NL8F callsign prefix")
        precondition(countryToFlag("ALAND ISLANDS") == "🇦🇽", "Failed on ALAND ISLANDS")
        precondition(countryToFlag("OH0Z") == "🇦🇽", "Failed on OH0Z callsign prefix")

        // 10. Dominican Republic, Mexico, Nigeria
        precondition(countryToFlag("DOMINICAN REPUBLIC") == "🇩🇴", "Failed on DOMINICAN REPUBLIC")
        precondition(countryToFlag("HI8CQ") == "🇩🇴", "Failed on HI8CQ callsign prefix")
        precondition(countryToFlag("MEXICO") == "🇲🇽", "Failed on MEXICO")
        precondition(countryToFlag("XE1PM") == "🇲🇽", "Failed on XE1PM callsign prefix")
        precondition(countryToFlag("NIGERIA") == "🇳🇬", "Failed on NIGERIA")
        precondition(countryToFlag("5N0YEN") == "🇳🇬", "Failed on 5N0YEN callsign prefix")
    }

    private static func testCallsignPrefixFallbacks() {
        precondition(flagFromCallsignPrefix("EP2AES") == "🇮🇷", "EP2AES prefix failed")
        precondition(flagFromCallsignPrefix("JA1ABC") == "🇯🇵", "JA1ABC prefix failed")
        precondition(flagFromCallsignPrefix("W1AW") == "🇺🇸", "W1AW prefix failed")
        precondition(flagFromCallsignPrefix("DL1XYZ") == "🇩🇪", "DL1XYZ prefix failed")
        precondition(flagFromCallsignPrefix("F6KOP") == "🇫🇷", "F6KOP prefix failed")
        precondition(flagFromCallsignPrefix("EA3JE") == "🇪🇸", "EA3JE prefix failed")
        precondition(flagFromCallsignPrefix("PY2DS") == "🇧🇷", "PY2DS prefix failed")
        precondition(flagFromCallsignPrefix("VK3DAN") == "🇦🇺", "VK3DAN prefix failed")
        precondition(flagFromCallsignPrefix("ZL1BQD") == "🇳🇿", "ZL1BQD prefix failed")
        precondition(flagFromCallsignPrefix("UR5KGG") == "🇺🇦", "UR5KGG prefix failed")
        precondition(flagFromCallsignPrefix("RA3LBM") == "🇷🇺", "RA3LBM prefix failed")
        precondition(flagFromCallsignPrefix("BY1AA") == "🇨🇳", "BY1AA prefix failed")
        precondition(flagFromCallsignPrefix("VU2PTT") == "🇮🇳", "VU2PTT prefix failed")
    }

    private static func testSpecialDXCCEntities() {
        precondition(countryToFlag("Svalbard") == "🇸🇯")
        precondition(countryToFlag("Jan Mayen") == "🇸🇯")
        precondition(countryToFlag("Mount Athos") == "🇬🇷")
        precondition(countryToFlag("Market Reef") == "🇫🇮")
        precondition(countryToFlag("Easter Island") == "🇨🇱")
        precondition(countryToFlag("Galapagos Islands") == "🇪🇨")
        precondition(countryToFlag("Saint Helena") == "🇸🇭")
        precondition(countryToFlag("Ascension Island") == "🇸🇭")
        precondition(countryToFlag("Tristan da Cunha") == "🇸🇭")
        precondition(countryToFlag("Falkland Islands") == "🇫🇰")
        precondition(countryToFlag("South Georgia") == "🇬🇸")
        precondition(countryToFlag("Bouvet Island") == "🇧🇻")
        precondition(countryToFlag("Heard Island") == "🇭🇲")
        precondition(countryToFlag("Norfolk Island") == "🇳🇫")
        precondition(countryToFlag("Christmas Island") == "🇨🇽")
        precondition(countryToFlag("Cocos (Keeling) Islands") == "🇨🇨")
        precondition(countryToFlag("Lord Howe Island") == "🇦🇺")
        precondition(countryToFlag("Pitcairn Island") == "🇵🇳")
        precondition(countryToFlag("Bermuda") == "🇧🇲")
        precondition(countryToFlag("Cayman Islands") == "🇰🇾")
        precondition(countryToFlag("Turks & Caicos") == "🇹🇨")
        precondition(countryToFlag("Guam") == "🇬🇺")
        precondition(countryToFlag("Saipan") == "🇲🇵")
        precondition(countryToFlag("American Samoa") == "🇦🇸")
        precondition(countryToFlag("French Polynesia") == "🇵🇫")
        precondition(countryToFlag("New Caledonia") == "🇳🇨")
    }

    private static func testISOCodes() {
        precondition(countryToFlag("IR") == "🇮🇷")
        precondition(countryToFlag("US") == "🇺🇸")
        precondition(countryToFlag("DE") == "🇩🇪")
        precondition(countryToFlag("JP") == "🇯🇵")
        precondition(countryToFlag("IT") == "🇮🇹")
        precondition(countryToFlag("FR") == "🇫🇷")
    }
}
