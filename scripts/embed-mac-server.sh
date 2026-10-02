#!/bin/bash
# Embeds a published self-contained server (package-server.sh osx-arm64 or osx-x64) in a built My Journal.app, then
# signs the app again with its own entitlements and provisioning profile. The server and the app use the app's
# signing identity; an ad-hoc signed app (a test build) gets an ad-hoc signed server.
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Usage: embed-mac-server.sh <My Journal.app> <published-server-directory>}"
server="${2:?Provide the directory package-server.sh published}"
[[ -d "$app/Contents/MacOS" && -x "$server/Journal.Api" ]] || {
  echo "Provide a built My Journal.app and a published Mac server." >&2
  exit 2
}
signature="$(codesign -d --verbose=2 "$app" 2>&1)"
identity="$(sed -n 's/^Authority=//p' <<<"$signature" | head -n 1)"
[[ -n "$identity" ]] || identity=-
helper="$app/Contents/Helpers/JournalServer.app"
# The previous copy is a build product of this script, never source.
rm -rf "$helper"
mkdir -p "$app/Contents/Helpers"
scripts/assemble-mac-server.sh "$server" "$helper" "$app/Contents/Info.plist" "$identity"
codesign --force --sign "$identity" --preserve-metadata=identifier,entitlements,requirements,flags,runtime "$app"
codesign --verify --deep --strict "$app"
printf 'Embedded the server in %s (signed by %s)\n' "$app" "$identity"
