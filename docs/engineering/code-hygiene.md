# Code hygiene and enforced checks

These rules apply to all code in the repository, including existing code. Formatting alone is not code quality; reviewers still assess understandable responsibilities, safe state transitions, cancellation, failure recovery, and the cost of dependencies and tests.

## Decisions and sources

| Guidance | Project decision | Enforcement |
| --- | --- | --- |
| [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): clarity at the point of use; clarity matters more than brevity. | Descriptive domain names, one statement per line, small focused operations. Avoid compressed multi-statement lines and force unwraps. | Official swift-format; SwiftLint correctness rules plus function complexity/size limits. Design/API review remains necessary. |
| [Swift concurrency migration guide](https://www.swift.org/migration/documentation/migrationguide/incrementaladoption/): adopt checking incrementally and make isolation boundaries explicit. | UI on MainActor, persistence in an actor, immutable Sendable networking, owned/cancelable asynchronous work. Swift 5 language compatibility with complete concurrency checking. | Strict compiler concurrency checking and warnings as errors. No unchecked Sendable declarations added just to silence a diagnostic. |
| [Official swift-format](https://github.com/swiftlang/swift-format): lint needs `--strict` to fail on warnings. | One checked-in format configuration and the formatter bundled with Xcode 26.6 (6.3.0). | Strict lint locally and in the Apple CI job; one command fixes formatting. |
| [Microsoft code analysis](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview) and [configuration](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-options): SDK analyzers identify correctness, reliability, security and performance issues. | Nullable references, .NET 10 recommended analyzers, compiler/analyzer warnings as errors, consistent EditorConfig. | Build fails; dotnet format verifies formatting and configured style. Generated EF migrations are explicitly marked generated. |
| [NuGet package auditing](https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages): audit direct and transitive dependencies during restore. | Audit all dependencies at every severity. Restore exact locked dependency graphs. Do not silently skip unavailable audit services. | Locked restore, NuGet audit warnings are errors; scheduled audit and dependency-update PRs. Swift source revisions are checked against [OSV](https://google.github.io/osv.dev/post-v1-querybatch/). OSV coverage is not exhaustive. |
| [GitHub Actions security guidance](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions): immutable action pins, least privilege, avoid untrusted expression interpolation and public-repository self-hosted runners. | Full commit SHA pins, read-only workflow tokens, no persisted checkout credentials, hosted ephemeral runners, no signing secrets in PR jobs. | actionlint, reviewed workflow files, required status-check ruleset, protected environments checked by the jobs that use them. |
| [ShellCheck](https://www.shellcheck.net/) and [shfmt](https://github.com/mvdan/sh): check shell semantics and format consistently. | Quoted paths, strict shell execution, explicit cleanup and failure propagation. | Both run on all maintained shell scripts and Git hooks. |
| [Ruff](https://docs.astral.sh/ruff/): Python linting and formatting. | Keep the small maintenance helpers clear; check imports, likely bugs, and formatting. | Pinned Ruff checks all Python helpers. |
| [Gitleaks](https://github.com/gitleaks/gitleaks): detect accidental credentials. | Redacted source scan. Exclude generated output and local test journals; never exclude an entire source directory. | Every hygiene run and PR. A single inline exception documents a CryptoKit parameter type falsely detected as a credential; no actual key is exempted. |
| [mise lockfiles](https://mise.jdx.dev/dev-tools/mise-lock.html): record tool versions and available integrity/provenance information. | Pin lint tools in mise.toml and keep mise.lock. Pin .NET in global.json and Xcode in the Apple workflow. | CI uses locked mise installation; SwiftPM/NuGet lockfiles are committed. Tools using platform installers, including mise's .NET backend, do not have the same artifact-checksum entries as Aqua tools; .NET uses Microsoft's release installer. |

The .NET release was checked against [Microsoft's official release metadata](https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json): SDK 10.0.401, runtime 10.0.12. The GitHub macOS 26 [runner manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) lists Xcode 26.6. Tool changes are deliberate dependency changes and require rerunning checks.

## Local workflow

Install Xcode 26.6 and mise, then from the repository root:

```sh
mise trust
mise install --locked
mise exec -- scripts/format.sh
mise exec -- scripts/check.sh all
```

Individual lanes:

- `hygiene`: shell correctness/format, workflow validation, redacted secret scan, and small checks of the release, signing and test-result guards and of the .NET version pins.
- `backend`: locked audited restore, formatter check, analyzer/compiler build, focused API tests.
- `apple`: Swift format/lint, core behavior tests with concurrency checking, native Mac tests and iOS simulator compilation.
- `audit`: fresh dependency audit; network failures fail the command.

Expensive, meaningful E2E checks are separate: `mise exec -- scripts/test-sync.sh`, `mise exec -- scripts/test-local-server.sh`, and `mise exec -- scripts/test-native-pairing.sh` (the complete iOS unit and UI test scheme against a disposable server; on an iPhone simulator it leaves out the iPad-only keyboard shortcut test, which would otherwise be reported as skipped). `mise exec -- scripts/test-mac-sandbox.sh <team-id>` checks the Mac App Store configuration (the sandboxed app with its bundled server, the data protection keychain and the agent connector started from outside the app); it needs the team's signing identity, so it runs locally before each Mac TestFlight upload, not in CI. The separate `mise exec -- python3 scripts/test-https-deployment.py` lane verifies the container proxy with a disposable, explicitly trusted local CA; it does not change system trust or open public ports. The separate `mise exec -- scripts/test-native-accessibility.sh` runs journal recovery, historical entry/settings restoration and synced-image description editing in dark mode at the largest Dynamic Type size, scrolls native controls, verifies the complete edited description after relaunch and cancellation of subsequent edits, checks the active field against the full keyboard input area (including predictions), captures visual evidence, and restores the simulator’s original appearance/text preferences even after failure. Passing interaction assertions does not replace screenshot or VoiceOver inspection. No tests access real journals or personal servers.

The native test scripts fail when a test was skipped, when no test ran, or when a test named with `-only-testing` did not run (`scripts/verify-test-results.py`), so coverage cannot disappear through a missing environment value or a stale test name. Set `JOURNAL_TEST_RESULTS` to a new directory to keep result bundles and server logs; CI uploads them when a job fails.

The simulator scripts use the simulator named by `JOURNAL_SIMULATOR_ID`. Without it, `scripts/prepare-simulator.sh` reuses or creates a dedicated "Journal Test iPhone 17" simulator on the iOS runtime matching the selected Xcode, the same device model CI uses, so personal simulators are never changed. It boots the simulator and marks the one-time keyboard tips as shown, because a fresh simulator's first text entry otherwise shows a tip that can take a test's taps. The scripts use the Xcode chosen with `xcode-select` unless `DEVELOPER_DIR` is set.

The optional local hook can be installed with `git config core.hooksPath .githooks`. It scans the staged changes for secrets, which can differ from the working tree, then runs the hygiene lane. Hooks are convenience checks and can be bypassed; required server-side checks are the enforcement boundary. In CI, the Hygiene job also scans the commits of a pull request, or the full history on `main`.

## CI and repository enforcement

Seven stable checks are required: Hygiene, Backend, Apple, Integration (sync and local server), iOS UI (iOS unit and UI tests with a disposable server), iOS Accessibility (recovery flows at the largest text size in dark mode), and Dependency Audit. The UI suites run as separate jobs because together they take longer than one job's time limit. Their timeouts are estimates from local test durations until the first hosted runs are measured; then set each to about 1.5 times the observed time. Quality runs for pull requests and pushes to `main`, and the Release workflow runs it again for a tag. The dependency audit also runs weekly so newly disclosed advisories are checked even without code changes. It has no path filter: a required check must report for every pull request. Package Builds (unsigned development packages) runs only on request.

Dependabot proposes NuGet updates for `/server`, Swift updates for the JournalCore package, container and Compose updates for `/server` and `/deploy`, and action updates. After the first NuGet update, confirm that both `packages.lock.json` files were regenerated, because CI restores in locked mode. The .NET version is pinned in several files that different tools update: the SDK in `global.json`, `mise.toml` and the Dockerfile build stage; the runtime in `Journal.Api.csproj` (`RuntimeFrameworkVersion`), the Dockerfile runtime stage and `scripts/test-packaged-container.sh`. The hygiene lane fails until each group agrees, so a partial update cannot test one runtime and ship another. Update mise tool versions explicitly and regenerate its lockfile; do not let an unreviewed newest tool silently redefine formatting. The mise action checks the mise download against its signed checksums, and signing and upload jobs skip the tool cache so every tool is downloaded and checked against `mise.lock`.

`.github/rulesets/quality.json` requires these checks on the default branch, from GitHub Actions only, with no bypass actors, no branch deletion and no force push. [Repository setup](../repository-setup.md) describes when to import and activate it. Every workflow runs its shell steps with `bash -eo pipefail`.

Never add `continue-on-error`, broad `NoWarn`, a lint baseline, audit opt-out, or test skips to turn a failed gate green. A narrowly scoped false-positive exception needs a concrete rationale and review. Generated files and third-party dependencies are excluded from source style ownership, not from dependency auditing.

Release staging is also enforced by the hygiene lane. A small synthetic fixture verifies that the complete checked set of server downloads is accepted while missing, altered, unexpected or symlinked assets, including a leftover Mac download, are refused before staging. This protects against partial or accidental private-file publication; it does not replace signing or remote workflow verification. See [release operations](../release-operations.md) for the protected environments, draft-then-publish releases and immutable release activation.

## Review responsibilities that tools cannot automate

- Keep storage, transport, cryptography, UI and agent authorization responsibilities explicit. Extract cohesive operations when models or views grow; do not introduce abstractions merely to satisfy a line count.
- Review every task's lifetime and cancellation, and every await near lock, pairing, import, or save transitions. Passing Sendable checks does not prove logical race freedom.
- Verify boundary input, resource limits, authorization, crash recovery and durable-write behavior with meaningful examples.
- A test must protect a user-visible behavior or plausible failure mode. There are no coverage quotas, test-per-file requirements, screenshot pixel baselines or trivial DTO tests. Remove tests whose cost exceeds their value.
- UI changes retain the design → independent review → implementation → actual inspection gate in AGENTS.md.
- Describe why a test or dependency is needed in the PR. Keep suppressions and migration changes visible for review.

## New concurrency APIs

The SwiftLint `incompatible_concurrency_annotation` migration rule is intentionally not enabled: it requires `@preconcurrency` for public actor-annotated declarations to preserve a pre-existing nonisolated Swift 5 API. This unreleased project has no such compatibility contract. New public bridge APIs retain explicit MainActor isolation, enforced by complete compiler concurrency checking and warnings-as-errors, rather than adding a compatibility annotation that can relax checking for callers. Reassess this migration rule only when evolving a released public API. This removes a source-compatibility policy that does not apply; no compiler concurrency diagnostics are suppressed.

## Public interoperability corpus exception

`protocol/fixtures/encryption-v1.json` and `protocol/fixtures/encryption-v2.json` intentionally publish synthetic keys, passwords, tokens and derived authentication values so other clients can reproduce exact protocol bytes. Each file has its own Gitleaks exception that matches only its listed exact values, only in that file, and only for `generic-api-key`. No directory or whole-file exclusion is used. The rule-scoped `targetRules` setting is necessary: a global path allowlist can skip the file before evaluating secret matches. This was caught by deliberately replacing a synthetic value and observing the scanner, not by assuming the TOML meant what was intended.

The hygiene lane runs `scripts/quality/check-secret-fixtures.py` against a disposable copy of both files: the documented public corpora must pass, while a different random synthetic secret in a field of either file must fail. The test does not touch the real corpus or print credentials. This small enforcement-boundary check is justified because a broadened exception could otherwise hide an accidentally committed real key. The official pinned-version configuration reference is [Gitleaks v8.30.1](https://github.com/gitleaks/gitleaks/blob/v8.30.1/README.md#configuration).

## Archive UI recovery evidence

The existing native accessibility lane includes ArchiveUITests: real encrypted archive opened through XCTest's system URL-delivery API, wrong recovery key and retry, lifecycle counts, scrolling, cancellation and fresh reopen, actual restore, process relaunch and verification of decrypted records/images. Test data lives in isolated temporary directories. This validates the supported document-open route; it does not substitute for separate Files-picker or VoiceOver verification.

The iOS UI-test runner requires iOS 16.4 because XCTest's `XCUIApplication.open(_:)` was introduced there. The iOS app, the shared core and the iOS unit tests keep the iOS 16.0 floor. This keeps the test on a public OS document-delivery API instead of adding an application-only test import hook. On the Mac, the app and its test bundles target macOS 14.0. That deprecates SwiftUI's `onChange(of:perform:)`, whose replacement needs iOS 17, so shared views use `onValueChange(of:perform:)` (Views/ValueChange.swift), which calls the current API on each platform.

## iOS release credential boundary

The hygiene lane executes `scripts/quality/check-app-store-signing.py` against synthetic decoded iOS and Mac profiles. It verifies the TestFlight upload options for a matching App Store profile, including the installer certificate the Mac needs, and rejection of expired profiles, wrong name/team/bundle/platform, development entitlement and ad hoc/enterprise eligibility. This protects the pre-import credential boundary without real Apple credentials or uploads. Actual certificate/profile compatibility, signing and upload still require Xcode execution on the protected TestFlight runner; these fixtures do not establish signed distribution.

## Opt-in native Files acceptance

Run `mise exec -- scripts/test-native-file-import.sh artifacts/<new-output-directory>` on a simulator with the local Files provider available (the simulator is chosen as described above). This separate scheme stages one uniquely named synthetic PNG in On My iPhone, selects it through the system picker, verifies the displayed entry after relaunch and compares the exact encrypted-store attachment bytes. Its EXIT trap removes only that staged file and the test's uniquely named archive. Result attachments are exported into the chosen output directory. It never accesses personal journals or cloud-provider files.

This provider-dependent UI route is intentionally outside routine CI and default test schemes. Use it when changing image import or picker integration; ordinary image validation and lifecycle races remain covered by smaller focused tests. Both `JournalFileTests` and the opt-in `JournalMeasurements` sources are included in strict SwiftLint checks.

The opt-in `JournalFileUITests/ArchiveFileUITests` case covers actual archive delivery: Settings → Export Archive → native Files save → a fresh welcome screen → native Files import → recovery → relaunch. It compares restored record identities/content, deletion state and exact image bytes with the source fixture. Run it with `mise exec -- scripts/test-native-file-import.sh artifacts/<new-output-directory> -only-testing:JournalFileUITests/ArchiveFileUITests`. The wrapper deletes only the uniquely named synthetic archive package after completion/failure. It complements fast archive/history tests and existing wrong-key/cancellation UI coverage; it does not add a routine CI requirement or use personal backups.

## Deployment dependency updates

The Tailscale sidecar uses an explicit version and immutable multi-platform index digest instead of the moving `stable` tag, and the pinned image's binary reports that version. Compose syntax is validated; real tailnet enrollment is not tested. Caddy has a version and digest pin too. Application server images are selected by the release digest described in release operations, or built from local source during development.

GitHub's [supported ecosystems documentation](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories#docker-compose) lists Docker Compose as the distinct `docker-compose` ecosystem. The /deploy Compose update entry complements the existing Dockerfile updater; it does not replace it.

## Markdown parser and resource limits

The Markdown body format uses Apple's Swift Markdown parser pinned to 0.9.0, with its locked swift-cmark dependency. A maintained CommonMark/GFM parser avoids maintaining an incomplete syntax recognizer. The dependency is Apache-2.0 with Swift's runtime exception; swift-cmark includes its MIT-derived notices. Keep upstream notices in release attribution and include the lockfile in the existing dependency audit. Raw HTML is never executed and remote images are not loaded.

Apple checks use two build jobs and run sequentially on development machines. This limits build memory pressure without skipping checks. UI acceptance still requires actual inspection after independent design review.
