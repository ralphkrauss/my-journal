#!/bin/bash
# Fail closed when a release environment has no required reviewers or deployment ref policy. GitHub creates a
# missing environment without protection the first time a job names it, so naming it in YAML is not enough.
set -euo pipefail
environment="${1:?Usage: require-protected-environment.sh <environment>}"
: "${GH_TOKEN:?}" "${GH_REPO:?}"
[[ "$environment" =~ ^[a-z-]+$ ]]
gh api "repos/$GH_REPO/environments/$environment" | python3 -c '
import json
import sys

environment = json.load(sys.stdin)
reviewers = [
    reviewer
    for rule in environment.get("protection_rules", [])
    if rule.get("type") == "required_reviewers"
    for reviewer in rule.get("reviewers", [])
]
if not reviewers or not environment.get("deployment_branch_policy"):
    raise SystemExit(
        f"Protect the {sys.argv[1]} environment with a required reviewer and a v* tag or main deployment policy "
        "before it runs; see docs/release-operations.md."
    )
print(f"The {sys.argv[1]} environment requires review and restricts deployment refs.")
' "$environment"
