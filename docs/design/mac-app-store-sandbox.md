# Mac App Store sandbox: prototype and plan

2026-09-27. Scope: run the Mac app, its bundled server and its agent connector in the App Sandbox so the Mac app can ship in the Mac App Store and Mac TestFlight. Findings STORE-12 and AGT-3.

## Decision and consequences in brief

The owner decided to sell My Journal once, with universal purchase across iPhone, iPad and Mac. Both apps use the bundle ID `io.github.ralphkrauss.myjournal` (team `776KB9Z56U`). Universal purchase needs the Mac app in the Mac App Store, and the Mac App Store and Mac TestFlight need every executable in the app to be sandboxed.

This prototype shows that the whole Mac app works sandboxed on macOS 26.3 with Xcode 26.6: the app, the bundled .NET server and the agent connector. It changes no interface. What the owner should know:

- **The Mac ships only through the Mac App Store and TestFlight.** The Developer ID disk image path (`sign-mac.sh`, `notarize-mac.sh`, the Mac job in `release.yml`) no longer matches the product. Updates come only from the App Store (guideline 2.4.5(vii)), so no Sparkle.
- **Data moves into the app's container.** The library is now in `~/Library/Containers/io.github.ralphkrauss.myjournal/Data/Library/Application Support/PrivateJournal`. A library at the old location moves there by itself the first time the sandboxed app opens (Apple's container migration, tested below). No public Mac release exists, so no customer data needs to move.
- **Agent connection files move to a shared app group container**, `~/Library/Group Containers/776KB9Z56U.io.github.ralphkrauss.myjournal/agent-connections`. Existing agent access starts empty once, and agents need new connection instructions. A connection file copied elsewhere no longer works, because the connector's own sandbox can't read it.
- **The server adds about 116 MB (Apple silicon only) or about 222 MB (Apple silicon and Intel).** The owner must choose; see "Intel" below.
- **Development builds are sandboxed too.** `JOURNAL_DATA_DIR` works only for a folder inside the container, renamed preview copies each get their own container, and the debug fallbacks to helpers in the repository can't run. Use `scripts/build-mac-development.sh <team> [configuration] [server folder]`.

## What changed

| Area | Change |
| --- | --- |
| `apps/apple/project.yml` | The Mac app is signed with `Signing/JournalMac.entitlements` in every build, through a new setting `JOURNAL_MAC_ENTITLEMENTS` so a script can switch only the app's entitlements. New `JournalAgent` command-line tool target (bundle ID `io.github.ralphkrauss.myjournal.agent`, Info.plist embedded in the binary, own entitlements), embedded in `My Journal.app/Contents/Helpers` by every Mac build. `MacResources/container-migration.plist` in the Mac app's resources. New `JournalMacSandboxTests` target and `JournalMacSandbox` scheme. Both apps use `io.github.ralphkrauss.myjournal`. |
| `apps/apple/Signing/` | `JournalMac.entitlements` (sandbox, no restricted entitlements, for builds without a provisioning profile such as tests and CI), `JournalMac-Development.entitlements` (the same plus the data protection keychain group, for team-signed builds and the App Store archive), `JournalAgent.entitlements`. |
| `packaging/server-sandbox.entitlements` | The server helper: exactly `app-sandbox` and `inherit`. |
| `JournalApp/Model/SharedContainer.swift`, `AppModel.swift`, `AgentController.swift` | The app finds its app group container from its own entitlements. The default library keeps `agent-connections` there; test and `JOURNAL_DATA_DIR` libraries keep it in their data folder. A build without the group (unsandboxed) is unchanged. |
| `scripts/assemble-mac-server.sh`, new `scripts/embed-mac-server.sh` | Build `JournalServer.app` (bundle ID `io.github.ralphkrauss.myjournal.server`), sign it with the app's identity and the inherit entitlements, and sign the app again with its own entitlements and profile. |
| `scripts/build-mac-development.sh`, `scripts/package-mac.sh` | Team-signed development build with an optional server; the development disk image keeps the Xcode-built sandboxed connector instead of a separately built, unsandboxed one. |
| New `scripts/test-mac-sandbox.sh`, `scripts/drive-agent-connector.py` | A separate local lane: a team-signed sandboxed test host with the server embedded, the local server tests, a keychain check, and the agent connector started from outside the app as an agent starts it. |

