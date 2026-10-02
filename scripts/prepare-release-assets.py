"""Validate the complete download set from one release run before publication."""

import hashlib
import pathlib
import re
import shutil
import sys


def expected_assets(tag: str) -> dict[str, list[str]]:
    # The apps ship through the App Store; a release holds the standalone server.
    return {
        "linux-x64": [f"journal-server-{tag}-linux-x64.tar.gz"],
        "linux-arm64": [f"journal-server-{tag}-linux-arm64.tar.gz"],
    }


def prepare(source: pathlib.Path, tag: str, output: pathlib.Path) -> None:
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) or output.exists():
        raise ValueError("A version tag and new output directory are required.")
    expected = expected_assets(tag)
    if {path.name for path in source.iterdir()} != {f"release-{platform}" for platform in expected}:
        raise ValueError("The complete architecture set is required, with no extra artifacts.")
    verified = []
    for platform, names in expected.items():
        directory = source / f"release-{platform}"
        manifest = directory / f"SHA256SUMS-{platform}"
        artifacts = [directory / name for name in names]
        if directory.is_symlink() or {path.name for path in directory.iterdir()} != {
            manifest.name,
            *names,
        }:
            raise ValueError("Unexpected release artifact contents.")
        if any(path.is_symlink() or not path.is_file() for path in [manifest, *artifacts]):
            raise ValueError("Release assets must be regular files.")
        if manifest.stat().st_size > 4096:
            raise ValueError("Invalid checksum manifest.")
        lines = manifest.read_text().splitlines()
        entries = {}
        for line in lines:
            digest, filename = line.split(maxsplit=1)
            if not re.fullmatch(r"[a-f0-9]{64}", digest):
                raise ValueError("Unexpected release checksum entry.")
            entries[filename.removeprefix("./")] = digest
        if len(entries) != len(lines) or set(entries) != set(names):
            raise ValueError("Expected one checksum for each release asset.")
        for artifact in artifacts:
            with artifact.open("rb") as stream:
                actual = hashlib.file_digest(stream, "sha256").hexdigest()
            if actual != entries[artifact.name]:
                raise ValueError("Release asset checksum mismatch.")
            verified.append((artifact, actual))
    output.mkdir()
    lines = []
    for artifact, digest in sorted(verified):
        shutil.copyfile(artifact, output / artifact.name)
        lines.append(f"{digest}  {artifact.name}\n")
    (output / "SHA256SUMS").write_text("".join(lines))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: prepare-release-assets.py <download-directory> <tag> <new-output>")
    try:
        prepare(pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3]))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
