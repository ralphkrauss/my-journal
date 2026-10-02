#!/bin/bash
# Builds a team-signed, sandboxed Mac app for local testing. Its keys live in the data protection keychain, so
# rebuilding never asks for the login keychain password. Requires Xcode signed in to the team's Apple account.
# With a published server (package-server.sh osx-arm64 or osx-x64), the app includes it for Use This Mac….
set -euo pipefail
cd "$(dirname "$0")/.."
team="${1:?Usage: build-mac-development.sh <team-id> [configuration] [published-server-directory]}"
configuration="${2:-Debug}"
server="${3:-}"
scripts/generate-apple.sh
xcodebuild -jobs 4 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (Mac)' -configuration "$configuration" \
  -destination 'platform=macOS' -derivedDataPath artifacts/DerivedDataMacTeam \
  -onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic \
  JOURNAL_MAC_ENTITLEMENTS=Signing/JournalMac-Development.entitlements build
app="$PWD/artifacts/DerivedDataMacTeam/Build/Products/$configuration/My Journal.app"
[[ -z "$server" ]] || scripts/embed-mac-server.sh "$app" "$server"
printf 'Team-signed app: %s\n' "$app"