## Entitlements

| Executable | Entitlements | Why |
| --- | --- | --- |
| `My Journal.app` | `app-sandbox`, `network.client` (sync, readiness probe), `network.server` (agent bridge listener and, inherited, the server's Kestrel listener; both bind only 127.0.0.1), `files.user-selected.read-write` (Import/Export Archive, Insert Image panels), `application-groups` = `$(TeamIdentifierPrefix)io.github.ralphkrauss.myjournal`, and in provisioned builds `keychain-access-groups` = `$(AppIdentifierPrefix)org.privatejournal.vault` (unchanged). | |
| `Contents/Helpers/journal-agent` | `app-sandbox`, the same `application-groups`, `network.client`. Hardened runtime. Info.plist in `__TEXT,__info_plist`. | Agent apps start it, so it can't inherit My Journal's sandbox. |
| `Contents/Helpers/JournalServer.app` | Exactly `app-sandbox` and `inherit`. No hardened runtime. | My Journal starts it; it runs in the app's sandbox. |

No temporary exception entitlements are used. The Mac App Store doesn't require the hardened runtime.

### App group identifier

The group is macOS style, `776KB9Z56U.io.github.ralphkrauss.myjournal`, not iOS style (`group.…`):

- Apple documents both formats on macOS, and that the Team-ID-prefixed format needs no registration ([App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)).
- The connector is a bare command-line tool and can't carry a provisioning profile. An iOS-style group must be authorized by a profile. From macOS 15, a process reaches a group container without a prompt only if it is from the Mac App Store, from TestFlight (macOS 15.1 and later), uses a group that starts with its Team ID, or has the group authorized by its profile. The Team-ID prefix holds in development, TestFlight and App Store builds alike ([Quinn, "App Groups: macOS vs iOS: Working Towards Harmony"](https://developer.apple.com/forums/thread/721701)).
- Mac App Store submission accepts group IDs that "either start with your Team ID (macOS style) or are assigned to your team (iOS style)" (same post).
- Only the Mac uses the group, so the iOS-style format's cross-platform advantage doesn't apply.

Apple notes that an app group claim not authorized by the provisioning profile clears the "entitlements validated" flag, which historically disabled the data protection keychain; profiles for App IDs with the App Groups capability now authorize `TEAM_ID.*` (same post). The development builds here use the team's wildcard profile, which doesn't list app groups, and the data protection keychain still works (`SandboxKeychainTests`, below). To be safe, enable the App Groups capability on the App ID before the first App Store upload so its profile authorizes the group.

## Data locations

- **Library**: Application Support inside the app's container. The code is unchanged; `FileManager` returns the container path when the app is sandboxed.
- **Agent connections** (grant store, connection files, `bridge.json`): `agent-connections` in the app group container, because the connector's own sandbox can't read the app's container. Only this folder is shared, not the library, so a compromised connector can't read the encrypted database, the configuration file (PIN verifier) or the server's data. The helper is launched with arguments from another app, so it gets the smallest access that works.
- **Server data** stays in the library folder; the server inherits the app's sandbox and needs nothing shared.

The agent access key's Keychain name is derived from the folder path, so it changes with the move. The existing "unreadable permissions" rule applies: agent access starts empty and can be granted again ([agent access contract](../../protocol/agent-access-server.md)). An old `agent-connections` folder that moves with the library stays where it is; its tokens no longer grant anything.

## Migration

### Options

- **Container migration** (`container-migration.plist` with `Move`, [Apple](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container)): macOS moves the listed folder into the container when it creates the container, before the app runs. No entitlement, no interface, no App Review question.
- **One-time import by the app**: reading `~/Library/Application Support/PrivateJournal` from the sandbox needs either a temporary exception entitlement, which App Review questions and may refuse, or an open panel the person must use (a new interface through the design gate).

The container migration is the safer choice and is implemented. What it does was measured on macOS 26.3 with a throwaway sandboxed app (`org.privatejournal.migrationprobe`) and synthetic files:

- The folder was **moved**, not copied: the source was gone, no symbolic link was left, and file contents, a nested folder and a symbolic link inside it arrived intact. Apple's current page says "copy", so don't rely on either; the app must work in both cases, and it does, because the old location is only read by unsandboxed builds.
- It runs **only when the container is created**. A second launch with a new folder at the source moved nothing.

### Consequences to plan for

- Libraries created before the Keychain key's name was saved in the configuration found the key by the library's path. The app saves the name the first time a current build opens the library (`rememberKeyAccount`). A library never opened by a current build would, after the move, ask for its master password or recovery key once; nothing is lost. The same applies to the sync connection's Keychain item.
- Keys created by team-signed builds live in the data protection keychain group `776KB9Z56U.org.privatejournal.vault`, which the sandboxed app shares, so they keep working. Keys created by a Developer ID or ad-hoc build are in the login keychain, bound to that build's signature; the sandboxed app would ask for the login keychain password or fail and fall back to the master password (as STORE-12 item 4 describes). No such build was released.
- Quit any older copy of My Journal before the first sandboxed launch. A running unsandboxed copy would keep writing to the moved files and create new ones at the old path.
- Any sandboxed build with the same bundle ID creates the container, including the unit test host. On a developer's Mac the first sandboxed test run moves that developer's own library into the container; unsandboxed builds then no longer find it. It isn't lost.
- On this Mac the container for `io.github.ralphkrauss.myjournal` already exists (created by these tests), so migration won't run here again. `~/Library/Application Support/PrivateJournal` doesn't exist on this Mac; the owner's preview copies keep their data in their own folders.

### Plan for existing data

1. Customers: none on the Mac. The Mac App Store is the first Mac channel. The migration manifest stays in the app for anyone who used a development build at the default location.
2. The owner's development and preview data: use Export Archive in the old build and Import Archive in the sandboxed build. Archives are the supported portable format. Alternatively, with both apps quit, move the `PrivateJournal` folder into the container's `Application Support` by hand; team-signed keys keep working.
3. Local server: its settings and data move with the library, so "Use This Mac" keeps its server identity and devices. Other devices keep syncing because the port and data are unchanged.

## The bundled server

`JournalServer.app` (self-contained single-file .NET 10 server, 116 MB for Apple silicon) sits in `Contents/Helpers`, signed with only `app-sandbox` and `inherit` and without the hardened runtime, as Apple describes for helper tools ([Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)). CoreCLR's JIT, Kestrel on 127.0.0.1, EF Core with SQLite in the container, `--recovery-code`, the parent-process watchdog (`Process.GetProcessById` on the app) and stopping with SIGTERM all work in the inherited sandbox. No code change was needed; `LocalServerController` already passes the data folder and URLs in the environment.

Measured variants:

| Variant | Result |
| --- | --- |
| `app-sandbox` + `inherit`, no hardened runtime (chosen) | All 4 local server tests pass, also with the test host's read exception removed. |
| Same, started directly from a shell | Crashes at launch (exit 133). An inherit-only helper can't be started by anyone but the app. |
| Hardened runtime + `inherit`, no JIT entitlement | The server doesn't start ("Couldn't start the server…"); one local server test run. |
| Hardened runtime + `inherit` + `cs.allow-jit` | The same test passes, although Apple warns against extra entitlements on an inheriting helper. Only relevant for a sandboxed Developer ID build. |
| osx-x64 server under Rosetta, inherited sandbox | All 4 local server tests pass. Real Intel hardware not tested. |
| `lipo` of the arm64 and x64 single-file servers (222 MB) | Serves `/ready` on both architectures. In the sandbox (arm64 slice) 3 of 4 passed on the first run; the resume test timed out waiting for readiness once and passed on two reruns. Microsoft doesn't document universal single-file apps. |

### Intel

The Release app is universal (arm64 and x86_64). The server is built per architecture. Options for the owner:

1. Apple silicon only: 116 MB. On an Intel Mac, "Use This Mac…" can't start a server and needs a clear message (a design-gate item). macOS 26 is the last macOS release for Intel Macs.
2. Universal with `lipo`: 222 MB, works in these tests, not a documented .NET configuration; needs a run on a real Intel Mac and the full server lane.
3. Two server bundles (`JournalServer-arm64.app`, `JournalServer-x64.app`) and a choice by architecture in `LocalServerController`: 232 MB, documented configurations only, small code change.

## The agent connector

`journal-agent` is now an Xcode command-line tool target embedded by every Mac build, so App Store archives, development builds and tests all carry a correctly signed copy. It has its own `app-sandbox`, the app group and `network.client`, and an Info.plist inside the binary (`CREATE_INFOPLIST_SECTION_IN_BINARY`). The MCP contract, the connection file format and the bridge are unchanged.

Measured:

- Without an embedded Info.plist, a sandboxed command-line tool started from a shell crashes at launch (exit 133). With it, the tool runs sandboxed with its own container named after its identifier (`~/Library/Containers/io.github.ralphkrauss.myjournal.agent`), reading its user's files is refused (`Operation not permitted`), and system files such as `/etc/hosts` stay readable.
- End to end (`AgentConnectorSandboxTests` with `drive-agent-connector.py`): the sandboxed app creates a grant for one of two journals, with the connection files in the app group container. The driver, which like an agent app is neither sandboxed nor started by My Journal, starts the bundled connector and gets: `initialize` (protocol 2025-11-25), `tools/list` (the three tools), `list_journals` (only the shared journal), `read_entry` of a shared entry (its text), `read_entry` of an entry in the unshared journal (`isError`, "Not found, or not shared with this connection."). The same connector given a well-formed connection file outside the group container exits with status 1: its sandbox refuses the read. After the app revokes the grant, the still-running connector answers `list_journals` with `isError` "Access unavailable…", and it exits 0 when its input closes.

Building for testing gives every sandboxed target XCTest's exceptions, including read access to every file (`temporary-exception.files.absolute-path.read-only` = `/`). The first run failed its confinement check because of that: the connector could read a file outside the group container. The lane now signs the connector as it ships and removes the read exception from the test host too; all tests pass that way.

## Signing, archive and export

- Development: automatic signing with team `776KB9Z56U`. Xcode used "Mac Team Provisioning Profile: *" and needed no new capability; `REGISTER_APP_GROUPS=YES` changes nothing for a macOS-style group.
- Release archive (`xcodebuild archive`, universal): the connector is embedded and signed with its entitlements, no stray copy (`SKIP_INSTALL`). After `embed-mac-server.sh` added the server to the archived app, `xcodebuild -exportArchive` (method `debugging`) re-signed every nested item (app, connector, server, `libe_sqlite3.dylib`) and kept each item's own entitlements; `get-task-allow` was removed from the app. App Store export uses the same step with a distribution certificate. None was created, and nothing was uploaded.
- `codesign` fails with "internal error in Code Signing subsystem" when the disk has less free space than about twice the 116 MB server binary.

## Verification evidence

All on macOS 26.3 (25D125), Xcode 26.6, Apple silicon, signed with "Apple Development: Ralph Krauss (5LNR83Y25W)" unless noted.

| Check | Result |
| --- | --- |
| `mise exec -- scripts/test-mac-sandbox.sh 776KB9Z56U` | 6 of 6 tests passed: agent connector end to end, data protection keychain, 4 local server tests. Test host without XCTest's read exception. |
| Mac unit tests, sandboxed test host, manual Apple Development signing | 121 passed. |
| Mac unit tests, ad-hoc signing (as `check.sh apple` in CI) | 121 passed. |
| `scripts/test-local-server.sh` (the CI Integration lane, ad-hoc sandboxed test host, unbundled server from a temporary folder) | 4 passed. With XCTest's read exception removed from the same test host, starting that unbundled server fails ("The file “Journal.Api” doesn't exist.") while the bundled server passes: only the test exception makes this lane work, so it doesn't test what ships. |
| JournalCore tests (`swift test`, strict concurrency, warnings as errors) | 126 passed. |
| iOS simulator build | Succeeded. |
| Release archive, server embedded, development export | Succeeded; nested signatures as above. |
| `scripts/package-mac.sh arm64` | Built and verified; app 138 MB, disk image 59 MB. |
| Format, strict SwiftLint, `scripts/check.sh hygiene` | Passed. |

Not verified, because the owner declined screen control of the app or because it needs a distribution certificate or other hardware:

- The interface in the sandboxed app: onboarding, Import and Export Archive panels, Insert Image from a panel, dropping or pasting image files, opening an archive from Finder, Settings > Sync "Use This Mac…", and Settings > Agent Access. The model code behind them ran in the sandboxed test host. The panels and archive opening already use security-scoped access (`ArchiveView.swift`, `ImagePickerPresenter.swift`); dropped and pasted files depend on the system's sandbox extensions.
- Screen-lock notifications (`com.apple.screenIsLocked`) in the sandbox, which pause agent access. Locking the owner's screen wasn't acceptable.
- The container migration with the real bundle ID (the container already existed; the mechanism was measured with the probe app).
- App Store Connect processing: profile and app group validation, the nested-executable sandbox check (ITMS-90296), and the symbol scan of the .NET runtime.
- Real Intel hardware; macOS 13 to 15.
- Whether macOS asks before a third-party process, such as an agent with shell access, reads the app group container, and whether it asks when builds with different certificates (development, TestFlight, App Store) open the same container. Both would be system prompts, not app interface.

Test data left on this Mac by these runs, safe to delete: `~/Library/Containers/` `io.github.ralphkrauss.myjournal`, `io.github.ralphkrauss.myjournal.agent`, `org.privatejournal.journal`, `org.privatejournal.journal.agent`, `org.privatejournal.myjournal`, `org.privatejournal.myjournal.agent`, `org.privatejournal.migrationprobe`, `org.privatejournal.readprobe`; `~/Library/Group Containers/` `776KB9Z56U.io.github.ralphkrauss.myjournal`, `776KB9Z56U.org.privatejournal.journal`, `776KB9Z56U.org.privatejournal.myjournal`, `org.privatejournal.myjournal`. They contain only synthetic test data.

## App Review

Relevant guidelines ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), last updated June 8, 2026):

