"""Refuse mismatched or device-specific profiles before importing CI credentials."""

import copy
import datetime
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
script = root / "scripts/prepare-app-store-export.py"
bundle = "io.github.ralphkrauss.myjournal"
profiles = {
    "ios": {
        "Name": "Synthetic App Store Profile",
        "Platform": ["iOS", "xrOS", "visionOS"],
        "TeamIdentifier": ["TESTTEAM00"],
        "ApplicationIdentifierPrefix": ["TESTPREFIX"],
        "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
        "Entitlements": {
            "application-identifier": f"TESTPREFIX.{bundle}",
            "com.apple.developer.team-identifier": "TESTTEAM00",
            "get-task-allow": False,
        },
    },
    "macos": {
        "Name": "Synthetic Mac App Store Profile",
        "Platform": ["OSX"],
        "TeamIdentifier": ["TESTTEAM00"],
        "ApplicationIdentifierPrefix": ["TESTPREFIX"],
        "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
        "Entitlements": {
            "com.apple.application-identifier": f"TESTPREFIX.{bundle}",
            "com.apple.developer.team-identifier": "TESTTEAM00",
            "keychain-access-groups": ["TESTPREFIX.*"],
        },
    },
}
debugging = {"ios": "get-task-allow", "macos": "com.apple.security.get-task-allow"}
identifiers = {"ios": "application-identifier", "macos": "com.apple.application-identifier"}
with tempfile.TemporaryDirectory(prefix="journal-signing-check-") as temporary:
    directory = pathlib.Path(temporary)

    def check(platform, candidate, accepted):
        prefix = "IOS" if platform == "ios" else "MAC"
        environment = dict(
            os.environ,
            **{
                f"{prefix}_TEAM_ID": "TESTTEAM00",
                f"{prefix}_PROFILE_NAME": profiles[platform]["Name"],
                f"{prefix}_SIGNING_IDENTITY": "Apple Distribution: Synthetic Identity",
                "MAC_INSTALLER_IDENTITY": "3rd Party Mac Developer Installer: Synthetic Identity",
            },
        )
        options = directory / "ExportOptions.plist"
        options.unlink(missing_ok=True)
        with (directory / "profile.plist").open("wb") as target:
            plistlib.dump(candidate, target)
        result = subprocess.run(
            [sys.executable, str(script), temporary, platform],
            env=environment,
            capture_output=True,
            check=False,
        )
        assert (result.returncode == 0) == accepted, (platform, candidate, result.stderr)
        assert options.exists() == accepted
        if accepted:
            with options.open("rb") as source:
                exported = plistlib.load(source)
            assert exported["destination"] == "upload"
            assert exported["method"] == "app-store-connect"
            assert exported["provisioningProfiles"] == {bundle: profiles[platform]["Name"]}
            # The Mac App Store takes an installer package, signed with its own certificate.
            assert ("installerSigningCertificate" in exported) == (platform == "macos")

    for platform, profile in profiles.items():
        check(platform, profile, True)
        other = "macos" if platform == "ios" else "ios"
        for key, value in [
            ("Name", "Wrong Profile"),
            ("TeamIdentifier", ["OTHERTEAM0"]),
            ("ExpirationDate", datetime.datetime.now() - datetime.timedelta(days=1)),
            ("ProvisionedDevices", ["synthetic-device"]),
            ("ProvisionsAllDevices", True),
            ("Platform", profiles[other]["Platform"]),
        ]:
            invalid = copy.deepcopy(profile)
            invalid[key] = value
            check(platform, invalid, False)
        for key, value in [
            (identifiers[platform], "TESTPREFIX.org.other.app"),
            ("com.apple.developer.team-identifier", "OTHERTEAM0"),
            (debugging[platform], True),
        ]:
            invalid = copy.deepcopy(profile)
            invalid["Entitlements"][key] = value
            check(platform, invalid, False)
        # A profile for the other platform names the app differently and is refused.
        invalid = copy.deepcopy(profile)
        identifier = invalid["Entitlements"].pop(identifiers[platform])
        invalid["Entitlements"][identifiers[other]] = identifier
        check(platform, invalid, False)
print("TestFlight uploads accept matching App Store profiles and refuse unsafe mismatches.")
