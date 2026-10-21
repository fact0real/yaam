#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
regression_dir="$(mktemp -d /tmp/yaam-sked-regressions.XXXXXX)"
trap 'rm -rf "$regression_dir"' EXIT
sources=(YAAM/SKEDCountryDiscovery.swift YAAM/SKEDContactDiscovery.swift YAAM/SKEDDirectoryService.swift YAAM/SKEDGeographyService.swift YAAM/QRZRankAPIContract.swift YAAM/CSVExportSafety.swift YAAM/SKEDPlanning.swift)
for suite in SKEDCountryDiscoveryRegression SKEDContactDiscoveryRegression SKEDDirectoryContractRegression SKEDGeographyContractRegression SKEDPlanningRegression; do
    swiftc -parse-as-library "Tests/$suite.swift" "${sources[@]}" -o "$regression_dir/$suite"
    "$regression_dir/$suite"
done
