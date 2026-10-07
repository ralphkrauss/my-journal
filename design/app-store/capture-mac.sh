#!/bin/bash
# Captures the Mac windows for the App Store screenshots (docs/app-store/screenshots-plan.md). Seeds a fresh
# sample library inside the app's sandbox container and starts a disposable local server, then runs the opt-in
# JournalMacScreenshots test hosted in a team-signed build, which opens the library in the app's own windows and
# renders them. For frame 4 the test sets up the server as "MacBook Pro" and connects "Writing Assistant" to it; the
# server names itself with the public address https://journal.example.net, which Agent Access shows, and frame 3
# shows Settings > Sync connected to it under that address. Writes the PNG captures to <output>. The owner's own
# library is never opened.
# Usage: capture-mac.sh <new-output-directory>
set -euo pipefail
cd "$(dirname "$0")/../.."
output="${1:?Usage: capture-mac.sh <output-directory>}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
public_url="https://journal.example.net"
# The sandboxed test host can only write inside its own container.
work="$HOME/Library/Containers/io.github.ralphkrauss.myjournal/Data/tmp/journal-screenshots"
rm -rf "$work"
mkdir -p "$work"
server_pid=""
cleanup() {
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  # Also after a failure, so the frames captured until then and failed-* show what happened.
  # Files the app wrote in its container can take a moment to show to this process.
  for _ in {1..20}; do
    if compgen -G "$work/captures/*.png" >/dev/null; then
      cp "$work/captures/"* "$output/"
      break
    fi
    sleep 0.5
  done
  rm -rf "$work"
}
trap cleanup EXIT
# The library is uploaded to a new server, so it leaves out versions made on another device.
JOURNAL_SCREENSHOT_HISTORY=0 design/app-store/seed-library.sh "$work/library" >/dev/null
dotnet build server/src/Journal.Api -v quiet -p:RestoreLockedMode=true >/dev/null
# Created first, so the wait below can read it before the server opens it.
: >"$work/server.log"
# The agent's requests name the public host on the loopback address, so the server accepts that host too.
Journal__DataDirectory="$work/server" Journal__PublicUrl="$public_url" ASPNETCORE_URLS="http://127.0.0.1:0" \
  AllowedHosts="localhost;127.0.0.1;[::1];${public_url#https://}" \
  dotnet server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll >"$work/server.log" 2>&1 &
server_pid=$!
address=""
for _ in {1..100}; do
  address="$(sed -n 's/.*Now listening on: \(http:\/\/127.0.0.1:[0-9]*\).*/\1/p' "$work/server.log" | head -1)"
  if [[ -n "$address" && -f "$work/server/setup-code" ]]; then break; fi
  sleep 0.1
done
[[ -n "$address" && -f "$work/server/setup-code" ]] || {
  cat "$work/server.log"
  exit 1
}
scripts/generate-apple.sh apps/apple/screenshots.yml JournalScreenshots >/dev/null
TEST_RUNNER_JOURNAL_DATA_DIR="$work/library" \
  TEST_RUNNER_JOURNAL_SCREENSHOT_PASSWORD_FILE="$PWD/design/app-store/.seed-password" \
  TEST_RUNNER_JOURNAL_SCREENSHOT_OUTPUT="$work/captures" \
  TEST_RUNNER_JOURNAL_SCREENSHOT_SERVER="$address" \
  TEST_RUNNER_JOURNAL_SCREENSHOT_SETUP_CODE="$(cat "$work/server/setup-code")" \
  TEST_RUNNER_JOURNAL_SCREENSHOT_PUBLIC_URL="$public_url" \
  xcodebuild -project apps/apple/JournalScreenshots.xcodeproj -scheme JournalMacScreenshots \
  -destination 'platform=macOS' -derivedDataPath "${JOURNAL_SCREENSHOT_DERIVED_DATA:-artifacts/DD-shots}" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=${JOURNAL_SIGNING_IDENTITY:?Set JOURNAL_SIGNING_IDENTITY to your Apple Development identity}" test
printf 'Captures: %s\n' "$output"
