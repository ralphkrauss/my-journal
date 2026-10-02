"""Require every check named in the default-branch ruleset to have passed on one commit.

The TestFlight workflow uses this instead of repeating the full Quality run for a commit
that already passed it.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GITHUB_ACTIONS_APP_ID = 15368


def required_checks():
    ruleset = json.loads((ROOT / ".github/rulesets/quality.json").read_text())
    return {
        check["context"]
        for rule in ruleset["rules"]
        if rule["type"] == "required_status_checks"
        for check in rule["parameters"]["required_status_checks"]
    }


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"[0-9a-f]{40}", sys.argv[1]):
        raise SystemExit("Usage: require-successful-checks.py <commit-sha>")
    pages = subprocess.run(
        [
            "gh",
            "api",
            "--paginate",
            "--slurp",
            f"repos/{os.environ['GH_REPO']}/commits/{sys.argv[1]}/check-runs?per_page=100",
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    latest = {}
    for page in json.loads(pages):
        for run in page["check_runs"]:
            if run["app"]["id"] != GITHUB_ACTIONS_APP_ID:
                continue
            if run["name"] not in latest or run["id"] > latest[run["name"]]["id"]:
                latest[run["name"]] = run
    missing = sorted(
        name
        for name in required_checks()
        if name not in latest or latest[name]["conclusion"] != "success"
    )
    if missing:
        raise SystemExit(
            "Wait until Quality and Dependency Audit pass on this commit. Not yet successful: "
            + ", ".join(missing)
        )
    print("All required checks passed on this commit.")


if __name__ == "__main__":
    main()
