# Distribution and installation

My Journal has no public release yet. This page describes the planned distribution channels, the supported systems, how packages are built and signed, and what to know when installing or updating. Maintainer steps for publishing a release are in [release operations](release-operations.md).

## Channels

| Product | Channel | Built by |
| --- | --- | --- |
| iPhone and iPad app | TestFlight, then the App Store | TestFlight workflow (signed at export and uploaded to App Store Connect) |
| Mac app (one purchase with iPhone and iPad) | TestFlight, then the Mac App Store | TestFlight workflow (sandboxed; signed at export and uploaded to App Store Connect) |
| Server for Linux (x64 and Arm64, glibc) | Self-contained archives on GitHub Releases | Release workflow |
| Server container (amd64 and arm64) | GitHub Container Registry, referenced by digest | Release workflow |

The Mac app is only distributed through the Mac App Store, so it runs in the App Sandbox; see [Mac App Store sandbox](design/mac-app-store-sandbox.md). Every GitHub release asset comes with a SHA-256 checksum and a build provenance attestation. The **Package Builds** workflow, which runs only when started manually, builds unsigned development packages as short-lived workflow artifacts; these are for testing, not distribution.

## Supported systems

- The app runs on macOS 14 or later (Apple silicon and Intel) and iOS/iPadOS 16 or later. The apps are only clients; none of them includes a server.
- The standalone server runs on glibc-based Linux (x64 and Arm64) and on macOS 14 or later, the minimum for [.NET 10](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md). It includes its own .NET runtime. It is not built for Alpine or other musl-based systems; use the container there.

## Setup choices

- **This device only.** Install the app and create a journal. No server is needed. Encryption is on by default and uses a master password; save it in your password manager. If you turn encryption off, anyone with access to the files, a server or a backup can read your journals.
- **Your own server.** Run the container or a standalone server on a computer you control that stays on, such as a home server, a NAS, a VPS, or a Mac or PC with Docker, then choose Connect to a Server… in Settings > Sync. See [self-hosting](self-hosting/README.md), including [running the server on a Mac](self-hosting/README.md#running-the-server-on-a-mac).

Earlier TestFlight builds of the Mac app could run a server inside the app (Use This Mac). A Mac connected to that server stops syncing once, the first time a newer build opens, and keeps its journals; Settings > Sync explains it. The app never deletes that server's files (`local-server.json`, `local-server-process.json`, `local-server.log` and `local-server-data`), not even with Erase Journals and Settings, because they may hold the only copy of changes another device sent. The guide explains [moving to another server and recovering from those files](guide/troubleshooting.md#if-you-used-use-this-mac).

## Updating

Updates replace the app or server binaries; journals in Application Support and server data directories are kept. Back up before updating: Export Archive in Settings > Backup for the app, `--backup` for the server. Keep the master password separate from backups. The app and the server refuse to open data written by a newer version and leave it unchanged, so install that version or later rather than downgrading; to go back, restore a backup made with the older version. Before migrating an existing database, the server keeps a copy as `journal.pre-migration.db` in its data directory. The app has no automatic updater outside the App Store.

## Building packages locally

Use the pinned tools and Xcode 26.6 (see [development](development.md)). Each command needs a new output directory:

```sh
mise exec -- scripts/package-mac.sh arm64 artifacts/mac-arm64
mise exec -- scripts/package-mac.sh x86_64 artifacts/mac-x86_64
mise exec -- scripts/package-server.sh linux-x64 artifacts/server-linux-x64
JOURNAL_VERSION=1.2.0 mise exec -- scripts/package-server.sh linux-arm64 artifacts/server-linux-arm64
mise exec -- scripts/archive-ios.sh artifacts/ios-archive
JOURNAL_SIGNING_TEAM=<team-id> mise exec -- scripts/archive-mac.sh artifacts/mac-archive
```

- `package-mac.sh` builds `My Journal.app` for one architecture and a development disk image with a checksum. The app is sandboxed, ad-hoc signed and not notarized, so it is only for testing on your own Mac. The Mac App Store plan, including the sandbox, is in [Mac App Store sandbox](design/mac-app-store-sandbox.md).
- `package-server.sh` builds a self-contained server folder with the `journal-server` launcher, a README, the license and the third-party notices. It needs no installed .NET. `JOURNAL_VERSION` (for example `1.2.0`, without a leading `v`) sets the version GET /v1/server reports; without it the server reports `0.0.0-dev`. Release builds set it from their tag.
- `archive-ios.sh` builds `My Journal.xcarchive`, an unsigned device archive that can't be installed until it is signed at export. `JOURNAL_BUILD_NUMBER` sets its build number.
- `archive-mac.sh` builds the Mac App Store archive: the universal app for Apple silicon and Intel. It needs no signing credentials; the app is signed to run locally so the archive records its entitlements, and the export signs it again for distribution. `JOURNAL_SIGNING_TEAM` is required because the app group and keychain group start with the team ID. `JOURNAL_BUILD_NUMBER` sets the build number. The script also removes the signatures of resource bundles, which App Store Connect rejects, and checks the entitlements and privacy manifest, so use it for every Mac upload.
- `python3 scripts/test-packaged-server.py <server-folder>` starts a packaged server with a disposable data directory and no system .NET, checks readiness and requires a clean shutdown.

## Signing

App Store signing runs in the TestFlight workflow on GitHub-hosted runners with credentials from a protected environment. Locally:

- `JOURNAL_SIGNING_TEAM=<team-id> [JOURNAL_BUILD_NUMBER=<n>] scripts/archive-ios.sh <new-output-directory>` archives with automatic signing through the Xcode account for that team. It sets only the signing style and team, never a profile or identity, which would also apply to Swift package resource bundles.
- `scripts/export-ios.sh <My Journal.xcarchive> <ExportOptions.plist> <new-output-directory>` exports a signed or unsigned archive with options you review (method `app-store-connect`, `release-testing` or `debugging`; local export only). Keep `ExportOptions.plist` outside the repository; it names your team.
- For the Mac, open the archive from `archive-mac.sh` (`open "artifacts/mac-archive/My Journal.xcarchive"` adds it to Xcode's Organizer as My Journal) and choose Distribute App > App Store Connect with automatic signing. Xcode signs every nested executable again and keeps its entitlements.
- The TestFlight workflow archives both apps without signing credentials, then signs and uploads each at export; see [release operations](release-operations.md#testflight).

Mac builds signed with a team or App Store provisioning profile keep keys in the data protection keychain, in the keychain group they share; ad-hoc builds use the login keychain. The Mac app keeps journals in its sandbox container: `~/Library/Containers/io.github.ralphkrauss.myjournal/Data/Library/Application Support/PrivateJournal`.
