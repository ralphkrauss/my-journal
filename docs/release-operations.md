# Release operations

The Release and TestFlight workflows are prepared but have not run on GitHub. Real signing, App Store Connect upload and publication still need a first supervised run. Activate the rulesets first, as described in [repository setup](repository-setup.md). Review changes to these workflows and scripts as security-sensitive code.

## Protected environments

Create two environments in Settings > Environments before the first release or upload. Do not add credentials to an environment until its protection is set.

| Environment | Required reviewer | Deployment refs | Holds |
| --- | --- | --- | --- |
| `release-publish` | The maintainer | Tags matching `v*` | Nothing; publication uses the job's scoped GitHub token |
| `testflight` | The maintainer | The `main` branch | iOS and Mac signing and upload secrets and variables |

Leave **Prevent self-reviews** off while there is a single maintainer. With it on, whoever pushed the tag or dispatched the workflow cannot approve the deployment, so a sole maintainer's release would wait with no eligible reviewer. For one maintainer the approval still provides a deliberate pause before credentials are used or anything becomes public, and the ref restriction still limits what can reach the credentials. If a second trusted reviewer joins, add them and turn Prevent self-reviews on.

GitHub creates a missing environment without any protection the first time a job names it. Every job that uses one of these environments therefore first reads the environment through the API and stops unless it has a required reviewer and a deployment ref policy (`scripts/require-protected-environment.sh`).

Never put credentials in repository files, artifacts or issue reports.

When the release flow below has run once, turn on immutable releases (Settings > General > Releases). The workflow attaches every asset to a draft before publishing it, which immutable releases allow.

## Standalone Linux release

The apps ship through TestFlight and the App Store (below). A GitHub release holds the standalone server for Linux; the container image is published with it.

1. Set the marketing version in `apps/apple/project.yml`. The server release uses the same version. Review release notes and finish the product verification checklist.
2. Merge to `main`, then push an immutable `vMAJOR.MINOR.PATCH` tag matching the marketing version on that commit. Pushing the tag starts `.github/workflows/release.yml`; you can also dispatch the workflow on an existing tag. The version gate refuses other refs, a tag that does not match the marketing version, and a commit that is not on `main`.
3. The complete reusable Quality and Dependency Audit workflows run for the tagged source. Nothing is built for release before they pass.
4. Linux x64 and Arm64 packages are built and checked on matching native runners, including a nonroot read-only container check.
5. When every build and check has passed, the workflow validates the complete download set against its checksums, rejecting missing, extra, altered or symlinked files. It records build provenance attestations for every asset, creates a **draft** release with the assets and generated notes, and deletes the workflow artifacts. The draft is visible only to people with write access.
6. Review the draft: notes, asset names and checksums. Then approve `release-publish`. The publication job checks that the draft still holds exactly the staged assets with the staged checksums, then publishes it. The container image is published by a parallel job under the same approval; see below.

To stop a release, decline `release-publish` and delete the draft. A rerun refuses to create a second release for a tag that already has one, draft or published; review and delete a stale draft first. Do not regenerate different bytes under an already distributed checksum.

Each release has these assets: `journal-server-vX.Y.Z-linux-x64.tar.gz`, `journal-server-vX.Y.Z-linux-arm64.tar.gz` and a combined `SHA256SUMS`. Anyone can check that a download was built by this repository's release workflow:

```sh
gh attestation verify journal-server-vX.Y.Z-linux-x64.tar.gz --repo OWNER/REPOSITORY
```

The packages exist as workflow artifacts only between their build job and the draft job, normally a few minutes, with a one-day retention as a backstop if the draft job fails. In a public repository any signed-in GitHub user can download a workflow artifact during that time.

## TestFlight

`.github/workflows/testflight.yml` is prepared and has not run. Dispatch it manually from `main`. It never runs on pull requests or tags. It uploads the iPhone and iPad app and the Mac app, which share the bundle identifier `io.github.ralphkrauss.myjournal` and one purchase, in two independent jobs.

