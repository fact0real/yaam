#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-board-visual.XXXXXX)
images=${1:-Reports/BoardPriorities-20261105}
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
swiftc "${flags[@]}" Tests/BoardPrioritiesVisualReview.swift YAAM/QSLSyncAll.swift YAAM/QSLHub.swift YAAM/EQSLInboxDownload.swift \
    YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift \
    YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift \
    YAAM/CountryNameNormalizer.swift YAAM/FrequencyBounds.swift YAAM/DigitalQSOConfirmation.swift YAAM/DigitalQSOConfirmationSheet.swift \
    YAAM/QSLSyncPreviewSheet.swift -o "$out/review"
"$out/review" "$images"
swiftc "${flags[@]}" -D OLIVIA_VISUAL Tests/BoardPrioritiesVisualReview.swift Tests/Support/TransmitGateStubs.swift \
    Tests/Support/TransmitGateDXCCStub.swift YAAM/OliviaMFSKEngine.swift YAAM/OliviaMFSKView.swift \
    YAAM/TransmitShutdown.swift YAAM/AudioOnlyTransmit.swift YAAM/TXLimits.swift YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o "$out/olivia"
"$out/olivia" "$images"
