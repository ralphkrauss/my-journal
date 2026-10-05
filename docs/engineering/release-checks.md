# Release checks

Before each TestFlight build, one command verifies the working tree and can archive both apps from it:

```sh
mise exec -- scripts/release-check.sh --plan                 # what it would run, and why
JOURNAL_SIGNING_TEAM=<team> JOURNAL_SIGNING_IDENTITY="Apple Development: …" \
  mise exec -- scripts/release-check.sh --archive <build-number>
```

`scripts/check.sh release …` is the same command. Uploading stays a separate step ([release operations](../release-operations.md)).

Until October 2026 every lane ran one after another before each build: hygiene, lint, audit, backend, JournalCore, Mac tests, the four sync and server lanes, the iOS unit and UI lane, the sync recovery UI lane, then both archives. The release check keeps the same lanes and the same pass criteria. It saves time in three ways: lanes that don't depend on each other run side by side, lanes that the changes can't affect are left out, and the archives are built while the last simulator lane runs.

## What runs at the same time

```text
gate     hygiene, lint, generate project  |  backend, publish server once      (side by side)
then     host: sync-health, sync, core, mac, sync-efficiency, audit             (one after another)
         simulator: server-recovery, ios-ui, recovery-ui                        (one after another)
then     archive: iOS, then Mac — starts once ios-ui and the host lanes passed, beside recovery-ui
```

- At most one simulator lane runs at a time, and at most two heavy processes overlap: the simulator lane and one host lane, or the simulator lane and one archive. Xcode builds keep `-jobs 2`. On a Mac short on memory, `--serial` runs one lane at a time in the same order.
- The Mac tests use `artifacts/DerivedDataMacTests`, so they build beside the lanes that share `artifacts/DerivedData` (server-recovery, ios-ui and recovery-ui, which therefore run one after another). The archives use their own derived data.
- The backend lane builds the server before any lane starts one, so lanes never build the same .NET project at once. The server is published once and given to the lanes that accept a published server (`JOURNAL_SERVER_PACKAGE`).
- server-recovery and recovery-ui wait for sync-health, because all three take servers' ports from the fixed loopback range 18950–18959.

The first failure stops everything: the other lanes are interrupted as Control-C would, so lane scripts stop their servers and restore simulator settings. The check prints when each lane starts, passes or fails, the failed lane's log, and at the end a table of lane times with the total and the time the same lanes take one after another. Logs of the five newest runs stay in `artifacts/release-check/runs`; result bundles are kept only when a run fails.

The check records the exact tree it started from, including uncommitted and untracked files. If the sources change during the run, it fails, because the results and archives would not describe one tree.

## Which lanes a change needs

The check compares the tree with the last tree that passed on this Mac (`artifacts/release-check/history.tsv`), or with the latest "Build N" commit if none is recorded. `--base <commit>` compares with another commit. Hygiene (secret scan, scripts, release guards) and the dependency audit (advisories appear without changes) always run.

| Changed | Lanes |
| --- | --- |
| `protocol/`, JournalCore sources (sync, storage, crypto), `Package.swift`/`Package.resolved`, `mise.toml`, `mise.lock`, `global.json`, any path without a rule | Every routine lane (a full run) |
| JournalCore tests or `JournalMeasure` | core |
| `JournalProbe` | core and the three sync lanes |
| `server/` sources, `Directory.Build.props`, `.editorconfig` | backend, the three sync lanes, server-recovery, recovery-ui, and the UI tests that use a server: pairing, connection setup, agent access, merge |
| `server/tests/` | backend |
| App code (`apps/apple/JournalApp/`), `project.yml`, `generate-apple.sh` | lint, mac, server-recovery, every iOS unit and UI test, recovery-ui |
| Mac-only code (`JournalApp/Views/Mac`, `MacResources`, `Signing`, `JournalServerTests`) | lint, mac, server-recovery |
| Shared unit tests (`apps/apple/JournalTests/`) | lint, mac, the iOS unit tests |
| A UI test file holding only test classes | lint and those classes (`SyncRecoveryUITests` runs in recovery-ui) |
| Another UI test file (shared helpers) | lint, every iOS unit and UI test, recovery-ui |
| A lane's own script | that lane; `prepare-simulator.sh` and `verify-test-results.py` every simulator lane; `package-server.sh` and `packaging/` the lanes that publish a server; a new `scripts/test-*` file a full run |
| `scripts/check.sh` | lint, backend, core, mac |
| Docs, design, deploy, workflows, other scripts, opt-in lanes (Files, measurements, screenshots, sandbox, containers) | hygiene only |

Most app changes still need the whole iOS UI lane: the suite can't tell which journeys a view or editor change affects. The iOS app is compiled by the iOS UI lane whenever it runs and by the archive otherwise.

## Full runs

Every routine lane runs when `--full` is given, when the changes need it, when the last full run is more than 7 days old or 5 selective runs back, when Xcode changed since the last full run, and when there is nothing to compare with. Before the first recorded run, the latest "Build N" commit counts as a full run, because every lane ran before each of those builds.

The accessibility lane (`test-native-accessibility.sh`) and the opt-in lanes stay outside routine release checks, as before; CI runs the accessibility lane on every pull request. `test-mac-sandbox.sh <team-id>` remains a separate step before a Mac upload, because it needs the team's signing identity. `--lanes a,b` runs exactly the named lanes, for example after fixing one failure; such a run is not recorded as a verification.

## Expected times

Measured on the owner's Mac with warm build caches on 2 October 2026 (before the UI-lane speed work):

| Lane | Time |
| --- | --- |
| Gate: hygiene, lint, backend, publish server | about 1.5 min |
| Host lanes together | about 7–8 min |
| server-recovery | under 1 min |
| ios-ui (60 tests, about 41 min running tests) | about 45 min |
| recovery-ui | about 4.7 min |
| Both archives, one after another | about 3 min |

| Build | One after another | Release check |
| --- | --- | --- |
| App change (typical) | about 60 min warm, 75–90 min with cold caches | about 52 min, almost all of it the iOS UI lane |
| Server change only | about 60 min | about 17 min |
| One UI test class changed | about 60 min | about 8 min plus that class |
| Docs only | about 60 min | about 4 min (hygiene, audit, archives) |

The iOS UI lane is the critical path: every minute saved there shortens a typical release check by a minute.

## Constraints for lane and build changes

- The simulator lanes and server-recovery share `artifacts/DerivedData`, so they can't overlap. If a lane gets its own derived data path, the release check can move it to another track.
- server-recovery publishes its own server and doesn't accept `JOURNAL_SERVER_PACKAGE`.
- The archives run beside recovery-ui only because they use their own derived data. If an archive script starts sharing `artifacts/DerivedData`, the archives have to wait for recovery-ui.