- It requires every check named in `.github/rulesets/quality.json` to have passed on that commit instead of running Quality again, and runs a fresh Dependency Audit.
- The build number is `<run number + offset>.<run attempt>`, passed to Xcode as `CURRENT_PROJECT_VERSION`; `project.yml` keeps `1` for local builds. The offset is `IOS_BUILD_NUMBER_OFFSET` for iOS and `MAC_BUILD_NUMBER_OFFSET` for the Mac, whose builds are counted separately. App Store Connect rejects a second upload of the same version and build number, so keep this workflow the only automated uploader. If builds of the same version were uploaded another way, for example from Xcode Organizer, set the offset above their build numbers. The numbers are shown in the job summary.
- Each archive is built before any credential exists. The iOS archive is unsigned: signing only at export means no signing setting reaches the Swift package resource bundles (GRDB's privacy-manifest bundle), which reject a command-line provisioning profile, and no development certificate is created on each ephemeral runner. The Mac archive comes from `scripts/archive-mac.sh`, which adds the bundled server and signs each executable to run locally, because the sandbox entitlements the Mac App Store requires must be in the archive for the export to keep them. It refuses an archive whose app, connector or server isn't sandboxed as designed.
- The export signs with the Apple Distribution identity and the App Store provisioning profile (for the Mac also the Mac Installer Distribution identity, which signs the package the Mac App Store takes), then uploads to App Store Connect with an API key. Credentials are validated before import (team, bundle identifier, platform, profile name, expiry, App Store eligibility) and deleted in a step that runs even after failure.

Configure on the `testflight` environment:

- iOS variables `IOS_TEAM_ID`, `IOS_PROFILE_NAME`, `IOS_SIGNING_IDENTITY`, and optionally `IOS_BUILD_NUMBER_OFFSET`; secrets `IOS_CERTIFICATE_P12` (base64 Apple Distribution certificate with private key), `IOS_CERTIFICATE_PASSWORD` and `IOS_PROVISIONING_PROFILE` (base64 iOS App Store profile for `io.github.ralphkrauss.myjournal`).
- Mac variables `MAC_TEAM_ID`, `MAC_PROFILE_NAME`, `MAC_SIGNING_IDENTITY` (for example `Apple Distribution: Name (TEAMID)`), `MAC_INSTALLER_IDENTITY` (for example `3rd Party Mac Developer Installer: Name (TEAMID)`), and optionally `MAC_BUILD_NUMBER_OFFSET`; secrets `MAC_CERTIFICATE_P12` and `MAC_CERTIFICATE_PASSWORD` (the Apple Distribution certificate; it can be the same one as for iOS), `MAC_INSTALLER_CERTIFICATE_P12` and `MAC_INSTALLER_CERTIFICATE_PASSWORD` (Mac Installer Distribution), and `MAC_PROVISIONING_PROFILE` (base64 Mac App Store profile for the same bundle identifier).
- Both jobs use the App Store Connect API key: `ASC_API_KEY_P8` (the private key file's contents), `ASC_API_KEY_ID` and `ASC_API_ISSUER_ID`.

Before the first Mac upload, enable the App Groups capability on the App ID `io.github.ralphkrauss.myjournal` in the developer portal and create the Mac App Store profile afterwards, so the profile authorizes the app group `<TEAMID>.io.github.ralphkrauss.myjournal`. Run `mise exec -- scripts/test-mac-sandbox.sh <team-id>` locally before each Mac upload; it needs a team identity, so CI can't run it.

Create a separate team API key for uploads with the least role that can upload builds (Apple's role table lists Developer for delivering builds; confirm on the first run). Xcode's cloud-managed signing would remove the stored distribution certificate but needs an Admin key, which this workflow deliberately avoids. If a different bundle identifier is adopted, update the Apple project, the app group and keychain group in `apps/apple/Signing`, and the expected identifier in `scripts/prepare-app-store-export.py` and `scripts/archive-mac.sh` together.

What the first run must confirm: that Xcode accepts signing an unsigned iOS archive at export for this app. If it does not, the fallback is to set the signing style, profile and identity on the `JournalIOS` target only in `project.yml`, never on the command line. For the Mac, a local export of an archive from `archive-mac.sh` with development signing re-signed the app and the server and kept each one's entitlements, but no distribution export has run.

For the first betas, uploading from Xcode Organizer with automatic signing is the lowest-risk route: for iOS, choose the My Journal (iOS) scheme, then Product > Archive, then Distribute App > App Store Connect. For the Mac, archive with `JOURNAL_SIGNING_TEAM=<team-id> JOURNAL_BUILD_NUMBER=<n> scripts/archive-mac.sh <new-output-directory>`, open the archive to add it to the Organizer, then Distribute App > App Store Connect; Product > Archive would leave out the bundled server. The app icon and the answers App Store Connect asks for (app privacy, export compliance) are separate from this workflow; the privacy manifest is part of the app (`apps/apple/JournalApp/Resources/PrivacyInfo.xcprivacy`).

Locally, `JOURNAL_SIGNING_TEAM=<team-id> JOURNAL_BUILD_NUMBER=<n> scripts/archive-ios.sh <new-output-directory>` builds an automatically signed iOS archive through your Xcode account, and `scripts/export-ios.sh` exports it with options you review. Neither uploads anything.

## App Store Connect

The repository is the app's website; there is no separate site. Enter these addresses in the app's App Store Connect record:

| Field | URL |
| --- | --- |
| Privacy Policy URL | https://github.com/ralphkrauss/my-journal/blob/main/PRIVACY.md |
| Support URL | https://github.com/ralphkrauss/my-journal/blob/main/SUPPORT.md |
| Marketing URL (optional) | https://github.com/ralphkrauss/my-journal |

The listing text, App Privacy and age rating answers, review notes and screenshot plan are in [App Store material](app-store/README.md).

The addresses point at `main`, so renaming or moving [PRIVACY.md](../PRIVACY.md) or [SUPPORT.md](../SUPPORT.md) breaks them until App Store Connect is updated. They work only once the repository is public. When the privacy policy changes, update its effective date, and check that the App Privacy answers still match it and the privacy manifest.

## Export compliance

Both apps declare `ITSAppUsesNonExemptEncryption` as `NO`. That answer relies on every algorithm coming from the operating system: CryptoKit (AES-GCM, HKDF, SHA-256, Curve25519), CommonCrypto (PBKDF2), `SecRandomCopyBytes` and HTTPS through URLSession, with GRDB using the system SQLite. Confirm it once in App Store Connect's encryption questionnaire. Revisit it before adding any encryption that isn't the operating system's (for example libsodium, Argon2 or SQLCipher). The Mac build uploaded to App Store Connect includes the bundled server, so confirm this answer for it before the first Mac upload: the server's imports are only system frameworks (including Security, CommonCrypto and CryptoKit, per [Mac App Store sandbox](design/mac-app-store-sandbox.md#app-review)), and it serves plain HTTP on loopback, but the .NET runtime's cryptography hasn't been formally assessed for export compliance.

## Containers

The release workflow builds the supplied Dockerfile on native Linux amd64 and arm64 runners after Quality and Dependency Audit pass. Each image is checked with its default nonroot user, read-only root filesystem, dropped capabilities, a persistent volume, health checks, restart and graceful shutdown. The checked image bytes are kept with checksums as artifacts; the publication job loads those exact images rather than rebuilding them.

The `Publish verified container` job runs only after the draft release exists and both images passed, requires `release-publish` approval (the same review that publishes the draft), and alone has `packages: write`. It validates the complete file sets and checksums before any registry write, then pushes architecture images and a combined multi-platform manifest to `ghcr.io/OWNER/REPOSITORY/server`, using the ephemeral GitHub token. It records a build provenance attestation for the manifest digest in the registry and on GitHub. The package inherits its repository association from the OCI source label; check repository access and set the package visibility to public during activation if anonymous installs are intended.

Tags include the version, workflow run ID and attempt, such as `v0.1.0-123456-1`, so another attempt never replaces a distributed tag. There is no moving `latest` tag. The job summary records the immutable `ghcr.io/OWNER/REPOSITORY/server@sha256:…` installation reference. Copy that actual reference into the release notes after publication; never fabricate an image digest. GitHub tag protections do not make registry tags immutable, so deployments should pin the digest. Verify an image with `gh attestation verify oci://ghcr.io/OWNER/REPOSITORY/server@sha256:… --repo OWNER/REPOSITORY`.

For either local-network or Tailscale Compose installation, set `JOURNAL_IMAGE` to that digest reference, then use `docker compose -f deploy/compose.yaml pull journal` and `docker compose -f deploy/compose.yaml up -d --no-build` (substitute `deploy/compose.tailscale.yaml` for the Tailscale setup). The persistent named volume is unchanged during image upgrades. Back up before upgrades and review migration compatibility before downgrading.

Registry publication is not atomic with the release publication. A failure can leave architecture images without a combined manifest, or a published image while the release publication job fails. Inspect the failed run; do not advertise a digest until manifest publication succeeds. A rerun gets a fresh attempt tag. The cleanup step removes Docker credentials even after a failed publication. No image is published by local packaging or pull-request checks.

## Current evidence

Workflow syntax (actionlint with ShellCheck), shell checks, formatting, secret scanning, release staging and TestFlight credential validation for iOS and Mac profiles pass locally. Staging tests exercise a complete synthetic set and refusal of missing, altered, extra or symlinked inputs, including a leftover Mac download. A local `JOURNAL_SIGNING_TEAM=<team> JOURNAL_BUILD_NUMBER=2 scripts/archive-mac.sh` run produced a universal archive with the Apple silicon server, build number 2 and the designed entitlements, and a development export of it (`xcodebuild -exportArchive`, method `debugging`, automatic signing) signed the app, connector, server and its library with the team identity, kept each one's entitlements, and embedded a profile only in the app. A local `JOURNAL_SIGNING_TEAM=<team> JOURNAL_BUILD_NUMBER=2 scripts/archive-ios.sh` run with Xcode 26.6 produced an archive signed with an Apple Development identity and team profile, with GRDB's resource bundle built without a signing error and left unsigned inside the sealed app, and build number 2. Distribution signing, protected environments, artifact transfer, attestations, exporting an unsigned iOS archive, App Store Connect upload and publication have not run yet.
