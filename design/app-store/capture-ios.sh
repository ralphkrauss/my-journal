#!/bin/bash
# Captures the iPhone or iPad App Store screenshots (docs/app-store/screenshots-plan.md) on one simulator.
# Seeds a fresh sample library, sets the status bar to 9:41 with full battery and Wi-Fi, runs the opt-in
# JournalScreenshotUITests in light and then dark appearance, and writes the PNG captures to <output>.
# Usage: capture-ios.sh <simulator-id> <new-output-directory> [test names, default: all]
set -euo pipefail
cd "$(dirname "$0")/../.."
device="${1:?Usage: capture-ios.sh <simulator-id> <new-output-directory> [tests]}"
output="${2:?Choose an output directory}"
shift 2
tests=("$@")
[[ ${#tests[@]} -gt 0 ]] || tests=(test1Writing test4FindAgain test5Journals test6Dark test9Privacy)
mkdir -p "$output"
output="$(cd "$output" && pwd)"
work="$(mktemp -d -t journal-screenshots)"
library="$work/library"
design/app-store/seed-library.sh "$library" >/dev/null
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100 --operatorName ''
# Enrolled Face ID or Touch ID, so Privacy can show "Unlock with Face ID" turned on.
xcrun simctl spawn "$device" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
xcrun simctl spawn "$device" notifyutil -p com.apple.BiometricKit.enrollmentChanged
scripts/generate-apple.sh apps/apple/screenshots.yml JournalScreenshots >/dev/null
derived="${JOURNAL_SCREENSHOT_DERIVED_DATA:-artifacts/DD-shots}"
run() {
  TEST_RUNNER_JOURNAL_SCREENSHOT_LIBRARY="$library" \
    TEST_RUNNER_JOURNAL_SCREENSHOT_PASSWORD_FILE="$PWD/design/app-store/.seed-password" \
    TEST_RUNNER_JOURNAL_SCREENSHOT_OUTPUT="$output" \
    xcodebuild -project apps/apple/JournalScreenshots.xcodeproj -scheme JournalScreenshots \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" -parallel-testing-enabled NO \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- "$@"
}
# capture-sync.sh builds once and runs two simulators at the same time.
if [[ -z "${JOURNAL_SCREENSHOT_SKIP_BUILD:-}" ]]; then
  run build-for-testing | grep -E "error:|BUILD" || true
fi
for appearance in light dark; do
  selected=()
  for test in "${tests[@]}"; do
    if [[ "$appearance" == dark && "$test" == test6Dark ]] || [[ "$appearance" == light && "$test" != test6Dark ]]; then
      selected+=("-only-testing:JournalScreenshotUITests/ScreenshotCaptureUITests/$test")
    fi
  done
  [[ ${#selected[@]} -gt 0 ]] || continue
  xcrun simctl ui "$device" appearance "$appearance"
  run test-without-building "${selected[@]}" -resultBundlePath "$work/$appearance.xcresult"
done
xcrun simctl ui "$device" appearance light
rm -rf "$work"
printf 'Captures: %s\n' "$output"
