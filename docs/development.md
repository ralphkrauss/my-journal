# Development

This page explains how to build and run My Journal from source and which checks to run before opening a pull request. See [architecture](architecture.md) for how the code is organized and [code hygiene](engineering/code-hygiene.md) for the rules the checks enforce.

## Prerequisites

- A Mac with **Xcode 26.6**. The Apple checks require the swift-format version bundled with it (6.3.0). The scripts use the Xcode selected with `xcode-select`; set `DEVELOPER_DIR` to use another.
- **[mise](https://mise.jdx.dev)**. It installs the pinned tools from `mise.toml` and `mise.lock`: the .NET SDK (the version in `global.json`), XcodeGen, SwiftLint, ShellCheck, shfmt, actionlint, Gitleaks and Ruff.
- Python 3 (the system `python3` is fine) for the helper scripts.
- Docker, only for the container and HTTPS deployment checks.

From the repository root:

```sh
mise trust
mise install --locked
```

Run commands through `mise exec --` so they use the pinned versions.

## Mac and iOS apps

The Xcode project is generated and not committed. Generate it after cloning and whenever `apps/apple/project.yml` changes:

```sh
mise exec -- scripts/generate-apple.sh
open apps/apple/Journal.xcodeproj
```

Choose the **My Journal (Mac)** or **My Journal (iOS)** scheme. My Journal (iOS) runs on iPhone and iPad simulators. To run on your own device, select your team in Signing & Capabilities; do not commit that change.

The Mac app runs in the App Sandbox in every build ([Mac App Store sandbox](design/mac-app-store-sandbox.md)). A development build uses your normal library, which is in the app's container: `~/Library/Containers/io.github.ralphkrauss.myjournal/Data/Library/Application Support/PrivateJournal`. To keep test data separate, add the environment variable `JOURNAL_DATA_DIR` with a folder of your choice in Product > Scheme > Edit Scheme > Run > Arguments; on the Mac it must be inside that container, and agent access doesn't work with it. Use synthetic content when testing. Unit tests that run inside the app use a new temporary data folder and keep keys in memory; UI tests give the app its own data folder but use the simulator's Keychain.

### Team-signed Mac build

Unsigned or ad-hoc-signed Mac builds keep their keys in the login keychain, which can ask for your password after each rebuild. For day-to-day testing, build a copy signed with your own team instead:

```sh
mise exec -- scripts/build-mac-development.sh <team-id>
```

It uses `apps/apple/Signing/JournalMac-Development.entitlements`, so keys live in the data protection keychain and rebuilds don't prompt. Xcode must be signed in to the team's Apple Account; the first build registers the Mac as a development device. The script prints the path of the built app. A sandboxed app can only start a server inside its bundle, so to try Use This Mac…, publish a server first and pass its folder:

```sh
mise exec -- scripts/package-server.sh osx-arm64 artifacts/local-server
mise exec -- scripts/build-mac-development.sh <team-id> Debug artifacts/local-server
```

`mise exec -- scripts/test-mac-sandbox.sh <team-id>` checks the sandboxed configuration: the bundled server and the data protection keychain. It needs the same team signing, so it runs locally, not in CI.

## Server

Run the server from source with a disposable data directory:

```sh
Journal__DataDirectory="$PWD/artifacts/dev-server" ASPNETCORE_URLS=http://127.0.0.1:8080 \
  mise exec -- dotnet run --no-launch-profile --project server/src/Journal.Api
cat artifacts/dev-server/setup-code
```

In the app, open Settings > Sync, choose Connect to a Server…, enter `http://127.0.0.1:8080` and the setup code. Plain HTTP is accepted only for loopback addresses; the iOS simulator can use the same address. The setup code file is removed after setup. Delete `artifacts/dev-server` to start again.

To run the container instead, see [self-hosting](self-hosting/README.md).

## Checks

Format before committing:

```sh
mise exec -- scripts/format.sh
```

Then run the lanes that match your change. CI runs all of them on every pull request.

| Lane | Command | Run it when you change |
| --- | --- | --- |
| Hygiene | `mise exec -- scripts/check.sh hygiene` | Shell or Python scripts, workflows, packaging, or anything that could contain a secret. It also runs Gitleaks. |
| Backend | `mise exec -- scripts/check.sh backend` | Anything under `server/`. Locked restore, formatting, analyzers and API tests. |
| Apple | `mise exec -- scripts/check.sh apple` | Swift code or `project.yml`. Format and lint, JournalCore tests, Mac tests and an iOS simulator build. |
| Audit | `mise exec -- scripts/check.sh audit` | Dependencies. Needs network access. |
| All | `mise exec -- scripts/check.sh all` | A large change. |
| Release | `mise exec -- scripts/release-check.sh` | Before a TestFlight build. Runs the lanes and end-to-end checks the changes need; see [release checks](engineering/release-checks.md). |

Optionally install the Git hook, which runs the hygiene lane before each commit:

```sh
git config core.hooksPath .githooks
```

## End-to-end checks

These are slower. In CI, the sync and local server checks run in the Integration job, the iOS unit and UI tests in the iOS UI job, and the accessibility flows in the iOS Accessibility job. Run the ones related to your change.

| Command | What it covers |
| --- | --- |
| `mise exec -- scripts/test-sync.sh` | A real server process and several Swift clients: sync, images, pairing, offline conflicts, recovery, revocation, backup and restore. Set `JOURNAL_TEST_RECOVERY_VERSION` (for example `2` for a password library or `4` for one without encryption) to test another library format. |
| `mise exec -- scripts/test-local-server.sh` | The server bundled in the Mac app: setup, restart, stop and recovery, using a freshly packaged server. |
| `mise exec -- scripts/test-native-pairing.sh` | The complete iOS unit and UI test scheme, including pairing through the app, against a disposable server. |
| `mise exec -- scripts/test-native-accessibility.sh` | Recovery and restoration flows at the largest text size in dark mode. |
| `mise exec -- python3 scripts/test-https-deployment.py` | The public HTTPS Compose example with a temporary local certificate authority. Needs Docker. |

The simulator checks boot a dedicated test simulator that holds only disposable data, and create it if needed (see `scripts/prepare-simulator.sh`). To use a specific simulator instead, set `JOURNAL_SIMULATOR_ID` to its identifier from `xcrun simctl list devices`.

The native test scripts fail when a test was skipped, when no test ran, or when a test named with `-only-testing` didn't run. Set `JOURNAL_TEST_RESULTS` to a new directory to keep result bundles and server logs.

The opt-in Files acceptance checks (`scripts/test-native-file-import.sh <new-output-directory>`) exercise image import and archive export and import through the system Files picker. They are not part of CI; run them when you change image import or archive delivery.

No check reads real journals or contacts a server you did not start.

## Packages

To build the Mac, iOS and server packages locally, see [distribution](distribution.md#building-packages-locally). For resource measurements, see [performance](performance.md).

## Design records

Changes to the interface need a design and an independent review before implementation; see [CONTRIBUTING.md](../CONTRIBUTING.md). Existing records and their status are listed in [design/README.md](design/README.md).
