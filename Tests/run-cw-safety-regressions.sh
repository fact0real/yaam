#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-cw-regressions.XXXXXX)
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures
    -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
keyer=(Tests/Support/TransmitGateStubs.swift Tests/Support/TransmitGateDXCCStub.swift
    YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift YAAM/GridLocator.swift YAAM/MorseTiming.swift)
run() {
    local name=$1
    shift
    swiftc "${flags[@]}" "Tests/$name.swift" "$@" -o "$out/$name"
    "$out/$name"
}
if [[ "${1:-}" != "--cat-only" ]]; then
run CWTextSecurityRegression YAAM/MorseTiming.swift
for name in WinKeyerAutoCQRegression CATStopDestinationRegression CWStopOnQuitRegression
do
    run "$name" "${keyer[@]}"
done
for name in CWNoKeyerRefusalRegression AutoCQManualSendRegression
do
    run "$name" "${keyer[@]}" YAAM/ContestESMEngine.swift
done
for name in FlrigCWErrorRegression CWTextFoldingRegression CWReplacedMessageRegression CWSilentClockRegression AutoCQCATRefusalRegression
do
    run "$name" "${keyer[@]}"
done
run TransmitGatesBehaviourRegression "${keyer[@]}" YAAM/ContestESMEngine.swift YAAM/DigitalModemEngine.swift
run SerialKeyerReplacedMessageRegression YAAM/SerialKeyerDriver.swift
run WinKeyerDatasheetRegression YAAM/WinKeyerDriver.swift YAAM/MorseTiming.swift
run HamlibCWStopRegression YAAM/RigControlClient.swift YAAM/MorseTiming.swift
run TransmitIdentityRegression YAAM/TransmitIdentity.swift YAAM/GridLocator.swift
for name in BandAdvisorDecodeCountRegression BandAdvisorClusterRegression
do
    run "$name" YAAM/TacticalBandAdvisor.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift \
        YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift
done
fi
swiftc -parse-as-library -emit-library -emit-module -module-name FT8808Engine \
    Tests/Support/FT8808EngineStandIn.swift -o "$out/libFT8808Engine.dylib" -emit-module-path "$out/FT8808Engine.swiftmodule"
for name in CATChunkStopRegression CATChunkPacingRegression
do
    run "$name" -I "$out" -L "$out" -lFT8808Engine -Xlinker -rpath -Xlinker "$out" \
        Tests/Support/CATDriverStandIns.swift YAAM/Lab599TX500Driver.swift YAAM/FX4CRDriver.swift \
        YAAM/Lab599TX500SMeter.swift YAAM/MorseTiming.swift
done
echo "Requested CW safety regressions passed. Results built in $out"
