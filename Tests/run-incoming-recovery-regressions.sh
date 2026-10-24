#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-incoming-regressions.XXXXXX)
sources=(YAAM/QSLSyncAll.swift YAAM/QSLHub.swift YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift
    YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift
    YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift
    YAAM/FrequencyBounds.swift)
swiftc -parse-as-library Tests/IncomingContactReviewRegression.swift YAAM/IncomingContactReview.swift YAAM/QSOIdentity.swift -o "$out/review"
"$out/review"
swiftc -parse-as-library Tests/QRZIncomingArchiveRegression.swift YAAM/QRZIncomingRecoveryArchive.swift -o "$out/archive"
"$out/archive"
swiftc -parse-as-library Tests/QRZIncomingRecoveryRegression.swift YAAM/AppStateIncomingReview.swift \
    YAAM/IncomingContactReview.swift YAAM/QRZIncomingRecoveryArchive.swift YAAM/QSOIdentity.swift "${sources[@]}" -o "$out/recovery"
"$out/recovery"
swiftc -parse-as-library Tests/IncomingRecoveryDatabaseRegression.swift YAAM/LogbookDatabase.swift \
    YAAM/StationProfile.swift YAAM/TableColumnPolicy.swift YAAM/GridLocator.swift YAAM/SelfContactPolicy.swift YAAM/AwardEngine.swift \
    YAAM/IncomingContactReview.swift YAAM/QSOIdentity.swift "${sources[@]}" -o "$out/database"
"$out/database"
echo "Incoming recovery regressions passed. Binaries: $out"
