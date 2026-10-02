#!/bin/bash
# Separate native integration lane: real self-contained child processes and disposable vaults.
# JOURNAL_TEST_RESULTS keeps the result bundle in a chosen new directory. Extra arguments go to xcodebuild, for
# example CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development: …" to sign the test host with your team.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d "${TMPDIR:-/tmp}/journal-local-server.XXXXXXXXXX")"
results="${JOURNAL_TEST_RESULTS:-$work}"
mkdir -p "$results"
results="$(cd "$results" && pwd)"
[[ ! -e "$results/LocalServer.xcresult" ]] || {
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
export JOURNAL_LOCAL_SERVER_EXECUTABLE="$work/server/Journal.Api"
scripts/generate-apple.sh
xcodebuild -project apps/apple/Journal.xcodeproj -scheme JournalLocalServer \
  -destination 'platform=macOS' -derivedDataPath artifacts/DerivedData \
  -resultBundlePath "$results/LocalServer.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- "$@" test
python3 scripts/verify-test-results.py "$results/LocalServer.xcresult"
printf 'Local server integration results: %s\n' "$results/LocalServer.xcresult"
