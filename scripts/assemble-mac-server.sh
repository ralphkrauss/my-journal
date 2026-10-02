#!/bin/bash
# Put executable code and configuration in the standard nested application-bundle locations.
# The server runs in the sandbox of the app that starts it, so it is signed with exactly the App Sandbox and
# inherit entitlements. It has no hardened runtime, which the Mac App Store doesn't require and which would stop
# the .NET JIT compiler unless the server also claimed the JIT entitlement.
set -euo pipefail
source_dir="${1:?Usage: assemble-mac-server.sh <published-server-directory> <new-app-bundle> <client-Info.plist> [signing-identity]}"
bundle="${2:?Choose a new app bundle path}"
client_info="${3:?Provide the client Info.plist for matching version metadata}"
identity="${4:--}"
entitlements="$(cd "$(dirname "$0")/.." && pwd)/packaging/server-sandbox.entitlements"
[[ ! -e "$bundle" ]] || {
  echo "Server bundle already exists." >&2
  exit 2
}
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$source_dir/Journal.Api" "$bundle/Contents/MacOS/Journal.Api"
for library in "$source_dir"/*.dylib; do
  cp "$library" "$bundle/Contents/MacOS/"
done
cp "$source_dir/appsettings.json" "$source_dir/LICENSE" "$source_dir/NOTICE" "$source_dir/THIRD-PARTY-NOTICES.txt" \
  "$bundle/Contents/Resources/"
python3 - "$bundle/Contents/Info.plist" "$client_info" <<'PY'
import plistlib
import sys
with open(sys.argv[2], "rb") as source:
    client = plistlib.load(source)
with open(sys.argv[1], "wb") as output:
    plistlib.dump({
        "CFBundleIdentifier": "io.github.ralphkrauss.myjournal.server",
        "CFBundleName": "Journal Server",
        "CFBundleExecutable": "Journal.Api",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": client["CFBundleShortVersionString"],
        "CFBundleVersion": client["CFBundleVersion"],
        "LSMinimumSystemVersion": "14.0",
        "LSBackgroundOnly": True,
    }, output)
PY
while IFS= read -r -d '' library; do
  codesign --force --sign "$identity" "$library"
done < <(find "$bundle/Contents/MacOS" -type f -name '*.dylib' -print0)
codesign --force --sign "$identity" --entitlements "$entitlements" "$bundle"
codesign --verify --deep --strict "$bundle"
