#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-ea3jic-review.XXXXXX)
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability
    -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility -module-name YAAM)
swiftc -parse-as-library Tests/SerialPortOwnershipRegression.swift YAAM/SerialPortService.swift -o "$out/serial"
"$out/serial"
swiftc -parse-as-library -emit-library -emit-module -module-name FT8808Engine Tests/Support/FT8808EngineStandIn.swift -o "$out/libFT8808Engine.dylib" -emit-module-path "$out/FT8808Engine.swiftmodule"
python3 - "$out" <<'PY'
from pathlib import Path
import sys
for name in ['Lab599TX500Driver','FX4CRDriver','IcomUSBRadioDriver','Xiegu6100Driver']:
    s=Path('YAAM/'+name+'.swift').read_text()
    # Speed up only freshness/poll clocks, not command handling or safety decisions.
    s=s.replace('self.lastSerialReply >= 6','self.lastSerialReply >= 0.4')
    a=s.index('    private func startSerialHealthWatch()'); b=s.index('    private func scheduleSerialRecovery()',a)
    s=s[:a]+s[a:b].replace('.seconds(1)','.milliseconds(50)')+s[b:]
    s=s.replace('repeating: 1.0','repeating: 0.05').replace('.now() + 1.0','.now() + 0.02')
    s=s.replace('.milliseconds(200)','.milliseconds(20)')
    s=s.replace('.milliseconds(250)','.milliseconds(50)').replace('.milliseconds(300)','.milliseconds(50)')
    Path(sys.argv[1],name+'.swift').write_text(s)
PY
swiftc "${flags[@]}" -I "$out" -L "$out" -lFT8808Engine -Xlinker -rpath -Xlinker "$out" \
 Tests/SerialLinkHealthRegression.swift Tests/Support/CATDriverStandIns.swift \
 "$out/Lab599TX500Driver.swift" "$out/FX4CRDriver.swift" "$out/IcomUSBRadioDriver.swift" "$out/Xiegu6100Driver.swift" \
 YAAM/MorseTiming.swift YAAM/Lab599TX500SMeter.swift YAAM/TXLimits.swift YAAM/TransmitShutdown.swift YAAM/TransmitNotices.swift -o "$out/health"
"$out/health"
