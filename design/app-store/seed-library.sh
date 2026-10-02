#!/bin/bash
# Seeds the sample library for the App Store screenshots into a new app data folder
# (docs/app-store/screenshots-plan.md). Open it with JOURNAL_DATA_DIR=<folder>; the app asks for the master
# password once. The password is generated on first use and kept in design/app-store/.seed-password, which is
# ignored by git. JOURNAL_SCREENSHOT_HISTORY=0 leaves out the earlier versions of "Bread, attempt four", for a
# library that will be uploaded to a new server.
set -euo pipefail
cd "$(dirname "$0")/../.."
folder="${1:?Usage: seed-library.sh <new-data-folder>}"
secret=design/app-store/.seed-password
if [[ ! -s "$secret" ]]; then
  (umask 077 && openssl rand -base64 18 | tr -d '/+=' >"$secret")
fi
swift build --package-path apps/apple/Packages/JournalCore --product JournalMeasure -c release >/dev/null
JOURNAL_SCREENSHOT_PASSWORD="$(cat "$secret")" JOURNAL_SCREENSHOT_PHOTOS="$PWD/design/app-store/photos" \
  apps/apple/Packages/JournalCore/.build/release/JournalMeasure seed-screenshots "$folder"
printf 'Seeded %s\n' "$folder"
