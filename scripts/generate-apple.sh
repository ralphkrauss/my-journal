#!/bin/bash
# Generate an Xcode project from its spec and pin its packages to the committed lockfile.
set -euo pipefail
cd "$(dirname "$0")/.."
spec="${1:-apps/apple/project.yml}"
project="${2:-Journal}"
xcodegen generate --spec "$spec" --project apps/apple
lock_dir="apps/apple/$project.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$lock_dir"
cp apps/apple/Packages/JournalCore/Package.resolved "$lock_dir/Package.resolved"
