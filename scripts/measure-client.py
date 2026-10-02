"""Opt-in encrypted Swift store measurement; no timing thresholds or real vaults."""

import json
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "apps/apple/Packages/JournalCore"


def main():
    if len(sys.argv) != 2 or platform.system() != "Darwin":
        raise SystemExit("Usage on macOS: measure-client.py <new-report.json>")
    output = Path(sys.argv[1]).resolve()
    if output.exists():
        raise SystemExit("Choose a new report path; existing output is preserved.")
    env = dict(os.environ)
    build = ["swift", "build", "--package-path", str(PACKAGE), "-c", "release"]
    subprocess.run(
        build
        + [
            "--force-resolved-versions",
            "--product",
            "JournalMeasure",
            "-Xswiftc",
            "-strict-concurrency=complete",
            "-Xswiftc",
            "-warnings-as-errors",
        ],
        env=env,
        check=True,
    )
    binary = (
        Path(subprocess.check_output(build + ["--show-bin-path"], env=env, text=True).strip())
        / "JournalMeasure"
    )
    with tempfile.TemporaryDirectory(prefix="journal-client-measure-") as temporary:
        fixture = Path(temporary) / "synthetic-vault"

        def run(mode):
            return json.loads(
                subprocess.check_output(
                    [str(binary), mode, str(fixture)], env=env, text=True, timeout=180
                )
            )

        seed = run("seed")
        reads = [run("read") for _ in range(3)]
        report = {
            "platform": platform.platform(),
            "architecture": platform.machine(),
            "build": "release",
            "entries": 3650,
            "images": 100,
            "imageBytesEach": 262144,
            "bodyCharactersApproximately": 4180,
            "fixtureFileBytes": sum(p.stat().st_size for p in fixture.rglob("*") if p.is_file()),
            "seed": seed,
            "freshProcesses": reads,
            "limits": (
                "Swift encrypted store only; not app startup, rendering or AppModel search. "
                "Fresh processes share warm OS disk caches. Synthetic attachment bytes model "
                "encrypted I/O, not image decoding. Peak RSS includes the full process and "
                "two retained snapshots. No minimum-hardware or timing guarantees."
            ),
        }
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
