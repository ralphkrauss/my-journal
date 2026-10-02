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
    [[ "$(xcrun swift-format --version)" == "6.3.0" ]] || {
      echo "Use Xcode 26.6 (swift-format 6.3.0)." >&2
      exit 1
    }
    python3 scripts/quality/format-swift.py
    swiftlint lint --strict --quiet
    swift test --package-path apps/apple/Packages/JournalCore --jobs 2 --force-resolved-versions \
      -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
    scripts/generate-apple.sh
    # Debug, explicitly: tests use loopback HTTP test servers, which only Debug builds accept.
    xcodebuild -jobs 2 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (Mac)' -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath artifacts/DerivedData \
      -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- test
    xcodebuild -jobs 2 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (iOS)' \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath artifacts/DerivedData \
      -onlyUsePackageVersionsFromResolvedFile CODE_SIGN_IDENTITY=- build
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
  *)
    printf 'Usage: %s {hygiene|backend|apple|audit|all}\n' "$0" >&2
    exit 2
    ;;
esac
