#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-modem-lines.XXXXXX)
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
for name in SerialModemLinesRegression SerialPortOwnershipRegression; do
    swiftc "${flags[@]}" "Tests/$name.swift" YAAM/SerialPortService.swift -o "$out/$name"
    "$out/$name"
done
swiftc -parse-as-library -emit-library -emit-module -module-name FT8808Engine Tests/Support/FT8808EngineStandIn.swift \
    -o "$out/libFT8808Engine.dylib" -emit-module-path "$out/FT8808Engine.swiftmodule"
for name in SerialModemDriverRegression TX500VerifiedPTTRegression; do
swiftc "${flags[@]}" -I "$out" -L "$out" -lFT8808Engine -Xlinker -rpath -Xlinker "$out" \
    "Tests/$name.swift" Tests/Support/CATDriverStandIns.swift \
    YAAM/Lab599TX500Driver.swift YAAM/FX4CRDriver.swift YAAM/IcomUSBRadioDriver.swift YAAM/Xiegu6100Driver.swift \
    YAAM/Lab599TX500SMeter.swift YAAM/MorseTiming.swift YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift \
    -o "$out/$name"
"$out/$name"
done
swiftc "${flags[@]}" Tests/SerialKeyerReplacedMessageRegression.swift YAAM/SerialKeyerDriver.swift -o "$out/keyer"
"$out/keyer"
echo "Serial modem-line regressions passed. Binaries: $out"
