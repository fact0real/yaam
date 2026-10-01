import Foundation

// Standalone: swiftc -parse-as-library Tests/CabrilloFrequencyRegression.swift YAAM/CabrilloFrequency.swift -o /tmp/cf && /tmp/cf
// Expected values follow the Cabrillo 3.0 QSO data spec (wwrof.org): kHz below 50 MHz, band designators from 50 MHz up.
@main
struct CabrilloFrequencyRegression {
    static func main() {
        let cases: [(Double, String)] = [
            (1.840, "1840"), (3.573, "3573"), (7.074, "7074"), (14.074, "14074"), (28.500, "28500"),
            (50.125, "50"), (70.200, "70"), (144.300, "144"), (222.100, "222"), (432.100, "432"), (903.100, "902"),
            (1_296.200, "1.2G"), (2_304.100, "2.3G"), (3_400.100, "3.4G"), (5_760.100, "5.7G"),
            (10_368.100, "10G"), (24_048.100, "24G"), (47_088.100, "47G")
        ]
        for (mhz, expected) in cases {
            let field = CabrilloFrequency.field(mhz: mhz)
            precondition(field == expected, "\(mhz) MHz: expected \(expected), got \(field)")
            precondition(field.count <= 5, "\(field) does not fit the 5-character freq column")
        }
        precondition(CabrilloFrequency.field(mhz: .infinity) == "0")
        precondition(CabrilloFrequency.field(mhz: .nan) == "0")
        precondition(CabrilloFrequency.field(mhz: .greatestFiniteMagnitude) == "0")
        precondition(CabrilloFrequency.designator(forBand: "2m") == "144")
        precondition(CabrilloFrequency.designator(forBand: "23CM") == "1.2G")
        precondition(CabrilloFrequency.designator(forBand: "6mm") == "47G")
        precondition(CabrilloFrequency.designator(forBand: "20M") == nil)
        print("Cabrillo frequency regression tests passed.")
    }
}
