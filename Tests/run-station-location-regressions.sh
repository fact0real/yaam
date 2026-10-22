#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /tmp/yaam-station-location.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library Tests/PreciseGridLocatorRegression.swift YAAM/PreciseGridLocator.swift YAAM/WeatherLocationPrivacy.swift YAAM/MaidenheadGridEngine.swift YAAM/AstronomicalSolarEngine.swift YAAM/StationLocationProfileUpdate.swift YAAM/StationProfile.swift YAAM/GridLocator.swift YAAM/CountryNameNormalizer.swift -o "$test_dir/grid"
"$test_dir/grid"
swiftc -D STANDALONE_PRIVACY_TEST -parse-as-library Tests/StationPrivacyRegression.swift YAAM/WeatherLocationPrivacy.swift YAAM/StationWeatherSafetyEngine.swift YAAM/StationProfile.swift YAAM/GridLocator.swift YAAM/CountryNameNormalizer.swift YAAM/CountryFlagEngine.swift YAAM/QSLCardStationInfo.swift YAAM/QSLCardView.swift YAAM/CallHistoryLookupEngine.swift -o "$test_dir/privacy"
"$test_dir/privacy"
