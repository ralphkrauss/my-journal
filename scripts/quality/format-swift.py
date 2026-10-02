#!/usr/bin/env python3
"""Use one formatter for every maintained Swift source, including test fixtures."""

import subprocess
import sys

from paths import ROOT, source_files

mode = ["format", "--in-place"] if "--fix" in sys.argv else ["lint", "--strict"]
paths = sorted(str(path) for path in source_files() if path.suffix == ".swift")
subprocess.run(["xcrun", "swift-format", *mode, *paths], cwd=ROOT, check=True)
