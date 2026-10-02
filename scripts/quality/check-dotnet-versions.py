"""Keep the .NET SDK and runtime pins that different tools and updaters change in agreement.

A partial update would test one runtime while shipping another, for example a new container
base image while the packaged-server check still runs on the previous runtime.
"""

import json
import re
import tomllib

from paths import ROOT


def find(path, pattern):
    match = re.search(pattern, (ROOT / path).read_text(), re.MULTILINE)
    if not match:
        raise SystemExit(f"No .NET version pin found in {path}")
    return match.group(1)


sdk = {
    "global.json": json.loads((ROOT / "global.json").read_text())["sdk"]["version"],
    "mise.toml": tomllib.loads((ROOT / "mise.toml").read_text())["tools"]["dotnet"],
    "server/Dockerfile (build)": find("server/Dockerfile", r"dotnet/sdk:(\d+\.\d+\.\d+)"),
}
runtime = {
    "Journal.Api.csproj": find(
        "server/src/Journal.Api/Journal.Api.csproj",
        r"<RuntimeFrameworkVersion>(\d+\.\d+\.\d+)</RuntimeFrameworkVersion>",
    ),
    "server/Dockerfile (runtime)": find("server/Dockerfile", r"dotnet/aspnet:(\d+\.\d+\.\d+)"),
    "scripts/test-packaged-container.sh": find(
        "scripts/test-packaged-container.sh", r"dotnet/runtime-deps:(\d+\.\d+\.\d+)"
    ),
}
for kind, pins in [("SDK", sdk), ("runtime", runtime)]:
    if len(set(pins.values())) != 1:
        details = ", ".join(f"{path} {version}" for path, version in pins.items())
        raise SystemExit(f"Update every .NET {kind} pin together: {details}")
print(f".NET SDK {sdk['global.json']} and runtime {runtime['Journal.Api.csproj']} pins agree.")
