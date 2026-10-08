#!/bin/bash
# Use mise exec -- scripts/check.sh <mode> to run with the committed tool versions.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-all}" in
  hygiene)
    while IFS= read -r -d '' script; do
      shellcheck "$script"
      shfmt -d -i 2 -ci "$script"
      # Workflows and other scripts run these directly; a missing executable bit only fails on first use.
      [[ -x "$script" ]] || {
        echo "Make $script executable (chmod +x)." >&2
        exit 1
      }
    done < <(find scripts .githooks packaging -type f \( -name '*.sh' -o -name pre-commit -o -name journal-server \) -print0)
    ruff check scripts
    ruff format --check scripts
    actionlint .github/workflows/*.yml
    gitleaks dir . --redact --no-banner --config .gitleaks.toml
    python3 scripts/quality/check-secret-fixtures.py
    python3 scripts/quality/check-release-assets.py
    python3 scripts/quality/check-app-store-signing.py
    python3 scripts/quality/check-test-results.py
    python3 scripts/quality/check-dotnet-versions.py
    ;;
  backend)
    dotnet restore server --locked-mode
    dotnet format server --no-restore --verify-no-changes
    dotnet build server --no-restore
    dotnet test server --no-build --no-restore
    ;;
  apple)
    scripts/check.sh lint
    scripts/check.sh core
    scripts/generate-apple.sh
    scripts/check.sh mac
    scripts/check.sh ios-build
    ;;
  # The parts of the apple lane, for scripts/release-check.sh. mac and ios-build need the generated project.
  lint)
    [[ "$(xcrun swift-format --version)" == "6.3.0" ]] || {
      echo "Use Xcode 26.6 (swift-format 6.3.0)." >&2
      exit 1
    }
    python3 scripts/quality/format-swift.py
    swiftlint lint --strict --quiet
    ;;
  core)
    swift test --package-path apps/apple/Packages/JournalCore --jobs 2 --force-resolved-versions \
      -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
    ;;
  mac)
    # Debug, explicitly: tests use loopback HTTP test servers, which only Debug builds accept. JOURNAL_DERIVED_DATA
    # lets it build beside a lane that uses artifacts/DerivedData. The test servers listen inside the app's sandbox,
    # so the test host gets the test entitlements.
    xcodebuild -jobs 2 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (Mac)' -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath "${JOURNAL_DERIVED_DATA:-artifacts/DerivedData}" \
      -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- \
      JOURNAL_MAC_ENTITLEMENTS=Signing/JournalMac-Tests.entitlements test
    ;;
  ios-build)
    # Only this Mac's simulator architecture, which the simulator test lanes build too. Building every architecture
    # would make this lane and those lanes recompile each other's code in the shared derived data.
    xcodebuild -jobs 2 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (iOS)' \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath artifacts/DerivedData \
      -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- ARCHS="$(uname -m)" build
    ;;
  audit)
    dotnet restore server --locked-mode --force-evaluate
    python3 scripts/quality/audit-swift.py
    ;;
  all)
    scripts/check.sh hygiene
    scripts/check.sh backend
    scripts/check.sh apple
    scripts/check.sh audit
    ;;
  release)
    shift
    exec scripts/release-check.sh "$@"
    ;;
  *)
    printf 'Usage: %s {hygiene|backend|apple|audit|all|release [options]}\n' "$0" >&2
    printf 'Parts of apple: lint, core, mac, ios-build.\n' >&2
    exit 2
    ;;
esac
