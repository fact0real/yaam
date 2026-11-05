#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-board-priorities.XXXXXX)
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
operator=(YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift
    YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift YAAM/FrequencyBounds.swift)
run() {
    local name=$1
    shift
    swiftc "${flags[@]}" "Tests/$name.swift" "$@" -o "$out/$name"
    "$out/$name"
}
run DigitalQSOConfirmationRegression YAAM/DigitalQSOConfirmation.swift "${operator[@]}"
run QSLSyncAllRegression YAAM/QSLSyncAll.swift YAAM/QSLHub.swift YAAM/EQSLInboxDownload.swift YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift YAAM/QSOMetadataFormatter.swift "${operator[@]}"
run RussianEntityGroupingRegression YAAM/ConfirmationOpportunity.swift YAAM/ADIFParser.swift YAAM/QSOMetadataFormatter.swift YAAM/GridLocator.swift "${operator[@]}"
run FT8OperatingSupportRegression YAAM/FT8OperatingSupport.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift
run OliviaCallsignDetectRegression Tests/Support/TransmitGateStubs.swift Tests/Support/TransmitGateDXCCStub.swift YAAM/OliviaMFSKEngine.swift YAAM/TransmitShutdown.swift YAAM/AudioOnlyTransmit.swift YAAM/TXLimits.swift YAAM/TransmitIdentity.swift YAAM/GridLocator.swift
run TCIOutsideTextRegression YAAM/TCIClient.swift YAAM/MorseTiming.swift YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift
run FlrigOutsideVFORegression YAAM/FLRigClient.swift YAAM/FlrigXMLRPC.swift YAAM/MorseTiming.swift YAAM/FrequencyBounds.swift YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift
run RigFrequencyReadbackRegression YAAM/RigControlClient.swift YAAM/RigctldReplyStream.swift YAAM/MorseTiming.swift YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift
printf 'Board priorities regressions passed. Binaries: %s\n' "$out"
