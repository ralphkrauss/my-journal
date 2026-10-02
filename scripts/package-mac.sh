#!/bin/bash
# Local development package, ad-hoc signed. The Mac App Store build comes from archive-mac.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
architecture="${1:?Usage: package-mac.sh <arm64|x86_64> <new-output-directory>}"
output="${2:?Choose a new output directory}"
case "$architecture" in
  arm64) runtime=osx-arm64 ;;
  x86_64) runtime=osx-x64 ;;
  *)
    echo "Unsupported Mac architecture." >&2
    exit 2
    ;;
esac
[[ ! -e "$output" ]] || {
  echo "Output already exists; choose a new directory." >&2
  exit 2
}
mkdir -p "$output"
output="$(cd "$output" && pwd)"
scripts/generate-apple.sh
xcodebuild -jobs 2 -project apps/apple/Journal.xcodeproj -scheme 'My Journal (Mac)' -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$output/build" \
  -onlyUsePackageVersionsFromResolvedFile ARCHS="$architecture" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- build
cp -R "$output/build/Build/Products/Release/My Journal.app" "$output/My Journal.app"
# The server joins the Xcode build in Contents/Helpers.
scripts/package-server.sh "$runtime" "$output/server-publish"
scripts/embed-mac-server.sh "$output/My Journal.app" "$output/server-publish"
mkdir "$output/dmg"
cp -R "$output/My Journal.app" "$output/dmg/My Journal.app"
ln -s /Applications "$output/dmg/Applications"
cp packaging/mac-README.md "$output/dmg/Read Me.txt"
hdiutil create -volname 'My Journal Development' -srcfolder "$output/dmg" -format UDZO \
  "$output/Journal-macOS-$architecture-development.dmg"
(
  cd "$output"
  shasum -a 256 "Journal-macOS-$architecture-development.dmg" >SHA256SUMS
)
printf 'Development package: %s\n' "$output/Journal-macOS-$architecture-development.dmg"
