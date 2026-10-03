import Foundation

@main
struct SKEDCountryPrefixRegression {
    static func main() {
        precondition(DXCCDatabase.resolve(callsign: "8P6AA").countryCode == "BB")
        precondition(DXCCDatabase.resolve(callsign: "9Y4AA").countryCode == "TT")
        precondition(DXCCDatabase.resolve(callsign: "EP2AAA").countryCode == "IR")
        print("SKED country prefix regression passed")
    }
}
