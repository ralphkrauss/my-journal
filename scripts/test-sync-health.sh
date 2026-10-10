#!/bin/bash
# The sync health fault matrix (docs/design/sync-health-and-recovery.md §6.1): the published server on a fixed
# loopback port, so a reset or restore keeps the address the devices know, driven by JournalProbe's health phases.
# JOURNAL_SERVER_PACKAGE reuses a server already produced by scripts/package-server.sh; JOURNAL_TEST_RESULTS keeps
# the server logs.
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir="$(mktemp -d)"
server_pid=""
data=""
stop_server() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
cleanup() {
  stop_server
  local pid
  for pid in ${helper_pids[@]+"${helper_pids[@]}"}; do kill "$pid" 2>/dev/null || true; done
  if [[ -n "${JOURNAL_TEST_RESULTS:-}" ]]; then
    mkdir -p "$JOURNAL_TEST_RESULTS" || true
    find "$task_dir" -maxdepth 1 -name 'server-*.log' -exec cp {} "$JOURNAL_TEST_RESULTS/" \; || true
  fi
  rm -rf "$task_dir"
}
trap cleanup EXIT

package="${JOURNAL_SERVER_PACKAGE:-}"
if [[ -z "$package" ]]; then
  package="$task_dir/package"
  scripts/package-server.sh osx-arm64 "$package" >/dev/null
fi
# Three free ports between 18950 and 18959: the server, a server with a self-signed certificate, and another web
# server.
ports=()
for candidate in {18950..18959}; do
  if ! nc -z 127.0.0.1 "$candidate" 2>/dev/null; then ports+=("$candidate"); fi
  [[ ${#ports[@]} -lt 3 ]] || break
done
[[ ${#ports[@]} -eq 3 ]] || {
  echo "Not enough free ports between 18950 and 18959." >&2
  exit 1
}
port="${ports[0]}"
address="http://127.0.0.1:$port"
helper_pids=()

# Starts the server for a data folder at the fixed address.
start_server() {
  data="$1"
  local log="$task_dir/server-$RANDOM.log"
  Journal__DataDirectory="$data" ASPNETCORE_URLS="$address" "$package/Journal.Api" >"$log" 2>&1 &
  server_pid=$!
  for _ in {1..150}; do
    if curl -fsS "$address/v1/status" >/dev/null 2>&1; then return 0; fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat "$log"
      exit 1
    fi
    sleep 0.1
  done
  cat "$log"
  exit 1
}
# Stops the server and wipes its data folder, as resetting a server does, then starts it again at the same address.
reset_server() {
  stop_server
  rm -rf "$data"
  start_server "$data"
}
# The flags of scripts/check.sh core, so both share one build of JournalCore instead of rebuilding it in turn.
probe() {
  swift run --jobs 2 --package-path apps/apple/Packages/JournalCore --force-resolved-versions \
    -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors JournalProbe "$@"
}

state="$task_dir/state"
start_server "$task_dir/server"
probe health-setup "$address" "$data/setup-code" "$state"
stop_server
probe health-offline "$address" "$state"
start_server "$data"
probe health-online "$address" "$state"
probe health-revoke "$address" "$state"
probe health-stop-syncing "$address" "$state"
Journal__DataDirectory="$data" "$package/Journal.Api" --backup "$task_dir/backup" >/dev/null
probe health-after-backup "$address" "$state"
stop_server
"$package/Journal.Api" --restore "$task_dir/backup" "--Journal:DataDirectory=$task_dir/restored" >/dev/null
start_server "$task_dir/restored"
probe health-restored "$address" "$state"
reset_server
probe health-reset "$address" "$data/setup-code" "$state"
probe health-stop-before-reset "$address" "$state"
reset_server
probe health-stop-reset "$address" "$data/setup-code" "$state"
reset_server
probe health-replaced "$address" "$data/setup-code" "$state"
# Single cases: the password changed elsewhere, a credential not accepted, rate limiting, damaged data on this device
# and an entry too large to sync.
reset_server
JOURNAL_TEST_RECOVERY_VERSION=2 probe health-cases "$address" "$data/setup-code" "$task_dir/cases-state"
stop_server

# Cases 4 to 6: a certificate that isn't valid, an address that doesn't resolve, and another web server.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=127.0.0.1" -keyout "$task_dir/key.pem" \
  -out "$task_dir/cert.pem" >/dev/null 2>&1
openssl s_server -quiet -accept "${ports[1]}" -cert "$task_dir/cert.pem" -key "$task_dir/key.pem" -www \
  >/dev/null 2>&1 &
helper_pids+=($!)
mkdir -p "$task_dir/other-web"
python3 -m http.server "${ports[2]}" --bind 127.0.0.1 --directory "$task_dir/other-web" >/dev/null 2>&1 &
helper_pids+=($!)
for helper_port in "${ports[1]}" "${ports[2]}"; do
  for _ in {1..100}; do
    if nc -z 127.0.0.1 "$helper_port" 2>/dev/null; then break; fi
    sleep 0.1
  done
done
probe health-addresses "https://127.0.0.1:${ports[1]}" "http://127.0.0.1:${ports[2]}"
echo "PASS: sync health fault matrix"
