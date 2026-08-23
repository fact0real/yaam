import Foundation

nonisolated enum AmateurBandPlan {
    static func formattedMHz(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    static func band(forMHz value: Double) -> String? {
        switch value {
        case 1.8..<2.0: return "160m"
        case 7.0..<7.3: return "40m"
        case 14.0..<14.4: return "20m"
        case 50.0..<54.0: return "6m"
        default: return nil
        }
    }
}

@main
struct IcomNetworkTransportRegression {
    static func main() {
        precondition(
            IcomNetworkRadio.civCodecSelfTest(),
            "Icom CI-V frequency codec self-test failed."
        )
        precondition(
            IcomNetworkRadio.credentialBoundsSelfTest(),
            "Icom credential byte-bound self-test failed."
        )
        precondition(
            IcomNetworkRadio.authenticationPacketLayoutSelfTest(),
            "Icom authentication packet layout self-test failed."
        )
        do {
            try IcomNetworkRadio.runUDPTransportSelfTest()
        } catch {
            preconditionFailure("Protected Icom UDP transport self-test failed: \(error.localizedDescription)")
        }
        print("Icom network transport regression tests passed.")
    }
}
