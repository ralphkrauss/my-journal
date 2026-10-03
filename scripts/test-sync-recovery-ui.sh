#!/bin/bash
# Runs SyncRecoveryUITests (docs/design/sync-health-and-recovery.md) against the published server on a fixed loopback
# port, resetting and stopping it when the test asks. JOURNAL_SIMULATOR_ID selects the simulator (see
# prepare-simulator.sh); JOURNAL_SERVER_PACKAGE reuses a server from scripts/package-server.sh; JOURNAL_TEST_RESULTS
# keeps the result bundle; JOURNAL_ONLY_TESTING narrows the run to one test; JOURNAL_CONFIGURATION is Release unless set (with testability, so the scheme's unit test
# target builds too).
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir="$(mktemp -d)"
results="${JOURNAL_TEST_RESULTS:-$task_dir/results}"
mkdir -p "$results"
results="$(cd "$results" && pwd)"
[[ ! -e "$results/SyncRecovery.xcresult" ]] || {
  echo "Choose a new JOURNAL_TEST_RESULTS directory." >&2
  exit 2
}
simulator_id="$(scripts/prepare-simulator.sh)"
bundle=io.github.ralphkrauss.myjournal
controller_pid=""
# The server is restarted by the request handler in a subshell, so its process is tracked in a file.
server_pid_file="$task_dir/server.pid"
stop_server() {
  if [[ -f "$server_pid_file" ]]; then
    local pid
    pid="$(cat "$server_pid_file")"
    kill "$pid" 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
    rm -f "$server_pid_file"
  fi
}
cleanup() {
  [[ -z "$controller_pid" ]] || kill "$controller_pid" 2>/dev/null || true
  stop_server
  if [[ -n "${JOURNAL_TEST_RESULTS:-}" ]]; then
    rm -rf "$task_dir"
  else
    rm -rf "$task_dir/data" "$task_dir/control" "$task_dir/package" "$task_dir/defaults.plist" "$task_dir/backup" \
      "$task_dir/impostor"
  fi
}
trap cleanup EXIT

package="${JOURNAL_SERVER_PACKAGE:-}"
if [[ -z "$package" ]]; then
  package="$task_dir/package"
  scripts/package-server.sh osx-arm64 "$package" >/dev/null
fi
port=""
for candidate in {18950..18959}; do
  if ! nc -z 127.0.0.1 "$candidate" 2>/dev/null; then
    port="$candidate"
    break
  fi
done
[[ -n "$port" ]] || {
  echo "No free port between 18950 and 18959." >&2
  exit 1
}
address="http://127.0.0.1:$port"
data="$task_dir/data"
control="$task_dir/control"
mkdir -p "$control"

# Starts the server at the fixed address and hands a new server's setup code to the test.
start_server() {
  Journal__DataDirectory="$data" ASPNETCORE_URLS="$address" "$package/Journal.Api" >>"$results/server.log" 2>&1 &
  echo $! >"$server_pid_file"
  for _ in {1..150}; do
    if curl -fsS "$address/v1/status" 2>/dev/null | grep -q '"protocolVersion"'; then
      [[ ! -f "$data/setup-code" ]] || cp "$data/setup-code" "$control/setup-code"
      return 0
    fi
    sleep 0.1
  done
  cat "$results/server.log" >&2
  exit 1
}
# Another web server at the same address, which answers 404 for everything a journal server serves.
start_impostor() {
  mkdir -p "$task_dir/impostor"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$task_dir/impostor" >>"$results/impostor.log" 2>&1 &
  echo $! >"$server_pid_file"
  for _ in {1..100}; do
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
  exit 1
}
# Moves the last successful sync two days back, as if changes had waited that long. The app's preferences live in
# its container, which the simulator's defaults reach by path.
age_last_sync() {
  local container exported="$task_dir/defaults.plist"
  container="$(xcrun simctl get_app_container "$simulator_id" "$bundle" data)"
  local domain="$container/Library/Preferences/$bundle"
  xcrun simctl spawn "$simulator_id" defaults export "$domain" "$exported"
  python3 - "$exported" <<'PY'
import datetime
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as file:
    values = plistlib.load(file)
aged = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=2)
for key, value in values.items():
    if key.startswith("lastSynced-") and isinstance(value, dict):
        value["date"] = aged.replace(tzinfo=None)
with open(path, "wb") as file:
    plistlib.dump(values, file)
PY
  xcrun simctl spawn "$simulator_id" defaults import "$domain" "$exported"
}
# Answers the test's requests while it runs.
serve_requests() {
  while true; do
    if [[ -f "$control/request" ]]; then
      local command
      command="$(cat "$control/request")"
      rm -f "$control/request"
      case "$command" in
        reset)
          stop_server
          rm -rf "$data"
          start_server
          ;;
        stop-and-age)
          stop_server
          age_last_sync
          ;;
        start | genuine)
          stop_server
          start_server
          ;;
        backup)
          rm -rf "$task_dir/backup"
          Journal__DataDirectory="$data" "$package/Journal.Api" --backup "$task_dir/backup" >>"$results/server.log"
          ;;
        restore)
          stop_server
          rm -rf "$data"
          "$package/Journal.Api" --restore "$task_dir/backup" "--Journal:DataDirectory=$data" >>"$results/server.log"
          start_server
          ;;
        impostor)
          stop_server
          start_impostor
          ;;
        recovery-code)
          Journal__DataDirectory="$data" "$package/Journal.Api" --recovery-code | tail -1 >"$control/recovery-code"
          ;;
      esac
      touch "$control/done-$command"
    fi
    sleep 0.2
  done
}

start_server
serve_requests &
controller_pid=$!
scripts/generate-apple.sh
xcodebuild -project apps/apple/Journal.xcodeproj -scheme 'My Journal (iOS)' \
  -configuration "${JOURNAL_CONFIGURATION:-Release}" \
  -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO \
  -derivedDataPath artifacts/DerivedData -resultBundlePath "$results/SyncRecovery.xcresult" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 600 \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- ENABLE_TESTABILITY=YES \
  JOURNAL_TEST_HEALTH_SERVER="$address" JOURNAL_TEST_HEALTH_CONTROL="$control" \
  "-only-testing:${JOURNAL_ONLY_TESTING:-JournalIOSUITests/SyncRecoveryUITests}" test
python3 scripts/verify-test-results.py "$results/SyncRecovery.xcresult" \
  "-only-testing:${JOURNAL_ONLY_TESTING:-JournalIOSUITests/SyncRecoveryUITests}"
