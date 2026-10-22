#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-transmit-integration.XXXXXX)
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures
    -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
swiftc -parse-as-library -emit-library -emit-module -module-name FT8808Engine \
    Tests/Support/FT8808EngineStandIn.swift -o "$out/libFT8808Engine.dylib" -emit-module-path "$out/FT8808Engine.swiftmodule"
swiftc "${flags[@]}" -I "$out" -L "$out" -lFT8808Engine -Xlinker -rpath -Xlinker "$out" \
    Tests/TransmitShutdownRegression.swift Tests/Support/CATDriverStandIns.swift \
    YAAM/RigControlEngine.swift YAAM/TCIClient.swift YAAM/FlrigXMLRPC.swift \
    YAAM/Lab599TX500Driver.swift YAAM/FX4CRDriver.swift YAAM/IcomUSBRadioDriver.swift YAAM/Xiegu6100Driver.swift \
    YAAM/Lab599TX500SMeter.swift YAAM/MorseTiming.swift YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift \
    -o "$out/shutdown"
"$out/shutdown"
swiftc "${flags[@]}" Tests/TCIReleaseIntegrationRegression.swift YAAM/TCIClient.swift YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift -o "$out/tci"
"$out/tci"
# Append only a fixture extension in a temporary copy; the PTT implementation is compiled verbatim.
cat YAAM/IcomNetworkRadio.swift > "$out/IcomNetworkRadio.swift"
cat >> "$out/IcomNetworkRadio.swift" <<'SWIFT'
extension IcomNetworkRadio {
    @MainActor func primeSafetyFixture() {
        assertNoSafetyFixtureSockets()
        state = .connected
        transmitArmed = true
    }
    @MainActor func assertNoSafetyFixtureSockets() {
        precondition(controlSocket == nil && civSocket == nil && audioSocket == nil)
    }
}
SWIFT
swiftc "${flags[@]}" Tests/IcomNetworkPTTSafetyRegression.swift "$out/IcomNetworkRadio.swift" \
    Tests/Support/CATDriverStandIns.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift YAAM/TXLimits.swift \
    -o "$out/icom-network"
"$out/icom-network"
swiftc "${flags[@]}" Tests/TransmitShutdownRegistryRegression.swift YAAM/TransmitShutdown.swift -o "$out/registry"
"$out/registry"
swiftc "${flags[@]}" -I "$out" -L "$out" -lFT8808Engine -Xlinker -rpath -Xlinker "$out" \
    Tests/RigControlReleaseDestinationRegression.swift Tests/Support/CATDriverStandIns.swift \
    YAAM/RigControlEngine.swift YAAM/FlrigXMLRPC.swift YAAM/Lab599TX500Driver.swift YAAM/FX4CRDriver.swift \
    YAAM/IcomUSBRadioDriver.swift YAAM/Xiegu6100Driver.swift YAAM/Lab599TX500SMeter.swift YAAM/MorseTiming.swift \
    YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift -o "$out/rig-destination"
"$out/rig-destination"
# Accelerate only the timer's sleep in a temporary source copy; keep the routing/release implementation verbatim.
python3 - "$out" <<'PYFIXTURE'
from pathlib import Path
import sys
source = Path("YAAM/RigControlEngine.swift").read_text()
clock = "try? await Task.sleep(for: .seconds(TXLimits.rigctldPTT))"
assert source.count(clock) == 1
Path(sys.argv[1], "RigControlEngine.swift").write_text(source.replace(clock, "try? await Task.sleep(for: .milliseconds(50))"))
PYFIXTURE
swiftc "${flags[@]}" -I "$out" -L "$out" -lFT8808Engine -Xlinker -rpath -Xlinker "$out" \
    Tests/RigControlReleaseDestinationRegression.swift Tests/Support/CATDriverStandIns.swift \
    "$out/RigControlEngine.swift" YAAM/FlrigXMLRPC.swift YAAM/Lab599TX500Driver.swift YAAM/FX4CRDriver.swift \
    YAAM/IcomUSBRadioDriver.swift YAAM/Xiegu6100Driver.swift YAAM/Lab599TX500SMeter.swift YAAM/MorseTiming.swift \
    YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift -o "$out/rig-watchdog"
"$out/rig-watchdog" --watchdog-only
echo "Transmit integration regressions passed. Binaries: $out"
