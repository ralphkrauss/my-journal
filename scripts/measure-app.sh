#!/bin/bash
# Opt-in release measurement of the apps on a heavy synthetic library, separate from routine correctness lanes.
# Usage: measure-app.sh <new-output-directory> mac|ios [existing-fixture-directory]
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Usage: measure-app.sh <new-output-directory> mac|ios [fixture-directory]}"
platform="${2:?Choose mac or ios.}"
fixture="${3:-}"
[[ ! -e "$output" ]] || {
  echo "Choose a new output directory." >&2
  exit 2
}
mkdir -p "$output"
output="$(cd "$output" && pwd)"
package=apps/apple/Packages/JournalCore
if [[ -z "$fixture" ]]; then
  swift build --package-path "$package" -c release --force-resolved-versions --product JournalMeasure \
    -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
  fixture="$output/fixture"
  "$(swift build --package-path "$package" -c release --show-bin-path)/JournalMeasure" seed-heavy "$fixture" \
    >"$output/seed.json"
  trap 'rm -rf "$fixture"' EXIT
fi
fixture="$(cd "$fixture" && pwd)"
scripts/generate-apple.sh apps/apple/measurement.yml JournalMeasurements
arguments=(-project apps/apple/JournalMeasurements.xcodeproj -derivedDataPath "${JOURNAL_MEASURE_DERIVED_DATA:-$output/build}"
  -onlyUsePackageVersionsFromResolvedFile ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO ENABLE_TESTABILITY=YES "JOURNAL_MEASURE_FIXTURE=$fixture" "JOURNAL_MEASURE_STEPS=${JOURNAL_MEASURE_STEPS:-}")
case "$platform" in
  mac)
    xcodebuild "${arguments[@]}" -scheme JournalMacMeasured -destination 'platform=macOS' \
      -only-testing:JournalMacMeasurements/HeavyLibraryMeasurement \
      CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=${JOURNAL_MAC_SIGNING_IDENTITY:--}" test | tee "$output/test.log"
    ;;
  ios)
    simulator="$(scripts/prepare-simulator.sh)"
    xcodebuild "${arguments[@]}" -scheme JournalIOSMeasured -destination "platform=iOS Simulator,id=$simulator" \
      -only-testing:JournalIOSMeasurements/HeavyLibraryMeasurement \
      CODE_SIGN_IDENTITY=- test | tee "$output/test.log"
    ;;
  *)
    echo "Choose mac or ios." >&2
    exit 2
    ;;
esac
grep -o 'JOURNAL-MEASUREMENT .*' "$output/test.log" | head -1 | cut -d' ' -f2- >"$output/report.json"
python3 -m json.tool "$output/report.json"
