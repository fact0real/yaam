import Foundation

@main
struct SelfContactPolicyRegression {
    static func main() {
        precondition(SelfContactPolicy.isSelfContact(
            fields: ["CALL": " ep2aes ", "STATION_CALLSIGN": "EP2AES"],
            profileCallsign: "DEFAULT"
        ))
        precondition(SelfContactPolicy.isSelfContact(
            fields: ["CALL": "EP2AES"],
            profileCallsign: "EP2AES"
        ))
        precondition(!SelfContactPolicy.isSelfContact(
            fields: ["CALL": "EP2AES", "STATION_CALLSIGN": "EP2DES"],
            profileCallsign: "EP2AES"
        ))
        precondition(!SelfContactPolicy.isSelfContact(
            fields: ["CALL": "EP2AES"],
            profileCallsign: "DEFAULT"
        ))
        precondition(!SelfContactPolicy.isSelfContact(
            fields: ["CALL": "EP2AES/P", "STATION_CALLSIGN": "EP2AES"],
            profileCallsign: "EP2AES"
        ))
        print("Self-contact policy regression passed")
    }
}
