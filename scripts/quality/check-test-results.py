"""Protect native test lanes against coverage lost silently to skips or stale test filters."""

import importlib.util
import pathlib

script = pathlib.Path(__file__).resolve().parents[1] / "verify-test-results.py"
spec = importlib.util.spec_from_file_location("verify_test_results", script)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def report(pairing_result):
    cases = [
        {
            "nodeType": "Test Case",
            "nodeIdentifier": "JournalUITests/testWriteAndReopenEntry()",
            "result": "Passed",
        },
        {
            "nodeType": "Test Case",
            "nodeIdentifier": "JournalUITests/testPairDeviceAndDownloadEncryptedEntry()",
            "result": pairing_result,
        },
    ]
    suite = {"nodeType": "Test Suite", "name": "JournalUITests", "children": cases}
    bundle = {"nodeType": "UI test bundle", "name": "JournalIOSUITests", "children": [suite]}
    return {"testNodes": [{"nodeType": "Test Plan", "children": [bundle]}]}


complete = "-only-testing:JournalIOSUITests/JournalUITests/testPairDeviceAndDownloadEncryptedEntry"
stale = "-only-testing:JournalIOSUITests/EntryArchivingUITests/testArchive"
assert verifier.problems(report("Passed"), [complete, "-only-testing:JournalIOSUITests"]) == []
assert verifier.problems(report("Skipped"), []) == [
    "Skipped: JournalIOSUITests/JournalUITests/testPairDeviceAndDownloadEncryptedEntry"
]
assert verifier.problems(report("Passed"), [stale]) == [
    "Requested test did not run: JournalIOSUITests/EntryArchivingUITests/testArchive"
]
assert verifier.problems({"testNodes": []}, []) == ["No tests ran."]
print("Native test runs fail on skipped tests, empty runs and requested tests that did not run.")
