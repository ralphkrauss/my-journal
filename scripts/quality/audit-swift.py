#!/usr/bin/env python3
"""Check resolved Swift packages against OSV; fail if the audit cannot run.

OSV indexes Git-range advisories by commit and GitHub advisories by SwiftURL package
version, so each pin is queried both ways.
"""

import json
import re
from urllib.request import Request, urlopen

from paths import ROOT

lock = json.loads((ROOT / "apps/apple/Packages/JournalCore/Package.resolved").read_text())
queries = []
owners = []
for pin in lock["pins"]:
    queries.append({"commit": pin["state"]["revision"]})
    owners.append(pin["identity"])
    version = pin["state"].get("version")
    if version:
        name = re.sub(r"^https?://", "", pin["location"]).removesuffix(".git")
        queries.append({"package": {"ecosystem": "SwiftURL", "name": name}, "version": version})
        owners.append(pin["identity"])
request = Request(
    "https://api.osv.dev/v1/querybatch",
    data=json.dumps({"queries": queries}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urlopen(request, timeout=30) as response:
    results = json.load(response)["results"]
if len(results) != len(queries):
    raise SystemExit("Incomplete dependency audit response")
findings = sorted(
    {
        f"{identity}: {issue['id']}"
        for identity, result in zip(owners, results, strict=True)
        for issue in result.get("vulns", [])
    }
)
if findings:
    raise SystemExit("Known dependency vulnerabilities:\n" + "\n".join(findings))
print(
    f"OSV: no known advisories for {len(lock['pins'])} resolved packages "
    f"({len(queries)} commit and version queries)."
)
print("Advisory coverage is not exhaustive.")
