"""Enumerate maintained files, excluding generated output and local journal data."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXCLUDED = {".git", ".build", "artifacts", "bin", "obj", "DerivedData", "__pycache__"}


def source_files():
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if any(part in EXCLUDED or part.endswith(".xcodeproj") for part in relative.parts):
            continue
        if path.is_file():
            yield path
