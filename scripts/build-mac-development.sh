#!/bin/bash
# Builds a team-signed, sandboxed Mac app for local testing. Its keys live in the data protection keychain, so
# rebuilding never asks for the login keychain password. Requires Xcode signed in to the team's Apple account.
set -euo pipefail
cd "$(dirname "$0")/.."
team="${1:?Usage: build-mac-development.sh <team-id> [configuration]}"
configuration="${2:-Debug}"
scripts/generate-apple.sh
xcodebuild -jobs 4 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (Mac)' -configuration "$configuration" \
  -destination 'platform=macOS' -derivedDataPath artifacts/DerivedDataMacTeam \
  -onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic \
  JOURNAL_MAC_ENTITLEMENTS=Signing/JournalMac-Development.entitlements build
app="$PWD/artifacts/DerivedDataMacTeam/Build/Products/$configuration/My Journal.app"
printf 'Team-signed app: %s\n' "$app"
