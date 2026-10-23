#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-workspace-regressions.XXXXXX)
python3 - "$out/AppStateMethods.swift" <<'PY'
from pathlib import Path
import sys
app=Path('YAAM/AppState.swift').read_text()
contest=Path('YAAM/AppStateRadioContestFeatures.swift').read_text()
save=app[app.index('    func autoSaveActiveWorkspace('):app.index('    func importLogDialog()', app.index('    func autoSaveActiveWorkspace('))]
log=contest[contest.index('    @MainActor\n    func logContestFastQSO('):contest.index('    func validateCurrentContestCabrillo()', contest.index('    func logContestFastQSO('))]
fixture=Path('Tests/Support/WorkspaceReviewStubs.swift').read_text()
Path(sys.argv[1]).write_text(fixture.replace('    // ACTUAL_METHODS', save+'\n'+log))
PY
swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
    -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
    Tests/WorkspaceSaveAndContestReviewRegression.swift "$out/AppStateMethods.swift" YAAM/ADIFParser.swift \
    YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift \
    YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift YAAM/FrequencyBounds.swift -o "$out/workspace"
"$out/workspace"
