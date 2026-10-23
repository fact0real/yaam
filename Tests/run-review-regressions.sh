#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-review-regressions.XXXXXX)
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures
    -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
swiftc "${flags[@]}" Tests/DigitalReceiveReviewRegression.swift Tests/Support/TransmitGateStubs.swift \
    Tests/Support/TransmitGateDXCCStub.swift YAAM/DigitalModemEngine.swift YAAM/HellschreiberEngine.swift \
    YAAM/OliviaMFSKEngine.swift YAAM/TransmitShutdown.swift YAAM/AudioOnlyTransmit.swift YAAM/TXLimits.swift YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o "$out/digital"
"$out/digital"
swiftc "${flags[@]}" Tests/CWConnectionLossRegression.swift Tests/Support/TransmitGateStubs.swift \
    Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/MorseTiming.swift YAAM/TXLimits.swift \
    YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o "$out/cw"
"$out/cw"
derived=${YAAM_DERIVED_DATA:-build/DerivedData}
codec="$derived/Build/Products/Debug"
includes="$derived/SourcePackages/checkouts/ft8-808/Sources/CFT8/include"
swiftc -parse-as-library -I "$codec" -I "$includes" Tests/FT8TimingCalibrationRegression.swift \
    YAAM/FT8StationDecoder.swift "$codec/FT8Codec.o" "$codec/CFT8.o" -o "$out/ft8"
"$out/ft8"
swiftc -parse-as-library -I "$codec" -I "$includes" Tests/FT8ExpandedDecodeRegression.swift \
    YAAM/FT8StationDecoder.swift "$codec/FT8Codec.o" "$codec/CFT8.o" -o "$out/ft8-expanded"
"$out/ft8-expanded"
echo "Review regressions passed. Binaries: $out"
