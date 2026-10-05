#!/bin/bash
# Produces an unpacked self-contained server. No publishing or signing credentials required.
# JOURNAL_VERSION (for example 1.2.0) is the version GET /v1/server reports; releases set it from their tag.
set -euo pipefail
cd "$(dirname "$0")/.."
runtime="${1:?Usage: [JOURNAL_VERSION=<x.y.z>] package-server.sh <osx-arm64|osx-x64|linux-arm64|linux-x64> <new-output-directory>}"
output="${2:?Choose a new output directory}"
version="${JOURNAL_VERSION:-0.0.0-dev}"
case "$runtime" in
  osx-arm64 | osx-x64 | linux-arm64 | linux-x64) ;;
  *)
    echo "Unsupported server runtime: $runtime" >&2
    exit 2
    ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || {
  echo "JOURNAL_VERSION must look like 1.2.0 or 1.2.0-beta.1, without a leading v." >&2
  exit 2
}
[[ ! -e "$output" ]] || {
  echo "Output already exists; choose a new directory." >&2
  exit 2
}
dotnet restore server/src/Journal.Api --locked-mode
dotnet publish server/src/Journal.Api -c Release -r "$runtime" --self-contained true --no-restore \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -p:PublishTrimmed=false -p:DebugType=embedded \
  -p:Version="$version" -o "$output"
cp packaging/journal-server "$output/journal-server"
chmod 755 "$output/journal-server"
cp LICENSE NOTICE "$output/"
# The self-contained server redistributes the .NET runtime and NuGet packages; their notices travel with it.
cp packaging/server-THIRD-PARTY-NOTICES.txt "$output/THIRD-PARTY-NOTICES.txt"
cp packaging/server-README.md "$output/README.md"
printf 'Self-contained server %s: %s\n' "$version" "$output"
