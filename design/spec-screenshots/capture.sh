#!/bin/bash
# Regenerates the screenshots of the Apple implementation notes (spec/platforms/apple/screenshots/) from the synthetic
# sample library, with no personal data. See design/spec-screenshots/README.md.
# Usage: mise exec -- design/spec-screenshots/capture.sh [iphone] [ipad] [mac]     (default: all three)
# Environment (all optional):
#   JOURNAL_SPEC_OUTPUT                 where the processed PNGs go (default spec/platforms/apple/screenshots)
#   JOURNAL_SCREENSHOT_DERIVED_DATA     derived data folder (default artifacts/DD-spec)
#   JOURNAL_SIGNING_IDENTITY            the Apple Development identity the Mac capture is signed with (required for mac)
#   JOURNAL_SPEC_TESTS                  space-separated test classes to run instead of all of them (iPhone and iPad)
#   JOURNAL_SPEC_KEEP_RAW=1             keep the unprocessed captures and their accessibility trees in artifacts/spec-raw
set -euo pipefail
cd "$(dirname "$0")/../.."
devices=("$@")
[[ ${#devices[@]} -gt 0 ]] || devices=(iphone ipad mac)
output="${JOURNAL_SPEC_OUTPUT:-spec/platforms/apple/screenshots}"
derived="${JOURNAL_SCREENSHOT_DERIVED_DATA:-artifacts/DD-spec}"
work="$(mktemp -d -t journal-spec-screenshots)"
failed=0
public_url="https://journal.example.net"
simulator=""
server_pids=()

# The classes of JournalScreenshots/iOS/Spec*CaptureTests.swift, in the order they run. The warm-up closes a new
# simulator's keyboard tips; the dark class runs last, with the simulator in dark appearance.
light_classes=(SpecWarmUpCaptureTests SpecBrowseCaptureTests SpecEditorCaptureTests SpecLibraryCaptureTests
  SpecSettingsCaptureTests SpecStartCaptureTests SpecDataCaptureTests SpecConflictCaptureTests
  SpecJournalCaptureTests SpecSyncCaptureTests)
dark_classes=(SpecDarkCaptureTests)

# shellcheck disable=SC2329 # Runs from the EXIT trap below, which ShellCheck doesn't follow here.
cleanup() {
  stop_servers
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" 2>/dev/null || true
    xcrun simctl delete "$simulator" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap 'cleanup' EXIT

seed_library() {
  # Fixed dates, so the screenshots do not change from one day to the next.
  JOURNAL_SCREENSHOT_FIXED_DATES=1 design/app-store/seed-library.sh "$work/seed" >/dev/null
}

# Starts a disposable server on a fixed loopback port (its address shows in Settings) and waits for its setup code. It
# runs in this shell, not a subshell, so cleanup can stop it.
# The first announces the public address https://journal.example.net, which Agent Access shows in place of the
# loopback address; the library keeps syncing with it on the loopback address.
start_server() {
  local name="$1" port="$2" public="${3:-}"
  mkdir -p "$work/$name"
  : >"$work/$name/log"
  Journal__DataDirectory="$work/$name/data" Journal__PublicUrl="$public" \
    AllowedHosts="localhost;127.0.0.1;[::1];journal.example.net" ASPNETCORE_URLS="http://127.0.0.1:$port" \
    dotnet server/src/Journal.Api/bin/Debug/net10.0/Journal.Api.dll >"$work/$name/log" 2>&1 &
  server_pids+=($!)
  for _ in {1..100}; do
    [[ -f "$work/$name/data/setup-code" ]] && break
    sleep 0.1
  done
  [[ -f "$work/$name/data/setup-code" ]] || {
    cat "$work/$name/log" >&2
    exit 1
  }
}

stop_servers() {
  for pid in ${server_pids[@]+"${server_pids[@]}"}; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  server_pids=()
  rm -rf "$work/encrypted" "$work/plain"
}

# Creates the one simulator of a run, named as the device is shown in the captures, and boots it.
create_simulator() {
  local name="$1" type="$2" runtime
  runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and r["platform"] == "iOS"]
print(sorted(runtimes, key=lambda r: r["version"].split("."))[-1]["identifier"])')"
  simulator="$(xcrun simctl create "$name" "com.apple.CoreSimulator.SimDeviceType.$type" "$runtime")"
  xcrun simctl boot "$simulator"
  xcrun simctl bootstatus "$simulator" -b >/dev/null
  xcrun simctl status_bar "$simulator" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 --operatorName ''
}

delete_simulator() {
  xcrun simctl shutdown "$simulator" 2>/dev/null || true
  xcrun simctl delete "$simulator"
  simulator=""
}

run_classes() {
  local raw="$1"
  shift
  local only=()
  for class in "$@"; do only+=("-only-testing:JournalScreenshotUITests/$class"); done
  TEST_RUNNER_JOURNAL_SCREENSHOT_LIBRARY="$work/seed" \
    TEST_RUNNER_JOURNAL_SCREENSHOT_PASSWORD_FILE="$PWD/design/app-store/.seed-password" \
    TEST_RUNNER_JOURNAL_SCREENSHOT_OUTPUT="$raw" \
    TEST_RUNNER_JOURNAL_SPEC_TREES="${JOURNAL_SPEC_KEEP_RAW:+1}" \
    TEST_RUNNER_JOURNAL_SPEC_SERVER="http://127.0.0.1:18765" TEST_RUNNER_JOURNAL_SPEC_SETUP_CODE="$code_a" \
    TEST_RUNNER_JOURNAL_SPEC_PLAIN_SERVER="http://127.0.0.1:18766" TEST_RUNNER_JOURNAL_SPEC_PLAIN_CODE="$code_b" \
    xcodebuild -project apps/apple/JournalScreenshots.xcodeproj -scheme JournalScreenshots \
    -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$derived" -parallel-testing-enabled NO \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- "${only[@]}" \
    -resultBundlePath "$work/result-$RANDOM.xcresult" test-without-building 2>&1 |
    grep -E "error:|Test Case .* (passed|failed)|\*\* TEST" || true
}

capture_simulator() {
  local device="$1" name="$2" type="$3" raw="$work/raw-$1"
  mkdir -p "$raw"
  create_simulator "$name" "$type"
  scripts/generate-apple.sh apps/apple/screenshots.yml JournalScreenshots >/dev/null
  xcodebuild -project apps/apple/JournalScreenshots.xcodeproj -scheme JournalScreenshots \
    -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$derived" \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- build-for-testing 2>&1 | grep -E "error:|BUILD" || true
  local light=("${light_classes[@]}") dark=("${dark_classes[@]}")
  if [[ -n "${JOURNAL_SPEC_TESTS:-}" ]]; then
    read -r -a light <<<"$JOURNAL_SPEC_TESTS"
    dark=()
  fi
  xcrun simctl ui "$simulator" appearance light
  run_classes "$raw" "${light[@]}"
  if [[ ${#dark[@]} -gt 0 ]]; then
    xcrun simctl ui "$simulator" appearance dark
    run_classes "$raw" "${dark[@]}"
    xcrun simctl ui "$simulator" appearance light
  fi
  delete_simulator
  finish "$device" "$raw"
}

# Resamples the raw captures into the screenshots folder, and reports failed and skipped captures.
finish() {
  local device="$1" raw="$2"
  if compgen -G "$raw/failed-*.png" >/dev/null; then
    echo "A capture failed: $(find "$raw" -name 'failed-*.png' -exec basename {} \; | tr '\n' ' ')" >&2
    failed=1
  fi
  if [[ -f "$raw/failed.txt" ]]; then
    echo "Failed states: $(tr '\n' ' ' <"$raw/failed.txt")" >&2
    failed=1
  fi
  [[ ! -f "$raw/skipped.txt" ]] || cat "$raw/skipped.txt" >&2
  if [[ -n "${JOURNAL_SPEC_KEEP_RAW:-}" ]]; then
    mkdir -p "artifacts/spec-raw/$device"
    cp -R "$raw/." "artifacts/spec-raw/$device/"
  fi
  python3 design/spec-screenshots/process.py "$device" "$raw" "$output/$device"
}

capture_mac() {
  : "${JOURNAL_SIGNING_IDENTITY:?Set JOURNAL_SIGNING_IDENTITY to your Apple Development identity for the Mac capture}"
  local raw="$work/raw-mac"
  # The sandboxed test host can only write inside its own container.
  local container="$HOME/Library/Containers/io.github.ralphkrauss.myjournal/Data/tmp/journal-spec-screenshots"
  rm -rf "$container"
  mkdir -p "$container"
  mkdir -p "$raw"
  scripts/generate-apple.sh apps/apple/screenshots.yml JournalScreenshots >/dev/null
  cp -R "$work/seed" "$container/library"
  TEST_RUNNER_JOURNAL_DATA_DIR="$container/library" \
    TEST_RUNNER_JOURNAL_SCREENSHOT_PASSWORD_FILE="$PWD/design/app-store/.seed-password" \
    TEST_RUNNER_JOURNAL_SCREENSHOT_OUTPUT="$container/captures" \
    TEST_RUNNER_JOURNAL_SPEC_SERVER="http://127.0.0.1:18765" TEST_RUNNER_JOURNAL_SPEC_SETUP_CODE="$code_a" \
    TEST_RUNNER_JOURNAL_SPEC_PUBLIC_URL="$public_url" TEST_RUNNER_JOURNAL_UI_TEST_DEVICE_AUTH=success \
    xcodebuild -project apps/apple/JournalScreenshots.xcodeproj -scheme JournalMacScreenshots \
    -destination 'platform=macOS' -derivedDataPath "$derived-mac" -onlyUsePackageVersionsFromResolvedFile \
    -only-testing:JournalMacScreenshots/SpecMacCapture CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=$JOURNAL_SIGNING_IDENTITY" test 2>&1 | grep -E "error:|Test Case .* (passed|failed)|\*\* TEST" || true
  for _ in {1..20}; do
    compgen -G "$container/captures/*.png" >/dev/null && break
    sleep 0.5
  done
  cp "$container/captures/"* "$raw/" 2>/dev/null || true
  rm -rf "$container"
  finish mac "$raw"
}

unknown_device() {
  echo "Unknown device $1 (iphone, ipad or mac)." >&2
  failed=1
}

seed_library
for device in "${devices[@]}"; do
  # Each device sets up its own new servers: a server is set up once.
  start_server encrypted 18765 "$public_url"
  start_server plain 18766
  code_a="$(cat "$work/encrypted/data/setup-code")"
  code_b="$(cat "$work/plain/data/setup-code")"
  case "$device" in
    iphone) capture_simulator iphone iPhone iPhone-17 ;;
    ipad) capture_simulator ipad iPad iPad-Pro-11-inch-M5-12GB ;;
    mac) capture_mac ;;
    *) unknown_device "$device" ;;
  esac
  stop_servers
done
exit "$failed"