- **2.4.5(i)** sandboxed, and **2.5.2** "self-contained in their bundles, and may not read or write data outside the designated container area": met. Every executable is sandboxed; data is in the container and the app's own group container; no temporary exceptions.
- **2.4.5(ii)** "self-contained, single app installation bundles and cannot install code or resources in shared locations": met. The connector runs from inside the bundle; nothing is copied to `/usr/local/bin` or elsewhere. Agents are configured with the in-bundle path.
- **2.4.5(iii)** no code that runs at login or keeps running after quit without consent: met. The server starts only after the person chooses "Use This Mac…", stops when the app quits, and exits by itself if the app ends. The connector is started and ended by the agent app; while My Journal isn't running it only answers "unavailable". Say so in the review notes.
- **2.4.5(iv)** and **2.5.2** no downloaded or installed code: met. The server and its runtime are in the reviewed bundle; the .NET JIT compiles only code from the bundle.
- **2.4.5(vii)** updates only through the Mac App Store: no updater is included; keep it that way.
- **2.5.1** public APIs only: the server's imports are CoreFoundation, Foundation, Security (including deprecated Secure Transport functions used by .NET's TLS layer), Network, GSS, CryptoKit, CoreServices, CommonCrypto and libSystem; no private frameworks. Upload validation runs the real symbol scan. Deprecated Secure Transport may draw a warning.
- **2.3.1(a)** no hidden features: the local server and Agent Access must be described with specific steps in the review notes.
- **5.1.2(i)** sharing with third-party AI needs disclosure and explicit permission: Agent Access already requires an explicit grant per journal with that disclosure.
- Risk that App Review questions an embedded web server and a helper started by other apps: moderate. Both are reachable only through loopback, and both are optional. Fallbacks, from least to most work: ship without the server on the Mac (people use a separate server), remove the connector (a compile-time switch), or distribute the connector separately, as 2Do does with a Claude extension that talks to a socket in its app group container ([2Do MCP](https://www.2doapp.com/docs/macos/mcp/)).

Draft review notes (to be checked against the final interface):

> My Journal is a private, end-to-end encrypted journal. Syncing is optional and uses a server the person runs; no account is needed.
>
> Optional feature "Use This Mac" (Settings > Sync > Use This Mac…): runs the bundled journal server (Contents/Helpers/JournalServer.app, a sandboxed helper that inherits the app's sandbox) so the person's other devices can sync through their own private network. It listens only on 127.0.0.1, stops when the app quits, and never starts at login.
>
> Optional feature "Agent Access" (Settings > Agent Access): the person can give an AI assistant app on the same Mac, such as Claude Desktop, read-only access to chosen journals. The assistant app starts the bundled, separately sandboxed connector (Contents/Helpers/journal-agent). It reads only the connection file in the app's group container and talks to My Journal over loopback, and only while My Journal is open and unlocked. The person grants access per journal after a disclosure that a cloud assistant may send the content to its provider, and can revoke it at any time.
>
> To review: create a journal without a server, add an entry, then Settings > Agent Access > Add Access… shows the flow.

## Remaining risks

1. App Store processing of a standalone-sandboxed command-line tool with an app group but no profile. Apple's guide describes only inheriting helpers, and suggests an app-like wrapper for standalone executables that need a profile ([Signing a daemon with a restricted entitlement](https://developer.apple.com/documentation/xcode/signing-a-daemon-with-a-restricted-entitlement)). If validation refuses it, wrap the connector as `Contents/Helpers/My Journal Agent.app` with its own App ID and profile; the MCP command path changes.
2. The first App Store upload is the first real check of the profile, the group, the nested signatures and the symbol scan. Do it with TestFlight before any public release.
3. Universal server (see Intel).
4. Interface paths not exercised (list above). Test them by hand in a sandboxed build before the first TestFlight.
5. System prompts when switching between development, TestFlight and App Store builds on one Mac: not measured.
6. The server's size and start time; a cold start of the 222 MB universal binary once missed the 6-second readiness window.

## Design gate

This prototype changes no interface. The sandbox itself adds no permission prompt for the flows the tests cover. Items for the design gate when they are decided:

- An explanation in "Use This Mac…" if the server isn't available on Intel Macs.
- The server's start-failure message says the address may be in use for every failure, including a runtime that can't start. A more accurate message may help.
- Documentation of the new data and connection file locations (not interface).

## Next steps

1. Owner: choose the Intel option. Enable the App Groups capability on the App ID.
2. Done 2026-09-28: the Developer ID job, `sign-mac.sh`, `notarize-mac.sh`, `ci-mac-signing.sh`, `packaging/server.entitlements` and `packaging/mac-release-README.md` are retired. `scripts/archive-mac.sh` builds the archive (signed to run locally, so it records each executable's entitlements, with the server embedded), and the TestFlight workflow's Mac job exports it with method `app-store-connect` and uploads it with Apple Distribution and Mac Installer Distribution certificates from the `testflight` environment ([release operations](../release-operations.md#testflight)). Prepared, not run.
3. Done 2026-09-28: the debug fallbacks to repository paths in `LocalServerController.executable()` and `AgentController.instructions` are removed.
4. Done 2026-09-28: `docs/distribution.md`, `docs/release-operations.md`, `packaging/mac-README.md` and the lane list in `docs/engineering/code-hygiene.md`.
5. Run `scripts/test-mac-sandbox.sh` before each Mac TestFlight upload (it needs a team identity, so not in hosted CI), and walk through the interface paths above in a sandboxed build.
