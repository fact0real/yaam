#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
regression_dir="$(mktemp -d /tmp/yaam-priority-regressions.XXXXXX)"
trap 'rm -rf "$regression_dir"' EXIT
operator_sources=(YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift)
qsl_sources=(YAAM/QSLSyncAll.swift YAAM/QSLHub.swift YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift YAAM/QSOMetadataFormatter.swift "${operator_sources[@]}")
run() {
    local suite="$1"
    shift
    swiftc -parse-as-library "Tests/${suite}.swift" "$@" -o "$regression_dir/$suite"
    "$regression_dir/$suite"
}
run ProtectedCredentialStorageRegression YAAM/ProtectedCredentialStorage.swift
run SecureVaultRegression
run QuickLogReuseRegression YAAM/QuickLogReusePolicy.swift "${operator_sources[@]}"
run DigitalContactCompletionRegression YAAM/DigitalContactCompletion.swift YAAM/ADIFParser.swift YAAM/QSOIdentity.swift YAAM/QSOMetadataFormatter.swift "${operator_sources[@]}"
run CompletedDigitalPersistenceRegression YAAM/AppStateCompletedDigitalContact.swift YAAM/DigitalContactCompletion.swift YAAM/QSOIdentity.swift
run CloudUploadBoundaryRegression YAAM/UploadFileReader.swift
run CloudUploadProviderRegression YAAM/UploadFileReader.swift "${qsl_sources[@]}"
run QRZAuthenticationRegression YAAM/QRZAuthenticationPolicy.swift
run PendingQueueCredentialRegression YAAM/KeychainStore.swift YAAM/ProtectedCredentialStorage.swift
swiftc -D STANDALONE_ADIF -parse-as-library Tests/ADIFLengthRegression.swift YAAM/ADIFParser.swift -o "$regression_dir/adif"
"$regression_dir/adif"
