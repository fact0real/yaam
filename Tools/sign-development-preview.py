#!/usr/bin/env python3
"""Stage an explicitly non-notarized preview without applying host privileges to Sparkle helpers."""
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile

if len(sys.argv) != 3:
    raise SystemExit("Usage: sign-development-preview.py source.app new-staged.app")
source, staged = map(lambda p: Path(p).resolve(), sys.argv[1:])
if not source.is_dir() or staged.exists() or source == staged:
    raise SystemExit("Source must exist; staged destination must be new")
subprocess.run(["/usr/bin/ditto", str(source), str(staged)], check=True)
framework = staged / "Contents/Frameworks/Sparkle.framework"
version = framework / "Versions/B"
if not version.is_dir():
    raise SystemExit("Expected the pinned Sparkle framework before signing")
for relative in ["XPCServices/Downloader.xpc", "XPCServices/Installer.xpc", "Autoupdate", "Updater.app"]:
    path = version / relative
    if path.exists():
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime",
                        "--preserve-metadata=entitlements", str(path)], check=True)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime", str(framework)], check=True)
info = plistlib.loads((staged / "Contents/Info.plist").read_bytes())
repo = Path(__file__).resolve().parent.parent
entitlements = plistlib.loads((repo / "YAAM/YAAM.entitlements").read_bytes())
entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = [
    info["CFBundleIdentifier"] + suffix for suffix in ("-spks", "-spki")
]
with tempfile.TemporaryDirectory(prefix="yaam-preview-sign-") as temp:
    path = Path(temp) / "entitlements.plist"
    path.write_bytes(plistlib.dumps(entitlements))
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements", str(path), str(staged)], check=True)
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged)], check=True)
print("Staged ad-hoc developer preview (not Apple-notarized):", staged)
