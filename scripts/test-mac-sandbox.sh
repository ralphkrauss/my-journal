#!/bin/bash
# Separate native lane for the Mac App Store configuration: a sandboxed, team-signed test host with the bundled
# server. Requires Xcode signed in
# to the team's Apple Account (see build-mac-development.sh). JOURNAL_TEST_RESULTS keeps the result bundle in a
# chosen new directory.
set -euo pipefail
cd "$(dirname "$0")/.."
team="${1:?Usage: test-mac-sandbox.sh <team-id>}"
work="$(mktemp -d "${TMPDIR:-/tmp}/journal-mac-sandbox.XXXXXXXXXX")"
results="${JOURNAL_TEST_RESULTS:-$work}"
mkdir -p "$results"
results="$(cd "$results" && pwd)"
[[ ! -e "$results/MacSandbox.xcresult" ]] || {
  echo "Choose a new JOURNAL_TEST_RESULTS directory." >&2
  exit 2
}
case "$(uname -m)" in
  arm64) runtime=osx-arm64 ;;
  x86_64) runtime=osx-x64 ;;
  *)
    echo "Run this check on macOS." >&2
    exit 2
    ;;
esac
# The published server (over 100 MB) is only needed until it is embedded.
trap 'rm -rf "$work/server"' EXIT
scripts/package-server.sh "$runtime" "$work/server"
scripts/generate-apple.sh
derived=artifacts/DerivedDataMacSandbox
xcode=(xcodebuild -jobs 2 -project apps/apple/Journal.xcodeproj -scheme JournalMacSandbox -destination 'platform=macOS'
  -derivedDataPath "$derived" -onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic
  JOURNAL_MAC_ENTITLEMENTS=Signing/JournalMac-Development.entitlements)
"${xcode[@]}" build-for-testing
app="$PWD/$derived/Build/Products/Debug/My Journal.app"
identity="$(codesign -d --verbose=2 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
# Building for testing gives every sandboxed target XCTest's exceptions, including read access to every file,
# which would hide reads the sandbox refuses. Keep only the test host's exception XCTest needs to reach its runner.
resign_without() {
  local code="$1"
  shift
  local entitlements
  entitlements="$work/$(basename "$code").entitlements"
  codesign -d --entitlements - --xml "$code" >"$entitlements"
  for exception in "$@"; do
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.temporary-exception.$exception" "$entitlements"
  done
  codesign --force --sign "$identity" --preserve-metadata=identifier,requirements,flags,runtime \
    --entitlements "$entitlements" "$code"
}
scripts/embed-mac-server.sh "$app" "$work/server"
resign_without "$app" files.absolute-path.read-only
codesign --verify --deep --strict "$app"
"${xcode[@]}" -resultBundlePath "$results/MacSandbox.xcresult" \
  JOURNAL_LOCAL_SERVER_EXECUTABLE="$app/Contents/Helpers/JournalServer.app/Contents/MacOS/Journal.Api" \
  test-without-building
python3 scripts/verify-test-results.py "$results/MacSandbox.xcresult"
printf 'Mac sandbox results: %s\n' "$results/MacSandbox.xcresult"
