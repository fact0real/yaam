#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-outside-input.XXXXXX)
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures
    -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
swiftc "${flags[@]}" Tests/RigctldReplyStreamRegression.swift YAAM/RigctldReplyStream.swift -o "$out/rigctld"
"$out/rigctld"
swiftc "${flags[@]}" Tests/OutsideNumberBoundsRegression.swift YAAM/FrequencyBounds.swift -o "$out/numbers"
"$out/numbers"
swiftc "${flags[@]}" Tests/FieldSpotsFailureRegression.swift YAAM/POTASpotsClient.swift YAAM/POTASOTAModels.swift \
    YAAM/FieldSpotsRadarView.swift YAAM/RadioTuningNotice.swift YAAM/FrequencyBounds.swift YAAM/TXLimits.swift -o "$out/spots"
"$out/spots" "${1:-$out/screenshots}"
# Compile the real service verbatim; expose only its parser through a same-file fixture extension.
cat YAAM/OnTheAirMonitorService.swift > "$out/OnTheAirMonitorService.swift"
cat >> "$out/OnTheAirMonitorService.swift" <<'SWIFT'
extension OnTheAirMonitorService {
    func parseFixture(_ data: Data) -> [OnAirSpot] { parsePSKReporterXML(data) }
}
SWIFT
swiftc "${flags[@]}" Tests/OutsidePSKXMLRegression.swift "$out/OnTheAirMonitorService.swift" YAAM/FrequencyBounds.swift -o "$out/psk-xml"
"$out/psk-xml"
swiftc "${flags[@]}" Tests/FlrigOutsideVFORegression.swift YAAM/FLRigClient.swift YAAM/FlrigXMLRPC.swift YAAM/FrequencyBounds.swift -o "$out/flrig"
"$out/flrig"
