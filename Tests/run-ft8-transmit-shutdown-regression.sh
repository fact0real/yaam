#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-ft8-shutdown.XXXXXX)
derived=${YAAM_DERIVED_DATA:-build/DerivedData}
codec="$derived/Build/Products/Debug"
includes="$derived/SourcePackages/checkouts/ft8-808/Sources/CFT8/include"
swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
    -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
    -module-name YAAM -I "$codec" -I "$includes" \
    Tests/FT8TransmitShutdownRegression.swift Tests/Support/TransmitGateStubs.swift YAAM/FT8EngineService.swift YAAM/FT8TransmissionTiming.swift \
    YAAM/DigitalContestEngine.swift YAAM/CountryFlagEngine.swift YAAM/DXCCDatabase.swift \
    YAAM/WebSDRReplyPlanner.swift YAAM/CountryNameNormalizer.swift YAAM/TransmitIdentity.swift YAAM/GridLocator.swift \
    YAAM/FT8AudioDecimator.swift YAAM/FT8StationDecoder.swift YAAM/DigitalContactCompletion.swift YAAM/FT8OperatingSupport.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift YAAM/TXLimits.swift "$codec/FT8Codec.o" "$codec/CFT8.o" "$codec/FT8808Engine.o" \
    -o "$out/ft8-shutdown"
"$out/ft8-shutdown"
