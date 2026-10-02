#!/bin/bash
# Opt-in release simulator observation, separate from routine correctness/CI lanes.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Usage: measure-native.sh <new-output-directory>}"
[[ ! -e "$output" ]] || {
  echo "Choose a new output directory." >&2
  exit 2
}
mkdir -p "$output"
output="$(cd "$output" && pwd)"
simulator="$(scripts/prepare-simulator.sh)"
scripts/generate-apple.sh apps/apple/measurement.yml JournalMeasurements
xcodebuild -project apps/apple/JournalMeasurements.xcodeproj -scheme JournalPopulated \
  -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$output/build" -resultBundlePath "$output/Measurement.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- ONLY_ACTIVE_ARCH=YES test
xcrun xcresulttool export attachments --path "$output/Measurement.xcresult" --output-path "$output/evidence"
python3 - "$output" <<'PY'
import json
import shutil
import sys
from pathlib import Path

output = Path(sys.argv[1])
evidence = output / "evidence"
manifest = json.loads((evidence / "manifest.json").read_text())
reports = [
    evidence / attachment["exportedFileName"]
    for test in manifest
    for attachment in test.get("attachments", [])
    if attachment.get("suggestedHumanReadableName", "").startswith("native-populated-measurement")
    and attachment["exportedFileName"].endswith(".json")
]
if len(reports) != 1:
    raise SystemExit("Expected exactly one completed measurement report.")
shutil.copyfile(reports[0], output / "report.json")
PY
