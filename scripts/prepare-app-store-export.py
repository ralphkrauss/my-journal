"""Check an App Store profile before any credential is imported, then write the export options.

Usage: prepare-app-store-export.py <credential-directory> <ios|macos>. The directory holds the
decoded profile as profile.plist. iOS reads IOS_TEAM_ID, IOS_PROFILE_NAME and IOS_SIGNING_IDENTITY;
the Mac reads the MAC_ equivalents and MAC_INSTALLER_IDENTITY, which signs the installer package
that the Mac App Store takes.
"""

import datetime
import os
import pathlib
import plistlib
import sys

if len(sys.argv) != 3 or sys.argv[2] not in ("ios", "macos"):
    raise SystemExit("Usage: prepare-app-store-export.py <credential-directory> <ios|macos>")
root = pathlib.Path(sys.argv[1])
platform = sys.argv[2]
variables = "IOS" if platform == "ios" else "MAC"
with (root / "profile.plist").open("rb") as source:
    profile = plistlib.load(source)
team = os.environ[f"{variables}_TEAM_ID"]
name = os.environ[f"{variables}_PROFILE_NAME"]
method = "app-store-connect"
bundle = "io.github.ralphkrauss.myjournal"
entitlements = profile.get("Entitlements", {})
prefixes = profile.get("ApplicationIdentifierPrefix", [])
valid_ids = {f"{prefix}.{bundle}" for prefix in prefixes}
# Mac profiles name the app's identifier and debugging entitlement differently.
identifier_key = "application-identifier"
if platform == "macos":
    identifier_key = "com.apple.application-identifier"
if profile.get("Name") != name or team not in profile.get("TeamIdentifier", []):
    raise SystemExit("Provisioning profile does not match the configured name/team.")
if ("iOS" if platform == "ios" else "OSX") not in profile.get("Platform", []):
    raise SystemExit(f"Use a provisioning profile for {'iOS' if platform == 'ios' else 'macOS'}.")
if (
    entitlements.get(identifier_key) not in valid_ids
    or entitlements.get("com.apple.developer.team-identifier") != team
):
    raise SystemExit(f"Use an explicit provisioning profile for {bundle} and the configured team.")
expiry = profile.get("ExpirationDate")
if not isinstance(expiry, datetime.datetime) or expiry <= datetime.datetime.now(
    datetime.UTC
).replace(tzinfo=None):
    raise SystemExit("Provisioning profile is expired or lacks an expiration date.")
debuggable = (
    entitlements.get("get-task-allow") is not False
    if platform == "ios"
    else bool(
        entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow")
    )
)
if profile.get("ProvisionsAllDevices") or debuggable:
    raise SystemExit("Provisioning profile type does not match the export method.")
if profile.get("ProvisionedDevices"):
    raise SystemExit("Profile device eligibility does not match the export method.")
# Only the protected TestFlight workflow runs this: it signs at export and uploads the build.
options = {
    "destination": "upload",
    "method": method,
    "teamID": team,
    "signingStyle": "manual",
    "signingCertificate": os.environ[f"{variables}_SIGNING_IDENTITY"],
    "provisioningProfiles": {bundle: name},
    "manageAppVersionAndBuildNumber": False,
    "uploadSymbols": True,
}
if platform == "macos":
    options["installerSigningCertificate"] = os.environ["MAC_INSTALLER_IDENTITY"]
with (root / "ExportOptions.plist").open("wb") as target:
    plistlib.dump(options, target)
