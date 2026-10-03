#!/bin/bash
# Runs the iOS test scheme against a disposable server. JOURNAL_TEST_RESULTS keeps the result bundle and server log
# in a chosen new directory; JOURNAL_SIMULATOR_ID selects the simulator (see prepare-simulator.sh);
# JOURNAL_DERIVED_DATA builds somewhere other than artifacts/DerivedData.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_dir="$(mktemp -d -t journal-ui-pairing)"
results="${JOURNAL_TEST_RESULTS:-$fixture_dir}"
mkdir -p "$results"
results="$(cd "$results" && pwd)"
[[ ! -e "$results/Pairing.xcresult" ]] || {
  echo "Choose a new JOURNAL_TEST_RESULTS directory." >&2
  exit 2
}
simulator_id="$(scripts/prepare-simulator.sh)"
# Tests of iPad-only features skip themselves elsewhere, and a skipped test fails the results check, so an iPhone
# run leaves them out.
ipad_only=()
if ! xcrun simctl list devices -j | python3 -c '
import json
import sys
devices = json.load(sys.stdin)["devices"].values()
sys.exit(0 if any(d["udid"] == sys.argv[1] and "iPad" in d.get("deviceTypeIdentifier", "") for group in devices for d in group) else 1)
' "$simulator_id"; then
  ipad_only=(
    -skip-testing:JournalIOSUITests/PreReleaseUITests/testSearchEntriesAndFindAndReplaceShortcutsOnIPad
    -skip-testing:JournalIOSUITests/IPadWritingUITests/testEntryRowBesideTheWritingControlsOpens
  )
fi
# The sync recovery journeys need servers they reset, restore and replace, so they run in
# scripts/test-sync-recovery-ui.sh and skip themselves here.
own_lane=(-skip-testing:JournalIOSUITests/SyncRecoveryUITests)
server_pids=()
# Stops the servers and removes their disposable data; the results, which may share the folder, stay.
stop_servers() {
  local pid
  for pid in ${server_pids[@]+"${server_pids[@]}"}; do kill "$pid" 2>/dev/null || true; done
  local tries
  for pid in ${server_pids[@]+"${server_pids[@]}"}; do
    tries=100
    while kill -0 "$pid" 2>/dev/null && ((tries-- > 0)); do sleep 0.1; done
  done
  rm -rf "$fixture_dir/server" "$fixture_dir/encrypted-setup" "$fixture_dir/plain-setup" "$fixture_dir/agent" \
    "$fixture_dir/merge"
  if [[ "$results" != "$fixture_dir" ]]; then rmdir "$fixture_dir" 2>/dev/null || true; fi
}
trap stop_servers EXIT
dotnet build server/src/Journal.Api -v quiet -p:RestoreLockedMode=true
# Starts a disposable server that isn't set up, leaving its address and setup code in started_address and
# started_code. It runs in this shell, so the exit trap stops it.
start_server() {
  local name="$1" address=""
  Journal__DataDirectory="$fixture_dir/$name" ASPNETCORE_URLS="http://127.0.0.1:0" dotnet server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll >"$results/$name.log" 2>&1 &
  server_pids+=($!)
  for _ in {1..100}; do
    address="$(sed -n 's/.*Now listening on: \(http:\/\/127.0.0.1:[0-9]*\).*/\1/p' "$results/$name.log" | head -1)"
    if [[ -n "$address" && -f "$fixture_dir/$name/setup-code" ]]; then break; fi
    sleep 0.1
  done
  [[ -n "$address" && -f "$fixture_dir/$name/setup-code" ]] || {
    cat "$results/$name.log" >&2
    exit 1
  }
  started_address="$address"
  started_code="$(cat "$fixture_dir/$name/setup-code")"
}
# The pairing test sets its server up itself; the setup tests set theirs up through the app, with and without
# encryption; the agent access test sets up its own and plays the MCP client against it.
start_server server
address="$started_address" setup_code="$started_code"
start_server encrypted-setup
encrypted_address="$started_address" encrypted_code="$started_code"
start_server plain-setup
plain_address="$started_address" plain_code="$started_code"
start_server agent
agent_address="$started_address" agent_code="$started_code"
# The merge test sets its server up as a connected device, then merges a device's own journals into it.
start_server merge
merge_address="$started_address" merge_code="$started_code"
scripts/generate-apple.sh
# Debug, explicitly: the tests reach these servers and the fake ones over loopback HTTP, which only Debug builds
# accept (PairingInvite.origin); a Release build refuses them by design.
# A test that hangs, such as on a system prompt nobody can answer, fails after five minutes instead of an hour.
xcodebuild -project apps/apple/Journal.xcodeproj -scheme 'My Journal (iOS)' -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "${JOURNAL_DERIVED_DATA:-artifacts/DerivedData}" \
  -resultBundlePath "$results/Pairing.xcresult" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- JOURNAL_TEST_SERVER="$address" JOURNAL_TEST_SETUP_CODE="$setup_code" \
  JOURNAL_TEST_ENCRYPTED_SETUP_SERVER="$encrypted_address" JOURNAL_TEST_ENCRYPTED_SETUP_CODE="$encrypted_code" \
  JOURNAL_TEST_PLAIN_SETUP_SERVER="$plain_address" JOURNAL_TEST_PLAIN_SETUP_CODE="$plain_code" \
  JOURNAL_TEST_AGENT_SERVER="$agent_address" JOURNAL_TEST_AGENT_CODE="$agent_code" \
  JOURNAL_TEST_MERGE_SERVER="$merge_address" JOURNAL_TEST_MERGE_CODE="$merge_code" \
  ${ipad_only[@]+"${ipad_only[@]}"} "${own_lane[@]}" "$@" test
python3 scripts/verify-test-results.py "$results/Pairing.xcresult" "$@"
printf 'Pairing evidence: %s\n' "$results/Pairing.xcresult"
