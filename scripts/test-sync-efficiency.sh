#!/bin/bash
# Short push receipts and waiting for changes against disposable loopback servers
# (docs/design/sync-protocol-efficiency.md §7.3): real-server checks, faults injected by scripts/sync-fault-proxy.py,
# many waiting devices, and, with JOURNAL_BASELINE_DIR set to a checkout of an earlier build (for example a git
# worktree of build 9), mixed versions both ways. JOURNAL_TEST_RESULTS keeps the servers' logs.
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir="$(mktemp -d)"
server_pid=""
proxy_pid=""
address=""
stop_server() {
  for pid in "$proxy_pid" "$server_pid"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  server_pid=""
  proxy_pid=""
}
cleanup() {
  stop_server
  if [[ -n "${JOURNAL_TEST_RESULTS:-}" ]]; then
    mkdir -p "$JOURNAL_TEST_RESULTS" || true
    find "$task_dir" -maxdepth 1 -name '*.log' -exec cp {} "$JOURNAL_TEST_RESULTS/" \; || true
  fi
  rm -rf "$task_dir"
}
trap cleanup EXIT
# Starts the server built at $1 for data directory $2 on a free loopback port and sets $address.
start_server() {
  local dll="$1" data="$2" log
  log="$task_dir/server-$RANDOM.log"
  Journal__DataDirectory="$data" ASPNETCORE_URLS="http://127.0.0.1:0" dotnet "$dll" >"$log" 2>&1 &
  server_pid=$!
  address=""
  for _ in {1..100}; do
    address="$(sed -n 's/.*Now listening on: \(http:\/\/127.0.0.1:[0-9]*\).*/\1/p' "$log" | head -1)"
    if [[ -n "$address" ]]; then return 0; fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat "$log"
      exit 1
    fi
    sleep 0.1
  done
  cat "$log"
  exit 1
}
# Puts scripts/sync-fault-proxy.py in mode $1 in front of $address and sets $address to the proxy.
start_proxy() {
  local log="$task_dir/proxy-$1.log"
  python3 -u scripts/sync-fault-proxy.py "$address" "$1" "$task_dir/proxy-$1.json" >"$log" 2>&1 &
  proxy_pid=$!
  for _ in {1..100}; do
    if grep -q LISTENING "$log"; then
      address="$(sed -n 's/^LISTENING \(.*\)$/\1/p' "$log")"
      return 0
    fi
    sleep 0.1
  done
  cat "$log"
  exit 1
}
probe_at() {
  swift run --jobs 2 --package-path "$1/apps/apple/Packages/JournalCore" --force-resolved-versions JournalProbe "${@:2}"
}
probe() { probe_at . "$@"; }

server_dll=server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll
dotnet build server/src/Journal.Api -v quiet -p:RestoreLockedMode=true

start_server "$server_dll" "$task_dir/wait-server"
probe wait "$address" "$task_dir/wait-server/setup-code"
stop_server

for mode in cut halfopen reset buffer instant-true cached-false drop-push; do
  start_server "$server_dll" "$task_dir/fault-$mode"
  code="$task_dir/fault-$mode/setup-code"
  start_proxy "$mode"
  probe wait-fault "$address" "$code" "$mode"
  stop_server
done

# Many devices: the server's memory is sampled while they wait and one device writes.
start_server "$server_dll" "$task_dir/many-server"
(
  peak=0
  while kill -0 "$server_pid" 2>/dev/null; do
    rss="$(ps -o rss= -p "$server_pid" | tr -d ' ' || true)"
    if [[ -n "$rss" && "$rss" -gt "$peak" ]]; then
      peak="$rss"
      echo "$peak" >"$task_dir/many-peak-rss"
    fi
    sleep 1
  done
) &
probe wait-many "$address" "$task_dir/many-server/setup-code" "${JOURNAL_WAITING_DEVICES:-20}"
echo "Server peak resident memory with waiting devices: $(($(cat "$task_dir/many-peak-rss") / 1024)) MiB"
stop_server

if [[ -n "${JOURNAL_BASELINE_DIR:-}" ]]; then
  baseline_dll="$JOURNAL_BASELINE_DIR/server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll"
  dotnet build "$JOURNAL_BASELINE_DIR/server/src/Journal.Api" -v quiet -p:RestoreLockedMode=true
  # A new client with the earlier server: nothing new is asked for, and everything still synchronizes.
  start_server "$baseline_dll" "$task_dir/old-server"
  probe wait-old "$address" "$task_dir/old-server/setup-code"
  stop_server
  start_server "$baseline_dll" "$task_dir/old-server-main"
  probe "$address" "$task_dir/old-server-main/setup-code"
  stop_server
  # The earlier client with the new server: its full receipts and polling still work.
  start_server "$server_dll" "$task_dir/new-server-old-client"
  probe_at "$JOURNAL_BASELINE_DIR" "$address" "$task_dir/new-server-old-client/setup-code"
  stop_server
  start_server "$server_dll" "$task_dir/new-server-old-merge"
  probe_at "$JOURNAL_BASELINE_DIR" merge "$address" "$task_dir/new-server-old-merge/setup-code"
  stop_server
  echo "PASS: mixed versions synchronize both ways"
fi
