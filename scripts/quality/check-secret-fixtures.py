"""Ensure the public crypto corpus exceptions cannot hide other secrets in those files."""

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Each corpus and the path (object members and list positions) to a value that a secret-like
# value replaces: the scanner must then report it. The value is derived from the path, so the
# check is repeatable (random values were occasionally not reported).
CORPORA = {
    "protocol/conformance/crypto/encryption-v1.json": ("recovery", "authenticationSecret"),
    "protocol/conformance/crypto/encryption-v2.json": ("recovery", "recoverySecret"),
    "protocol/conformance/agent-copy/agent-copy-v1.json": ("wrap", "secret"),
    "protocol/conformance/crypto/negative-v1.json": ("open", 0, "key"),
}


def write(directory, contents):
    for path, text in contents.items():
        target = Path(directory) / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)


def scan(directory, expected):
    command = [
        "gitleaks",
        "dir",
        directory,
        "--redact",
        "--no-banner",
        "--config",
        str(ROOT / ".gitleaks.toml"),
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != expected:
        raise RuntimeError("Secret scanner fixture boundary failed. " + result.stderr)


def main():
    originals = {path: (ROOT / path).read_text() for path in CORPORA}
    with tempfile.TemporaryDirectory(prefix="journal-secret-check-") as directory:
        write(directory, originals)
        scan(directory, 0)
        for path, location in CORPORA.items():
            corpus = json.loads(originals[path])
            parent = corpus
            for step in location[:-1]:
                parent = parent[step]
            planted = hashlib.sha256(("journal-secret-check:" + path).encode())
            parent[location[-1]] = planted.hexdigest()
            changed = json.dumps(corpus, indent=2, ensure_ascii=False) + "\n"
            write(directory, {**originals, path: changed})
            scan(directory, 1)
    print("Public fixture exceptions are limited to the documented synthetic values.")


if __name__ == "__main__":
    main()
