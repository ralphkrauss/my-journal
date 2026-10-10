#!/bin/bash
# JOURNAL_TEST_RESULTS keeps the disposable servers' logs in a chosen directory for diagnosis.
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir="$(mktemp -d)"
server_pid=""
address=""
stop_server() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
cleanup() {
  stop_server
  if [[ -n "${JOURNAL_TEST_RESULTS:-}" ]]; then
    mkdir -p "$JOURNAL_TEST_RESULTS" || true
    find "$task_dir" -maxdepth 1 -name 'server-*.log' -exec cp {} "$JOURNAL_TEST_RESULTS/" \; || true
  fi
  rm -rf "$task_dir"
}
trap cleanup EXIT
server_dll=server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll
# Starts a server on a free loopback port for the given data directory and sets $address.
start_server() {
  local data="$1" log="$task_dir/server-$RANDOM.log"
  Journal__DataDirectory="$data" ASPNETCORE_URLS="http://127.0.0.1:0" dotnet "$server_dll" >"$log" 2>&1 &
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
# The flags of scripts/check.sh core, so both share one build of JournalCore instead of rebuilding it in turn.
probe() {
  swift run --jobs 2 --package-path apps/apple/Packages/JournalCore --force-resolved-versions \
    -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors JournalProbe "$@"
}
dotnet build server/src/Journal.Api -v quiet -p:RestoreLockedMode=true
start_server "$task_dir/server"
probe "$address" "$task_dir/server/setup-code"
Journal__DataDirectory="$task_dir/server" dotnet "$server_dll" --backup "$task_dir/backup"
Journal__DataDirectory="$task_dir/restored" dotnet "$server_dll" --restore "$task_dir/backup"
python3 - "$task_dir/backup/journal.db" "$task_dir/restored/journal.db" <<'PY'
import sqlite3, sys
for path in sys.argv[1:]:
    db = sqlite3.connect(path)
    assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    assert db.execute('SELECT count(*) FROM Records').fetchone()[0] == 3
    assert db.execute('SELECT count(*) FROM Attachments').fetchone()[0] == 1
restored = sqlite3.connect(sys.argv[2])
assert restored.execute("SELECT count(*) FROM Devices WHERE Revoked = 0").fetchone()[0] == 0
print("PASS: online backup and offline restore preserve the vault and sign out restored devices")
PY
stop_server

# Restoring an older backup must not lose edits made after it.
mkdir "$task_dir/restore-probe"
start_server "$task_dir/restore-server"
probe restore-before "$address" "$task_dir/restore-server/setup-code" "$task_dir/restore-probe"
Journal__DataDirectory="$task_dir/restore-server" dotnet "$server_dll" --backup "$task_dir/older-backup"
probe restore-after "$address" "$task_dir/restore-probe"
stop_server
dotnet "$server_dll" --restore "$task_dir/older-backup" "--Journal:DataDirectory=$task_dir/restored-older"
start_server "$task_dir/restored-older"
probe restore-verify "$address" "$task_dir/restore-probe"
stop_server

# A server whose data folder is replaced by an older copy keeps its identity, and the Mac's edits take the positions,
# records and revision numbers of the phone's lost ones: whether the phone had read past its edits or not, and edited
# again, both versions are kept as entries (protocol/README.md, sync-continuity-digest).
mkdir "$task_dir/rollback-probe"
start_server "$task_dir/rollback-server"
probe rollback-setup "$address" "$task_dir/rollback-server/setup-code" "$task_dir/rollback-probe"
for phase in unsent read; do
  stop_server
  rm -rf "$task_dir/rollback-copy"
  cp -R "$task_dir/rollback-server" "$task_dir/rollback-copy"
  start_server "$task_dir/rollback-server"
  probe "rollback-$phase" "$address" "$task_dir/rollback-probe"
  stop_server
  rm -rf "$task_dir/rollback-server"
  cp -R "$task_dir/rollback-copy" "$task_dir/rollback-server"
  start_server "$task_dir/rollback-server"
  probe "rollback-check-$phase" "$address" "$task_dir/rollback-probe"
done
stop_server

# Agent access through the server: an OAuth client is allowed by code, reads only the shared journal over MCP, sees a
# synchronized edit and loses access when revoked (protocol/agent-access-server.md).
mkdir "$task_dir/agent-probe"
start_server "$task_dir/agent-server"
probe agent-connect "$address" "$task_dir/agent-server/setup-code" "$task_dir/agent-probe"
probe agent-revoke "$address" "$task_dir/agent-probe"
stop_server
# With All Journals, a second journal is shared too; once it goes to Recently Deleted, a sync takes it out of what the
# agent lists and finds.
start_server "$task_dir/agent-journals-server"
probe agent-journals "$address" "$task_dir/agent-journals-server/setup-code"
stop_server

# Merging a device's journals into a server's (docs/design/join-with-local-journals.md): an attempt that stops after
# sending images and some records, then one with new access, leave everything once on a server that never replaces
# an image.
start_server "$task_dir/merge-server"
probe merge "$address" "$task_dir/merge-server/setup-code"
stop_server

# Pins and journal order (docs/design/pinned-entries.md): the server takes the library record, and changes made on two
# devices at once are merged without a review.
start_server "$task_dir/library-server"
probe library "$address" "$task_dir/library-server/setup-code"
stop_server
