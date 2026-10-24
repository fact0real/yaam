#!/usr/bin/env python3
"""Build an inert native app using the production Incoming and rejection views for CUA visual review."""
from pathlib import Path
import plistlib
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/yaam-incoming-email-visual')
out.mkdir(parents=True, exist_ok=True)
source = (root/'YAAM/QRZIncomingAndAssistant.swift').read_text()
views = source[source.index('struct QRZIncomingRequestsView: View'):source.index('struct ConfirmationReconciliationView: View')]
(out/'Views.swift').write_text('import SwiftUI\nimport AppKit\n' + views)
app = out/'Incoming Email Preview.app'
mac = app/'Contents/MacOS'
mac.mkdir(parents=True, exist_ok=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'IncomingEmailPreview', 'CFBundleIdentifier': 'org.yaam.incoming-email-preview.' + out.name, 'CFBundleName': 'Incoming Email Preview', 'CFBundlePackageType': 'APPL'}))
subprocess.run(['swiftc', '-parse-as-library', str(root/'Tests/QRZIncomingEmailVisualReview.swift'), str(out/'Views.swift'), str(root/'YAAM/QRZIncomingEmailLookup.swift'), str(root/'YAAM/QRZAuthenticationPolicy.swift'), str(root/'YAAM/QRZIncomingRecoveryArchive.swift'), '-o', str(mac/'IncomingEmailPreview')], check=True)
print(app)
