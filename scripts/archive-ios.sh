#!/bin/bash
# Build a physical-device archive. By default it is unsigned and needs no developer account; signing happens at
# export. JOURNAL_SIGNING_TEAM instead archives with automatic signing through the Xcode account for that team.
# JOURNAL_BUILD_NUMBER sets the build number (CFBundleVersion) without editing the project.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Usage: archive-ios.sh <new-output-directory>}"
build_number="${JOURNAL_BUILD_NUMBER:-}"
team="${JOURNAL_SIGNING_TEAM:-}"
[[ ! -e "$output" ]] || {
  echo "Output already exists; choose a new directory." >&2
  exit 2
}
[[ -z "$build_number" || "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
  echo "JOURNAL_BUILD_NUMBER must be one to three period-separated integers." >&2
  exit 2
}
settings=()
if [[ -n "$build_number" ]]; then
  settings+=("CURRENT_PROJECT_VERSION=$build_number")
fi
if [[ -n "$team" ]]; then
  # Only the signing style and team: a command-line profile or identity would also apply to package resource bundles.
  settings+=(-allowProvisioningUpdates CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$team")
else
  settings+=(CODE_SIGNING_ALLOWED=NO)
fi
mkdir -p "$output"
output="$(cd "$output" && pwd)"
scripts/generate-apple.sh
xcodebuild -project apps/apple/Journal.xcodeproj -scheme 'My Journal (iOS)' -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$output/My Journal.xcarchive" \
  -derivedDataPath "$output/build" -onlyUsePackageVersionsFromResolvedFile "${settings[@]}" archive
app="$output/My Journal.xcarchive/Products/Applications/My Journal.app"
if [[ -n "$build_number" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")" != "$build_number" ]]; then
  echo "The archived app does not carry build number $build_number." >&2
  exit 1
fi
if [[ -n "$team" ]]; then
  codesign --verify --deep --strict "$app"
  printf 'Signed device archive, pending export: %s\n' "$output/My Journal.xcarchive"
else
  printf 'Unsigned device archive (not installable until signed at export): %s\n' "$output/My Journal.xcarchive"
fi
