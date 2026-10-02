#!/bin/bash
# Builds the Mac App Store archive: the universal Release app with the bundled
# server in Contents/Helpers. It needs no signing credentials. Every executable is signed to run locally, which
# records its entitlements; the export signs each one again with the distribution identity and profile and keeps
# them (upload-app-store.sh, or Distribute App in Xcode's Organizer). Archiving from Xcode would leave out the server.
# JOURNAL_SIGNING_TEAM is the team ID that prefixes the app group and the keychain group. JOURNAL_BUILD_NUMBER sets the
# build number (CFBundleVersion) and JOURNAL_VERSION the version the bundled server reports. JOURNAL_SIGNING_IDENTITY
# (for example an Apple Development identity) signs the archive for the team, which Xcode's Organizer needs to
# distribute it; without it every executable is signed ad hoc, as in CI.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Usage: archive-mac.sh <new-output-directory>}"
team="${JOURNAL_SIGNING_TEAM:-}"
build_number="${JOURNAL_BUILD_NUMBER:-}"
identity="${JOURNAL_SIGNING_IDENTITY:--}"
[[ ! -e "$output" ]] || {
  echo "Output already exists; choose a new directory." >&2
  exit 2
}
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || {
  echo "Set JOURNAL_SIGNING_TEAM to the 10-character team ID." >&2
  exit 2
}
[[ -z "$build_number" || "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
  echo "JOURNAL_BUILD_NUMBER must be one to three period-separated integers." >&2
  exit 2
}
settings=(DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity")
if [[ -n "$build_number" ]]; then
  settings+=("CURRENT_PROJECT_VERSION=$build_number")
fi
mkdir -p "$output"
output="$(cd "$output" && pwd)"
scripts/generate-apple.sh
xcodebuild -project apps/apple/Journal.xcodeproj -scheme 'My Journal (Mac)' -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$output/My Journal.xcarchive" \
  -derivedDataPath "$output/build" -onlyUsePackageVersionsFromResolvedFile "${settings[@]}" archive
app="$output/My Journal.xcarchive/Products/Applications/My Journal.app"
if [[ -n "$build_number" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" != "$build_number" ]]; then
  echo "The archived app does not carry build number $build_number." >&2
  exit 1
fi
# Package resource bundles (GRDB's privacy manifest) hold no code, so the app's signature seals them. A signature of
# their own would keep the archive's identity through export, which App Store Connect rejects (ITMS-90284).
while IFS= read -r -d '' bundle; do
  [[ -d "$bundle/Contents/MacOS" ]] || codesign --remove-signature "$bundle"
done < <(find "$app/Contents/Resources" -maxdepth 1 -type d -name '*.bundle' -print0)
# Xcode signs without a profile only without restricted entitlements, so the app gets the keychain group that
# team-signed builds share here; the App Store profile authorizes it at export.
sed "s/\$(TeamIdentifierPrefix)/$team./; s/\$(AppIdentifierPrefix)/$team./" \
  apps/apple/Signing/JournalMac-Development.entitlements >"$output/Journal.entitlements"
codesign --force --sign "$identity" --preserve-metadata=identifier,requirements,flags,runtime \
  --entitlements "$output/Journal.entitlements" "$app"
rm "$output/Journal.entitlements"
# Apple silicon only until the owner decides how Intel Macs get the server (docs/design/mac-app-store-sandbox.md).
scripts/package-server.sh osx-arm64 "$output/server"
scripts/embed-mac-server.sh "$app" "$output/server"
rm -rf "$output/server"
# Symbols for the embedded server's native code, so the upload finds a dSYM for every binary it contains.
server_code="$app/Contents/Helpers/JournalServer.app/Contents/MacOS"
for binary in "$server_code/Journal.Api" "$server_code/libe_sqlite3.dylib"; do
  dsymutil "$binary" -o "$output/My Journal.xcarchive/dSYMs/$(basename "$binary").dSYM"
done
# The App Store refuses an executable outside the sandbox, and the export keeps the entitlements recorded here.
check_entitlements() {
  codesign -d --entitlements - --xml "$1" 2>/dev/null | python3 -c '
import plistlib
import sys
code, team, *required = sys.argv[1:]
claimed = {key: value for key, value in plistlib.loads(sys.stdin.buffer.read()).items() if value}
group = claimed.get("com.apple.security.application-groups", [f"{team}.io.github.ralphkrauss.myjournal"])
keychain = claimed.get("keychain-access-groups", [f"{team}.org.privatejournal.vault"])
expected = ([f"{team}.io.github.ralphkrauss.myjournal"], [f"{team}.org.privatejournal.vault"])
if not set(required) <= set(claimed) or (group, keychain) != expected:
    raise SystemExit(code + " has unexpected entitlements: " + " ".join(sorted(claimed)))
if code.endswith("JournalServer.app") and set(claimed) != set(required):
    raise SystemExit("The server must only inherit the app sandbox.")
' "$1" "$team" "${@:2}"
}
check_entitlements "$app/Contents/Helpers/JournalServer.app" com.apple.security.app-sandbox com.apple.security.inherit
check_entitlements "$app" com.apple.security.app-sandbox com.apple.security.application-groups keychain-access-groups
printf 'Mac App Store archive, pending signing at export: %s\n' "$output/My Journal.xcarchive"
