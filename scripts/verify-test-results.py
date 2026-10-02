"""Fail when a test run skipped tests or did not run every test it was asked to run."""

import json
import subprocess
import sys


def test_cases(nodes, bundle=None):
    for node in nodes:
        kind = node.get("nodeType", "")
        if kind.endswith("test bundle"):
            yield from test_cases(node.get("children", []), node.get("name"))
        elif kind == "Test Case":
            identifier = node.get("nodeIdentifier", node.get("name", "")).removesuffix("()")
            yield f"{bundle}/{identifier}", node.get("result")
        else:
            yield from test_cases(node.get("children", []), bundle)


def problems(report, arguments):
    cases = list(test_cases(report.get("testNodes", [])))
    found = [f"Skipped: {name}" for name, result in cases if result == "Skipped"]
    if not cases:
        found.append("No tests ran.")
    for argument in arguments:
        if not argument.startswith("-only-testing:"):
            continue
        requested = argument.removeprefix("-only-testing:").removesuffix("()")
        if not any(name == requested or name.startswith(requested + "/") for name, _ in cases):
            found.append(f"Requested test did not run: {requested}")
    return found


def main():
    if len(sys.argv) < 2:
        raise SystemExit("Usage: verify-test-results.py <result.xcresult> [xcodebuild arguments]")
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", sys.argv[1]],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    found = problems(json.loads(output), sys.argv[2:])
    if found:
        raise SystemExit("Incomplete test run:\n" + "\n".join(found))


if __name__ == "__main__":
    main()
