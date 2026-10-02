#!/bin/bash
# Opt-in measurement of the iOS app's idle sync traffic (docs/design/sync-protocol-efficiency.md §7.4): the Release
# app on a simulator created for the run, a small library on a disposable loopback server, and the counting proxy
# (scripts/sync-fault-proxy.py) in front of it. Usage:
#   measure-idle-traffic.sh <new-output-directory> [server dll]
# The server defaults to the one built from this tree; pass an earlier build's Journal.Api.dll (such as a git
# worktree of build 9) to measure the same app against a server without waiting. JOURNAL_MEASURE_IDLE_SECONDS sets the
# idle period (600). The simulator is deleted afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Usage: measure-idle-traffic.sh <new-output-directory> [server dll]}"
[[ ! -e "$output" ]] || {
  echo "Choose a new output directory." >&2
  exit 2
}
mkdir -p "$output"
output="$(cd "$output" && pwd)"
server_dll="${2:-server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll}"
[[ -n "${2:-}" ]] || dotnet build server/src/Journal.Api -v quiet -p:RestoreLockedMode=true
server_pid=""
proxy_pid=""
simulator=""
cleanup() {
  for pid in "$proxy_pid" "$server_pid"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" 2>/dev/null || true
    xcrun simctl delete "$simulator" || true
  fi
  rm -rf "$output/server"
}
trap cleanup EXIT

Journal__DataDirectory="$output/server" ASPNETCORE_URLS="http://127.0.0.1:0" dotnet "$server_dll" >"$output/server.log" 2>&1 &
server_pid=$!
address=""
for _ in {1..100}; do
  address="$(sed -n 's/.*Now listening on: \(http:\/\/127.0.0.1:[0-9]*\).*/\1/p' "$output/server.log" | head -1)"
  [[ -z "$address" ]] || break
  sleep 0.1
done
[[ -n "$address" ]] || {
  cat "$output/server.log"
  exit 1
}
python3 -u scripts/sync-fault-proxy.py "$address" pass "$output/traffic.json" >"$output/proxy.log" 2>&1 &
proxy_pid=$!
for _ in {1..100}; do
  grep -q LISTENING "$output/proxy.log" && break
  sleep 0.1
done
proxy="$(sed -n 's/^LISTENING \(.*\)$/\1/p' "$output/proxy.log")"

runtime="$(xcrun simctl list runtimes --json | python3 -c 'import json,sys; print([r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]][-1])')"
simulator="$(xcrun simctl create "Sync Efficiency Measure iPhone 17" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$runtime")"
xcrun simctl boot "$simulator"

scripts/generate-apple.sh apps/apple/measurement.yml JournalMeasurements
xcodebuild -project apps/apple/JournalMeasurements.xcodeproj -derivedDataPath "${JOURNAL_MEASURE_DERIVED_DATA:-$output/build}" \
  -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO ENABLE_TESTABILITY=YES \
  "JOURNAL_MEASURE_SERVER=$proxy" "JOURNAL_MEASURE_SETUP_CODE=$(cat "$output/server/setup-code")" \
  "JOURNAL_MEASURE_IDLE_SECONDS=${JOURNAL_MEASURE_IDLE_SECONDS:-600}" \
  -scheme JournalIOSMeasured -destination "platform=iOS Simulator,id=$simulator" \
  -only-testing:JournalIOSMeasurements/IdleTrafficMeasurement CODE_SIGN_IDENTITY=- test | tee "$output/test.log" |
  grep -E "IdleTrafficMeasurement|JOURNAL-IDLE|error:" || true
grep -q "Test Case.*testIdleTraffic.*passed" "$output/test.log" || {
  echo "The measurement failed; see $output/test.log." >&2
  exit 1
}
python3 - "$output/traffic.json" <<'PY' | tee "$output/report.json"
import json, sys
events = json.load(open(sys.argv[1]))["events"]
marks = {name[5:]: when for when, name, _, _ in events if name.startswith("mark:")}
idle = [e for e in events if marks["start"] < e[0] < marks["end"] and not e[1].startswith("mark:")]
minutes = (marks["end"] - marks["start"]) / 60
kinds = {}
for _, name, up, down in idle:
    entry = kinds.setdefault(name, {"requests": 0, "up": 0, "down": 0})
    entry["requests"] += 1
    entry["up"] += up
    entry["down"] += down
total = sum(up + down for _, _, up, down in idle)
print(json.dumps({
    "idleMinutes": round(minutes, 2),
    "requestsPerMinute": round(len(idle) / minutes, 2),
    "httpBytesPerMinute": round(total / minutes),
    "httpBytesPerHour": round(total / minutes * 60),
    "byKind": kinds,
}, indent=1))
PY
