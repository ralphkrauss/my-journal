#!/bin/bash
# Separate native integration lane: the Mac app's sync recovery (SyncRecoveryServerTests) against real published servers in disposable data directories.
# JOURNAL_TEST_RESULTS keeps the result bundle in a chosen new directory. Extra arguments go to xcodebuild, for
# example CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development: …" to sign the test host with your team.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d "${TMPDIR:-/tmp}/journal-server-recovery.XXXXXXXXXX")"
results="${JOURNAL_TEST_RESULTS:-$work}"
mkdir -p "$results"
results="$(cd "$results" && pwd)"
[[ ! -e "$results/ServerRecovery.xcresult" ]] || {
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
# The published server (over 100 MB) is only needed while the tests run.
trap 'rm -rf "$work/server"; rmdir "$work" 2>/dev/null || true' EXIT
scripts/package-server.sh "$runtime" "$work/server"
export JOURNAL_SERVER_EXECUTABLE="$work/server/Journal.Api"
scripts/generate-apple.sh
# The test host starts the server as a child process inside its sandbox, so only test builds may listen.
xcodebuild -project apps/apple/Journal.xcodeproj -scheme JournalServerRecovery \
  -destination 'platform=macOS' -derivedDataPath artifacts/DerivedData \
  -resultBundlePath "$results/ServerRecovery.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- \
  JOURNAL_MAC_ENTITLEMENTS=Signing/JournalMac-Tests.entitlements "$@" test
python3 scripts/verify-test-results.py "$results/ServerRecovery.xcresult"
printf 'Server recovery results: %s\n' "$results/ServerRecovery.xcresult"
