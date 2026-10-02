#!/bin/bash
# Captures the Mac windows for the App Store screenshots (docs/app-store/screenshots-plan.md). Seeds a fresh
# sample library inside the app's sandbox container, then runs the opt-in JournalMacScreenshots test hosted in a
# team-signed build, which opens the library in the app's own windows and renders them. Writes the PNG captures
# and the agent transcript to <output>. The owner's own library is never opened.
# Usage: capture-mac.sh <new-output-directory>
set -euo pipefail
cd "$(dirname "$0")/../.."
output="${1:?Usage: capture-mac.sh <output-directory>}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
# The sandboxed test host can only write inside its own container.
work="$HOME/Library/Containers/io.github.ralphkrauss.myjournal/Data/tmp/journal-screenshots"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
design/app-store/seed-library.sh "$work/library" >/dev/null
scripts/generate-apple.sh apps/apple/screenshots.yml JournalScreenshots >/dev/null
TEST_RUNNER_JOURNAL_DATA_DIR="$work/library" \
  TEST_RUNNER_JOURNAL_SCREENSHOT_PASSWORD_FILE="$PWD/design/app-store/.seed-password" \
  TEST_RUNNER_JOURNAL_SCREENSHOT_OUTPUT="$work/captures" \
  xcodebuild -project apps/apple/JournalScreenshots.xcodeproj -scheme JournalMacScreenshots \
  -destination 'platform=macOS' -derivedDataPath "${JOURNAL_SCREENSHOT_DERIVED_DATA:-artifacts/DD-shots}" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=${JOURNAL_SIGNING_IDENTITY:?Set JOURNAL_SIGNING_IDENTITY to your Apple Development identity}" test
cp "$work/captures/"* "$output/"
printf 'Captures: %s\n' "$output"
