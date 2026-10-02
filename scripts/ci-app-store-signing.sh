#!/bin/bash
# Prepare App Store signing and upload credentials only on an ephemeral hosted macOS TestFlight runner.
# iOS reads the IOS_ variables; the Mac reads the MAC_ ones and also imports the installer certificate that signs
# the package the Mac App Store takes. Both use the same App Store Connect API key.
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:?Usage: ci-app-store-signing.sh <ios|macos>}"
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "$(uname -s)" == Darwin ]] || {
  echo 'App Store signing setup is restricted to GitHub-hosted macOS runners.' >&2
  exit 2
}
case "$platform" in
  ios) variables=(IOS_CERTIFICATE_P12 IOS_CERTIFICATE_PASSWORD IOS_PROVISIONING_PROFILE IOS_TEAM_ID IOS_PROFILE_NAME
    IOS_SIGNING_IDENTITY) ;;
  macos) variables=(MAC_CERTIFICATE_P12 MAC_CERTIFICATE_PASSWORD MAC_PROVISIONING_PROFILE MAC_TEAM_ID MAC_PROFILE_NAME
    MAC_SIGNING_IDENTITY MAC_INSTALLER_CERTIFICATE_P12 MAC_INSTALLER_CERTIFICATE_PASSWORD MAC_INSTALLER_IDENTITY) ;;
  *)
    echo 'Choose ios or macos.' >&2
    exit 2
    ;;
esac
: "${RUNNER_TEMP:?}"
for variable in "${variables[@]}" ASC_API_KEY_P8 ASC_API_KEY_ID; do
  [[ -n "${!variable:-}" ]] || {
    echo "$variable is required." >&2
    exit 2
  }
done
[[ "$ASC_API_KEY_ID" =~ ^[A-Z0-9]{10}$ ]] || {
  echo 'ASC_API_KEY_ID must be the 10-character App Store Connect key ID.' >&2
  exit 2
}
umask 077
directory="$RUNNER_TEMP/journal-$platform-signing"
mkdir "$directory"
python3 - "$directory" "$platform" <<'PY'
import base64
import os
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
variables = "IOS" if sys.argv[2] == "ios" else "MAC"
files = [(f"{variables}_CERTIFICATE_P12", "certificate.p12"), (f"{variables}_PROVISIONING_PROFILE", "profile")]
if variables == "MAC":
    files.append(("MAC_INSTALLER_CERTIFICATE_P12", "installer.p12"))
for variable, filename in files:
    (root / filename).write_bytes(base64.b64decode(os.environ[variable], validate=True))
(root / f"AuthKey_{os.environ['ASC_API_KEY_ID']}.p8").write_text(os.environ["ASC_API_KEY_P8"])
PY
security cms -D -i "$directory/profile" -o "$directory/profile.plist"
python3 scripts/prepare-app-store-export.py "$directory" "$platform"
keychain="$directory/release.keychain-db"
keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "$keychain_password" "$keychain"
# Lock after an hour; the TestFlight job deletes this keychain as soon as the upload finishes.
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain"
security default-keychain -d user -s "$keychain"
# Import private keys as non-extractable (-x), trusted only for signing, so no later step can export them.
if [[ "$platform" == ios ]]; then
  security import "$directory/certificate.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" \
    -x -T /usr/bin/codesign >/dev/null
else
  security import "$directory/certificate.p12" -k "$keychain" -P "$MAC_CERTIFICATE_PASSWORD" \
    -x -T /usr/bin/codesign >/dev/null
  security import "$directory/installer.p12" -k "$keychain" -P "$MAC_INSTALLER_CERTIFICATE_PASSWORD" \
    -x -T /usr/bin/productbuild >/dev/null
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
if [[ "$platform" == ios ]]; then
  cp "$directory/profile" "$profiles/journal-release.mobileprovision"
else
  cp "$directory/profile" "$profiles/journal-release.provisionprofile"
fi
rm -f "$directory/certificate.p12" "$directory/installer.p12" "$directory/profile.plist" "$directory/profile"
