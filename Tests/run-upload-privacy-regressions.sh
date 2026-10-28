#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-upload-regressions.XXXXXX)
sources=(YAAM/QSLSyncAll.swift YAAM/QSLHub.swift YAAM/EQSLInboxDownload.swift YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift
    YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift
    YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift
    YAAM/FrequencyBounds.swift)
for name in UploadFieldAllowlistRegression UploadFieldSwitchesRegression QSLSyncAllRegression; do
    swiftc -parse-as-library "Tests/$name.swift" "${sources[@]}" -o "$out/$name"
    "$out/$name"
done
swiftc -parse-as-library Tests/UploadTransportPrivacyRegression.swift "${sources[@]}" \
    YAAM/WavelogClient.swift YAAM/WavelogPushOutcome.swift YAAM/TQSLCoordinator.swift YAAM/UploadFileReader.swift -o "$out/transport"
"$out/transport"
echo "Upload privacy regressions passed. Binaries: $out"
