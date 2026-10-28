#!/usr/bin/env python3
"""Exercise the production archive with its real inbound models, without starting YAAM."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='yaam-received-regression-') as folder:
 p=Path(folder)
 source=(root/'YAAM/QSLInboxEngine.swift').read_text()
 (p/'Models.swift').write_text(source[:source.index('// MARK: - QSL Inbox Engine')])
 subprocess.run(['swiftc','-parse-as-library',str(p/'Models.swift'),str(root/'YAAM/QSLReceivedCardStore.swift'),str(root/'YAAM/QSLMailAttachmentParser.swift'),str(root/'Tests/QSLReceivedCardStoreRegression.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
