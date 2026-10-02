#!/bin/bash
# Exports a device archive, signing it with the reviewed options; does not upload to Apple or GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
archive="${1:?Usage: export-ios.sh <My Journal.xcarchive> <ExportOptions.plist> <new-output-directory>}"
options="${2:?Provide reviewed export options matching your team and provisioning}"
output="${3:?Choose a new output directory}"
app="$archive/Products/Applications/My Journal.app"
[[ -d "$app" && -f "$options" && ! -e "$output" ]] || {
  echo "A My Journal device archive, export options, and new output directory are required." >&2
  exit 2
}
# An unsigned archive from archive-ios.sh is signed during export; a signed one must still be intact.
if codesign --display "$app" 2>/dev/null; then
  codesign --verify --deep --strict "$app"
fi
python3 - "$options" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as source:
    options = plistlib.load(source)
if options.get("destination", "export") != "export":
    raise SystemExit("Only local export is supported; destination must be export.")
if options.get("method") not in {"app-store-connect", "release-testing", "debugging"}:
    raise SystemExit("Choose app-store-connect, release-testing or debugging for the export method.")
if not options.get("teamID"):
    raise SystemExit("A development team ID is required.")
PY
mkdir -p "$output"
output="$(cd "$output" && pwd)"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" -exportPath "$output"
python3 - "$output" <<'PY'
import hashlib
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
packages = sorted(root.glob("*.ipa"))
if len(packages) != 1:
    raise SystemExit("Expected one exported IPA. No release checksum generated.")
package = packages[0]
with package.open("rb") as source:
    digest = hashlib.file_digest(source, "sha256").hexdigest()
(root / "SHA256SUMS").write_text(f"{digest}  {package.name}\n")
PY
printf 'Exported iOS package: %s\n' "$output"
