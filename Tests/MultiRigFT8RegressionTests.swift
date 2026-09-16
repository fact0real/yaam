//
//  MultiRigFT8RegressionTests.swift
//  YAAM Tests
//
//  Automated Regression Suite for Multi-Transceiver FT8 Cluster (SO2R / SO3R)
//  Verifies multi-engine independence, cross-rig TX interlock arbitration,
//  slot configuration serialization, and multi-band logging.
//

import Foundation
@testable import YAAM

@main
struct MultiRigFT8RegressionTests {
    static func main() async {
        print("Running Multi-Rig FT8 Cluster Regression Tests...")
        await testMultiSlotInitialization()
        await testInterlockPolicies()
        await testConfigurationPersistence()
        await testCrossBandOpportunityAggregation()
        await testUnifiedMultiRigLogging()
        print("All Multi-Rig FT8 Cluster Regression Tests PASSED successfully! ⭐️")
    }

    private static func testMultiSlotInitialization() async {
        print("→ Testing Multi-Slot Initialization & Band Allocation...")
        await MainActor.run {
            let hub = MultiRigFT8Hub()
            precondition(!hub.slots.isEmpty, "Hub should initialize with default slots")
            precondition(hub.slots.count >= 3, "Default configuration must have at least 3 transceiver slots")

            let slot1 = hub.slots[0]
            let slot2 = hub.slots[1]
            let slot3 = hub.slots[2]

            // Verify independent frequencies
            precondition(slot1.dialFrequencyHz == 14_074_000, "Slot 1 must default to 20m FT8 (14.074 MHz)")
            precondition(slot2.dialFrequencyHz == 7_074_000, "Slot 2 must default to 40m FT8 (7.074 MHz)")
            precondition(slot3.dialFrequencyHz == 28_074_000, "Slot 3 must default to 10m FT8 (28.074 MHz)")

            // Verify independent driver types
            precondition(slot1.driverType == .icomLAN, "Slot 1 should be Icom LAN")
            precondition(slot2.driverType == .lab599TX500, "Slot 2 should be Lab599 TX-500")
            precondition(slot3.driverType == .transceiverEmulator, "Slot 3 should be Transceiver Emulator")

            // Verify independent FT8 engine instances
            precondition(slot1.engine !== slot2.engine, "Engines must be distinct instances")
            precondition(slot2.engine !== slot3.engine, "Engines must be distinct instances")
            precondition(slot1.engine.dialFrequencyHz == 14_074_000, "Slot 1 engine frequency must be 14.074 MHz")
            precondition(slot2.engine.dialFrequencyHz == 7_074_000, "Slot 2 engine frequency must be 7.074 MHz")

            print("✓ Multi-Slot independent initialization verified.")
        }
    }

    private static func testInterlockPolicies() async {
        print("→ Testing Cross-Rig Transmit Interlock Arbitration...")
        await MainActor.run {
            let coordinator = MultiRigInterlockCoordinator()
            let slot1ID = UUID()
            let slot2ID = UUID()

            // 1. Strict Lockout Policy
            coordinator.policy = .strictLockout
            coordinator.reset()

            let allow1 = coordinator.requestTransmit(slotID: slot1ID, slotName: "Rig 1", slotIndex: 1)
            precondition(allow1, "Rig 1 should be granted transmit when interlock is free")
            precondition(coordinator.activeTransmittingSlotID == slot1ID, "Active slot must be Rig 1")

            let allow2 = coordinator.requestTransmit(slotID: slot2ID, slotName: "Rig 2", slotIndex: 2)
            precondition(!allow2, "Rig 2 MUST be locked out while Rig 1 is transmitting!")

            coordinator.releaseTransmit(slotID: slot1ID)
            precondition(coordinator.activeTransmittingSlotID == nil, "Interlock must be free after Rig 1 release")

            let allow2After = coordinator.requestTransmit(slotID: slot2ID, slotName: "Rig 2", slotIndex: 2)
            precondition(allow2After, "Rig 2 should now be granted transmit")
            coordinator.releaseTransmit(slotID: slot2ID)

            // 2. Concurrent Policy (Unrestricted)
            coordinator.policy = .concurrent
            coordinator.reset()

            let allowConcurrent1 = coordinator.requestTransmit(slotID: slot1ID, slotName: "Rig 1", slotIndex: 1)
            let allowConcurrent2 = coordinator.requestTransmit(slotID: slot2ID, slotName: "Rig 2", slotIndex: 2)
            precondition(allowConcurrent1 && allowConcurrent2, "Both rigs must be permitted in concurrent policy")

            print("✓ Cross-Rig Interlock arbitration verified.")
        }
    }

    private static func testConfigurationPersistence() async {
        print("→ Testing Configuration JSON Serialization & Deserialization...")
        await MainActor.run {
            let original = MultiRigSlotConfig(
                slotIndex: 1,
                name: "Contest IC-7610",
                driverType: .icomLAN,
                dialFrequencyHz: 21_074_000,
                audioInputDeviceUID: "USB-AUDIO-IN-1",
                audioOutputDeviceUID: "USB-AUDIO-OUT-1",
                icomHost: "192.168.1.120",
                icomPort: 50001,
                icomUsername: "operator",
                icomModelName: "IC-7610",
                isEnabled: true
            )

            do {
                let data = try JSONEncoder().encode([original])
                let decoded = try JSONDecoder().decode([MultiRigSlotConfig].self, from: data)
                precondition(decoded.count == 1, "Decoded config count mismatch")
                let recovered = decoded[0]
                precondition(recovered.name == "Contest IC-7610", "Name mismatch")
                precondition(recovered.dialFrequencyHz == 21_074_000, "Frequency mismatch")
                precondition(recovered.icomHost == "192.168.1.120", "Host mismatch")
                precondition(recovered.driverType == .icomLAN, "Driver mismatch")
                print("✓ Configuration persistence verified.")
            } catch {
                fatalError("Serialization failed: \(error)")
            }
        }
    }

    private static func testCrossBandOpportunityAggregation() async {
        print("→ Testing Cross-Band Opportunity Aggregation...")
        await MainActor.run {
            let hub = MultiRigFT8Hub()
            let opps = hub.aggregatedCrossBandOpportunities()
            precondition(opps.isEmpty, "Initial opportunities should be empty before decodes")
            print("✓ Opportunity aggregation structure verified.")
        }
    }

    private static func testUnifiedMultiRigLogging() async {
        print("→ Testing Unified Multi-Rig Log Recording & Radio Tagging...")
        await MainActor.run {
            let appState = AppState()
            let hub = MultiRigFT8Hub()
            hub.configureBridges(with: appState)

            let slot1 = hub.slots[0]
            precondition(slot1.engine.logQSOHandler != nil, "logQSOHandler must be bridged to AppState")

            // Simulate QSO completion on Slot 1 (20m FT8)
            slot1.engine.logQSOHandler?("JA1ABC", "PM95", "-05", "-10", "20m", 14.074)

            // Verify QSO was inserted into AppState records
            let logged = appState.qsoRecords.first { $0.fields["CALL"] == "JA1ABC" }
            precondition(logged != nil, "JA1ABC must be logged into centralized database")
            precondition(logged?.fields["BAND"] == "20m", "Band must match 20m")
            precondition(logged?.fields["MODE"] == "FT8", "Mode must match FT8")
            precondition(logged?.fields["RADIO"] == slot1.name, "RADIO field must record slot name")

            print("✓ Unified Multi-Rig logging verified.")
        }
    }
}
