"""Protect the release gate against missing, altered and unexpected downloads."""

import hashlib
import pathlib
import shutil
import subprocess
import sys
import tempfile

script = pathlib.Path(__file__).resolve().parents[1] / "prepare-release-assets.py"
with tempfile.TemporaryDirectory(prefix="journal-release-assets-") as temporary:
    root = pathlib.Path(temporary)
    baseline = root / "baseline"
    baseline.mkdir()
    for platform in ["linux-x64", "linux-arm64"]:
        directory = baseline / f"release-{platform}"
        directory.mkdir()
        names = [f"journal-server-v0.1.0-{platform}.tar.gz"]
        sums = []
        for name in names:
            content = f"Synthetic {name}".encode()
            (directory / name).write_bytes(content)
            sums.append(f"{hashlib.sha256(content).hexdigest()}  ./{name}\n")
        (directory / f"SHA256SUMS-{platform}").write_text("".join(sums))
    for scenario in ["valid", "missing", "old-mac-download", "changed", "extra", "symlink"]:
        source = root / scenario
        shutil.copytree(baseline, source)
        target = source / "release-linux-x64/journal-server-v0.1.0-linux-x64.tar.gz"
        if scenario == "missing":
            shutil.rmtree(source / "release-linux-arm64")
        elif scenario == "old-mac-download":
            (source / "release-macOS-arm64").mkdir()
        elif scenario == "changed":
            target.write_bytes(b"Altered after checksum creation")
        elif scenario == "extra":
            (source / "release-linux-x64/connection.json").write_text("Synthetic private file")
        elif scenario == "symlink":
            target.unlink()
            target.symlink_to(baseline / "release-linux-x64" / target.name)
        output = root / f"output-{scenario}"
        result = subprocess.run(
            [sys.executable, str(script), str(source), "v0.1.0", str(output)],
            capture_output=True,
            text=True,
            check=False,
        )
        if scenario == "valid":
            if result.returncode != 0:
                raise SystemExit(result.stderr)
            for line in (output / "SHA256SUMS").read_text().splitlines():
                digest, name = line.split(maxsplit=1)
                if hashlib.sha256((output / name).read_bytes()).hexdigest() != digest:
                    raise SystemExit("Staged release checksum is incorrect.")
            if len(list(output.iterdir())) != 3:
                raise SystemExit("The staged release must contain two assets and one manifest.")
        elif result.returncode == 0 or output.exists():
            raise SystemExit(f"Unsafe release input was not refused before staging: {scenario}")
print("Release staging accepts the complete verified set and rejects unsafe inputs.")
