#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/yaam-incoming-visual.XXXXXX)
# Compile the production views against inert state: no credentials, real profiles or transports.
python3 - "$out/RequestsView.swift" <<'PYTHON'
from pathlib import Path
import sys
source = Path("YAAM/QRZIncomingAndAssistant.swift").read_text()
start = source.index("struct QRZIncomingRequestsView: View")
end = source.index("struct ConfirmationReconciliationView: View", start)
Path(sys.argv[1]).write_text("import SwiftUI\nimport AppKit\n" + source[start:end])
PYTHON
swiftc -parse-as-library Tests/QRZIncomingEmailVisualReview.swift "$out/RequestsView.swift" \
    YAAM/QRZIncomingEmailLookup.swift YAAM/QRZAuthenticationPolicy.swift \
    YAAM/QRZIncomingRecoveryArchive.swift YAAM/QRZIncomingEmailBatch.swift \
    YAAM/QRZIncomingBulkEmailView.swift YAAM/QRZIncomingBulkMail.swift -o "$out/preview"
"$out/preview"
