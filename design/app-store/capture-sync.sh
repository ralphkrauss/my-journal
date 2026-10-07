#!/bin/bash
# Captures frame 3 on the iPad and the iPhone (docs/app-store/screenshots-plan.md): a disposable local server set
# up by "MacBook Pro" with the sample library; the iPad joins, then approves the iPhone at the check code step, and
# the iPhone shows all three devices. The simulators are named "iPad" and "iPhone" for the capture (a restart
# applies a name) and renamed back afterwards.
# Usage: capture-sync.sh <ipad-simulator-id> <iphone-simulator-id> <ipad-output> <iphone-output>
set -euo pipefail
cd "$(dirname "$0")/../.."
ipad="${1:?Usage: capture-sync.sh <ipad-id> <iphone-id> <ipad-output> <iphone-output>}"
iphone="${2:?}"
ipad_output="${3:?}"
iphone_output="${4:?}"
work="$(mktemp -d -t journal-screenshot-sync)"
name_of() { xcrun simctl list devices -j | python3 -c '
import json, sys
for group in json.load(sys.stdin)["devices"].values():
    for device in group:
        if device["udid"] == sys.argv[1]:
            print(device["name"])
' "$1"; }
ipad_name="$(name_of "$ipad")"
iphone_name="$(name_of "$iphone")"
server_pid=""
cleanup() {
  local status=$?
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  if [[ $status -ne 0 && -f "$work/ipad.log" ]]; then grep -E "error:|Test Case" "$work/ipad.log" >&2 || true; fi
  xcrun simctl rename "$ipad" "$ipad_name" || true
  xcrun simctl rename "$iphone" "$iphone_name" || true
  rm -rf "$work"
}
trap cleanup EXIT
for pair in "$ipad:iPad" "$iphone:iPhone"; do
  xcrun simctl rename "${pair%%:*}" "${pair#*:}"
  xcrun simctl shutdown "${pair%%:*}" 2>/dev/null || true
  xcrun simctl boot "${pair%%:*}"
  xcrun simctl bootstatus "${pair%%:*}" -b >/dev/null
done
xcrun simctl spawn "$ipad" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
xcrun simctl spawn "$ipad" notifyutil -p com.apple.BiometricKit.enrollmentChanged
dotnet build server/src/Journal.Api -v quiet -p:RestoreLockedMode=true >/dev/null
# Created first, so the wait below can read it before the server opens it.
: >"$work/server.log"
Journal__DataDirectory="$work/server" ASPNETCORE_URLS="http://127.0.0.1:0" \
  dotnet server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll >"$work/server.log" 2>&1 &
server_pid=$!
address=""
for _ in {1..100}; do
  address="$(sed -n 's/.*Now listening on: \(http:\/\/127.0.0.1:[0-9]*\).*/\1/p' "$work/server.log" | head -1)"
  if [[ -n "$address" && -f "$work/server/setup-code" ]]; then break; fi
  sleep 0.1
done
[[ -n "$address" ]] || {
  cat "$work/server.log"
  exit 1
}
export TEST_RUNNER_JOURNAL_SCREENSHOT_SERVER="$address"
TEST_RUNNER_JOURNAL_SCREENSHOT_SETUP_CODE="$(cat "$work/server/setup-code")"
export TEST_RUNNER_JOURNAL_SCREENSHOT_SETUP_CODE
export TEST_RUNNER_JOURNAL_SCREENSHOT_SERVER_STATE="$work/approving-device.json"
# The library is uploaded to a new server, so it leaves out versions made on another device.
export JOURNAL_SCREENSHOT_HISTORY=0
scripts/generate-apple.sh apps/apple/screenshots.yml JournalScreenshots >/dev/null
xcodebuild -project apps/apple/JournalScreenshots.xcodeproj -scheme JournalScreenshots \
  -destination "platform=iOS Simulator,id=$ipad" -derivedDataPath "${JOURNAL_SCREENSHOT_DERIVED_DATA:-artifacts/DD-shots}" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- build-for-testing | grep -E "error:|BUILD" || true
export JOURNAL_SCREENSHOT_SKIP_BUILD=1
TEST_RUNNER_JOURNAL_SCREENSHOT_EMPTY_LIBRARY="$work/ipad" \
  design/app-store/capture-ios.sh "$ipad" "$ipad_output" test3Sync >"$work/ipad.log" 2>&1 &
ipad_run=$!
# The iPhone starts once the iPad has joined and waits for its pairing code.
for _ in {1..600}; do
  [[ ! -f "$work/ipad-ready" ]] || break
  kill -0 "$ipad_run" 2>/dev/null || break
  sleep 0.5
done
# Approve on the iPad asks for Face ID, which a test build doesn't answer for it: the iPad has Face ID enrolled, and
# once its run is about to approve, its face matches.
(
  for _ in {1..1200}; do
    if [[ -f "$work/ipad-approving" ]]; then
      for _ in 1 2 3; do
        sleep 2
        xcrun simctl spawn "$ipad" notifyutil -p com.apple.BiometricKit_Sim.pearl.match
      done
      break
    fi
    sleep 0.5
  done
) &
TEST_RUNNER_JOURNAL_SCREENSHOT_EMPTY_LIBRARY="$work/iphone" \
  design/app-store/capture-ios.sh "$iphone" "$iphone_output" test3Sync
wait "$ipad_run" || {
  cat "$work/ipad.log"
  exit 1
}
