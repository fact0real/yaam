#!/usr/bin/env python3
from pathlib import Path
import tempfile,subprocess,sys
root=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]if len(sys.argv)>1 else '/tmp/yaam-received-cards-visual');out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory()as f:
 p=Path(f);s=(root/'YAAM/QSLInboxEngine.swift').read_text();(p/'Models.swift').write_text(s[:s.index('// MARK: - QSL Inbox Engine')])
 subprocess.run(['swiftc','-parse-as-library',str(p/'Models.swift'),str(root/'YAAM/QSLReceivedCardsView.swift'),str(root/'Tests/QSLReceivedCardsVisualReview.swift'),'-o',str(p/'preview')],check=True)
 subprocess.run([str(p/'preview'),str(out)],check=True)
