"""Ensure the public crypto corpus exceptions cannot hide other secrets in those files."""

import json
import secrets
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Each corpus and a field whose value a random secret replaces: the scanner must then report it.
CORPORA = {
    "protocol/fixtures/encryption-v1.json": ("recovery", "authenticationSecret"),
    "protocol/fixtures/encryption-v2.json": ("recovery", "recoverySecret"),
    "protocol/fixtures/agent-copy-v1.json": ("wrap", "secret"),
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
        for path, (section, field) in CORPORA.items():
            corpus = json.loads(originals[path])
            corpus[section][field] = secrets.token_hex(32)
            changed = json.dumps(corpus, indent=2, ensure_ascii=False) + "\n"
            write(directory, {**originals, path: changed})
            scan(directory, 1)
    print("Public fixture exceptions are limited to the documented synthetic values.")


if __name__ == "__main__":
    main()
