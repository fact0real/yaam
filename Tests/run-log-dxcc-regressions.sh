#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-log-dxcc.XXXXXX)
shared=(YAAM/LogDXCCEntity.swift YAAM/DXCCEntityCatalog.swift YAAM/ConfirmationOpportunity.swift
    YAAM/AmateurBandSettings.swift YAAM/OperatorModels.swift YAAM/PortableActivity.swift YAAM/FrequencyBounds.swift
    YAAM/GridLocator.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift)
swiftc -parse-as-library Tests/LogDXCCRegression.swift "${shared[@]}" -o "$out/dxcc"
"$out/dxcc"
swiftc -parse-as-library Tests/RussianEntityGroupingRegression.swift "${shared[@]}" YAAM/ADIFParser.swift YAAM/QSOMetadataFormatter.swift -o "$out/russia"
"$out/russia"
swiftc -parse-as-library Tests/CallsignEntityRegression.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift -o "$out/callsign"
"$out/callsign"
