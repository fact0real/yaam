#!/bin/bash
# Build first. Package an already signed, sandboxed app; keys stay in the login Keychain.
set -euo pipefail
if [[ $# != 2 ]]; then
    printf 'Usage: SPARKLE_TOOLS=/path/to/Sparkle/bin %s /path/to/YAAM.app /path/to/release-directory\n' "$0" >&2
    exit 2
fi
app=$1
out=$2
tools=${SPARKLE_TOOLS:?Set SPARKLE_TOOLS to the pinned Sparkle distribution bin directory}
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")
[[ "$bundle" == ASIS.YAAM && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]] || exit 3
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$out"
archive="$out/YAAM-$version-macOS.zip"
[[ ! -e "$archive" ]] || { printf 'Archive already exists; never overwrite a published build.\n' >&2; exit 4; }
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
"$tools/generate_appcast" --account ASIS.YAAM.updates \
    --download-url-prefix https://yaam.asis.sh/releases/ \
    --link https://yaam.asis.sh/ --maximum-deltas 0 --embed-release-notes "$out"
"$tools/sign_update" --account ASIS.YAAM.updates --verify "$out/appcast.xml"
/usr/bin/shasum -a 256 "$archive"
printf 'Publish the archive under /releases/ and the signed, unchanged appcast under /updates/.\n'
