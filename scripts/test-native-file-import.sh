#!/bin/bash
# Opt-in local Files-provider acceptance with one synthetic image, never personal files.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Usage: test-native-file-import.sh <new-output-directory>}"
shift
[[ ! -e "$output" ]] || {
  echo "Choose a new output directory." >&2
  exit 2
}
simulator="$(scripts/prepare-simulator.sh)"
provider_root=""
while IFS=$'\t' read -r container_group container_path; do
  if [[ "$container_group" == group.com.apple.FileProvider.LocalStorage ]]; then provider_root="$container_path"; fi
done < <(xcrun simctl get_app_container "$simulator" com.apple.DocumentsApp groups)
[[ -n "$provider_root" && -d "$provider_root/File Provider Storage" ]] || {
  echo "Local Files provider is unavailable in the selected simulator." >&2
  exit 1
}
mkdir -p "$output"
output="$(cd "$output" && pwd)"
filename="Journal-Import-$(uuidgen).png"
fixture="$provider_root/File Provider Storage/$filename"
[[ ! -e "$fixture" ]]
archive="$provider_root/File Provider Storage/${filename%.png}-backup.journalarchive"
[[ ! -e "$archive" ]]
trap 'rm -f "$fixture"; rm -rf "$archive"' EXIT
encoded="$(
  python3 - <<'PY'
import base64
import struct
import zlib

def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

header = struct.pack('!2I5B', 16, 16, 8, 6, 0, 0, 0)
rows = b''.join(b'\0' + bytes([30, 110, 230, 255]) * 16 for _ in range(16))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
print(base64.b64encode(png).decode())
PY
)"
printf '%s' "$encoded" | base64 --decode >"$fixture"
scripts/generate-apple.sh apps/apple/file-acceptance.yml JournalFileAcceptance
xcodebuild -project apps/apple/JournalFileAcceptance.xcodeproj -scheme JournalFileImport \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$output/build" \
  -resultBundlePath "$output/Import.xcresult" -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- JOURNAL_IMPORT_NAME="$filename" JOURNAL_IMPORT_BYTES="$encoded" "$@" test
xcrun xcresulttool export attachments --path "$output/Import.xcresult" --output-path "$output/evidence"
python3 scripts/verify-test-results.py "$output/Import.xcresult" "$@"
