#!/bin/bash
# Only the protected GitHub release job may publish registry artifacts.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
  echo 'Container publication requires the protected GitHub-hosted release job.' >&2
  exit 1
}
root="${1:?Specify the downloaded container artifact directory}"
: "${GH_TOKEN:?}" "${GH_REPO:?}" "${RELEASE_TAG:?}" "${RELEASE_RUN_ID:?}" "${RELEASE_ATTEMPT:?}" "${REGISTRY_USER:?}"
[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$RELEASE_RUN_ID" =~ ^[0-9]+$ && "$RELEASE_ATTEMPT" =~ ^[0-9]+$ ]]
[[ "$GH_REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]
# Validate the entire input set before any registry write.
python3 - "$root" <<'PY'
import hashlib
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
expected = {f"container-{arch}" for arch in ("amd64", "arm64")}
if root.is_symlink() or {p.name for p in root.iterdir()} != expected:
    raise SystemExit("Expected exactly the two native container artifacts.")
for arch in ("amd64", "arm64"):
    folder = root / f"container-{arch}"
    archive = folder / f"{arch}.tar.gz"
    manifest = folder / "SHA256SUMS"
    if folder.is_symlink() or {p.name for p in folder.iterdir()} != {archive.name, manifest.name}:
        raise SystemExit("Unexpected container artifact contents.")
    if any(p.is_symlink() or not p.is_file() for p in (archive, manifest)):
        raise SystemExit("Expected regular container artifact files.")
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if manifest.read_text() != f"{digest}  {archive.name}\n":
        raise SystemExit("Container artifact checksum mismatch.")
PY
repository="ghcr.io/$(printf '%s' "$GH_REPO" | tr '[:upper:]' '[:lower:]')/server"
# Each run attempt gets a distinct tag. Installation uses the returned immutable digest.
reference="$repository:$RELEASE_TAG-$RELEASE_RUN_ID-$RELEASE_ATTEMPT"
for arch in amd64 arm64; do
  docker load --input "$root/container-$arch/$arch.tar.gz"
  [[ "$(docker image inspect "journal-release:$arch" --format '{{.Os}}/{{.Architecture}}')" == "linux/$arch" ]]
done
printf '%s' "$GH_TOKEN" | docker login ghcr.io --username "$REGISTRY_USER" --password-stdin
for arch in amd64 arm64; do
  docker tag "journal-release:$arch" "$reference-$arch"
  docker push "$reference-$arch"
done
docker buildx imagetools create --tag "$reference" "$reference-amd64" "$reference-arm64"
digest="$(docker buildx imagetools inspect "$reference" --format '{{.Manifest.Digest}}')"
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || {
  echo 'Registry publication returned an unexpected digest; inspect the published manifest.' >&2
  exit 1
}
docker buildx imagetools inspect "$repository@$digest" --raw | python3 -c '
import json, sys
manifest = json.load(sys.stdin)
platforms = {(item.get("platform", {}).get("os"), item.get("platform", {}).get("architecture"))
             for item in manifest.get("manifests", [])}
if platforms - {("unknown", "unknown")} != {("linux", "amd64"), ("linux", "arm64")}:
    raise SystemExit("Published manifest does not contain the expected Linux architectures.")
'
printf 'Published: %s\nInstall: %s@%s\n' "$reference" "$repository" "$digest"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'image=%s\ndigest=%s\n' "$repository" "$digest" >>"$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Server image\n\nTag: %s\n\nImmutable installation reference:\n\n    %s@%s\n' \
    "$reference" "$repository" "$digest" >>"$GITHUB_STEP_SUMMARY"
fi
