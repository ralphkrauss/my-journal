"""Opt-in synthetic server sizing probe, isolated from real journals and outside CI."""

import base64
import hashlib
import http.client
import json
import os
import pathlib
import statistics
import subprocess
import sys
import time
import uuid

if len(sys.argv) != 3:
    raise SystemExit("Usage: measure-server.py <local-image> <new-report.json>")
image, output = sys.argv[1], pathlib.Path(sys.argv[2])
if output.exists():
    raise SystemExit("Choose a new report path.")
name = "journal-sizing-" + uuid.uuid4().hex[:12]
volume = name + "-data"
entry_count, revisions, payload_bytes = 3650, 2, 4096
attachment_count, attachment_bytes = 100, 256 * 1024


def docker(*arguments):
    return subprocess.check_output(["docker", *arguments], text=True).strip()


def stats():
    sample = json.loads(docker("stats", "--no-stream", "--format", "{{json .}}", name))
    return {key: sample[key] for key in ["CPUPerc", "MemUsage", "PIDs"]}


def timings(values):
    ordered = sorted(values)
    return {
        "count": len(values),
        "medianMilliseconds": statistics.median(values) * 1000,
        "p95Milliseconds": ordered[int((len(values) - 1) * 0.95)] * 1000,
        "maxMilliseconds": max(values) * 1000,
    }


connection = None
token = None


def request(method, path, body=None, raw=False):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    if body is not None:
        headers["Content-Type"] = "application/octet-stream" if raw else "application/json"
        if not raw:
            body = json.dumps(body).encode()
    started = time.perf_counter()
    connection.request(method, path, body=body, headers=headers)
    response = connection.getresponse()
    data = response.read()
    elapsed = time.perf_counter() - started
    if response.status != 200:
        raise RuntimeError(f"Synthetic request failed: {method} {path}: {response.status}")
    return (data if raw and method == "GET" else json.loads(data)), elapsed


try:
    image_info = json.loads(docker("image", "inspect", image))[0]
    docker("volume", "create", volume)
    docker(
        "run",
        "-d",
        "--name",
        name,
        "--read-only",
        "--cpus",
        "1",
        "--memory",
        "256m",
        "--memory-swap",
        "256m",
        "--cap-drop",
        "ALL",
        "--security-opt",
        "no-new-privileges:true",
        "--tmpfs",
        "/tmp:rw,size=32m,mode=1777",
        "-v",
        volume + ":/data",
        "-p",
        "127.0.0.1::8080",
        image,
    )
    port = json.loads(docker("inspect", name))[0]["NetworkSettings"]["Ports"]["8080/tcp"][0][
        "HostPort"
    ]
    for _ in range(100):
        result = subprocess.run(
            ["docker", "exec", name, "dotnet", "Journal.Api.dll", "--health-check"],
            capture_output=True,
        )
        if result.returncode == 0:
            break
        time.sleep(0.2)
    else:
        raise RuntimeError("Synthetic server failed readiness.")
    connection = http.client.HTTPConnection("127.0.0.1", int(port), timeout=30)
    grant, _ = request(
        "POST",
        "/v1/setup",
        {
            "setupCode": docker("exec", name, "cat", "/data/setup-code"),
            "salt": base64.b64encode(os.urandom(16)).decode(),
            "wrappedKey": base64.b64encode(os.urandom(60)).decode(),
            "iterations": 600000,
            "recoverySecret": os.urandom(32).hex(),
            "deviceName": "Sizing fixture",
        },
    )
    token = grant["token"]
    expected, write_times = {}, []
    started = time.perf_counter()
    for index in range(entry_count):
        record = str(uuid.uuid4())
        for revision in range(1, revisions + 1):
            payload = base64.b64encode(os.urandom(payload_bytes)).decode()
            expected[(record, revision)] = hashlib.sha256(payload.encode()).hexdigest()
            _, elapsed = request(
                "PUT",
                "/v1/sync/" + record,
                {
                    "operationId": str(uuid.uuid4()),
                    "baseRevision": revision - 1,
                    "kind": "entry",
                    "payload": payload,
                },
            )
            write_times.append(elapsed)
        if (index + 1) % 1000 == 0:
            print(f"Stored {index + 1} synthetic entries", flush=True)
    write_seconds = time.perf_counter() - started
    after_writes = stats()
    attachment_times = []
    for _ in range(attachment_count):
        attachment = os.urandom(attachment_bytes)
        path = "/v1/attachments/" + str(uuid.uuid4())
        _, elapsed = request("PUT", path, attachment, raw=True)
        attachment_times.append(elapsed)
        recovered, _ = request("GET", path, raw=True)
        if recovered != attachment:
            raise RuntimeError("Attachment readback differs.")
    cursor, seen, page_times = 0, set(), []
    started = time.perf_counter()
    while True:
        page, elapsed = request("GET", f"/v1/sync/?after={cursor}&limit=200")
        page_times.append(elapsed)
        for change in page["changes"]:
            key = (change["recordId"], change["revision"])
            if (
                key in seen
                or expected.get(key) != hashlib.sha256(change["payload"].encode()).hexdigest()
            ):
                raise RuntimeError("Catch-up returned duplicate, unexpected or changed data.")
            seen.add(key)
        cursor = page["cursor"]
        if not page["hasMore"]:
            break
    catchup_seconds = time.perf_counter() - started
    if seen != set(expected):
        raise RuntimeError("Catch-up omitted revisions.")
    after_catchup = stats()
    print("Readback verified; waiting 20 seconds before settled samples", flush=True)
    time.sleep(20)
    settled = [stats() for _ in range(3)]
    storage = docker("exec", name, "du", "-sk", "/data").split()[0]
    report = {
        "scope": (
            "Server only, sequential loopback HTTP, opaque random payloads; "
            "not native encryption/rendering, WAN latency, concurrent load "
            "or minimum hardware proof."
        ),
        "imageID": image_info["Id"],
        "architecture": image_info["Architecture"],
        "limits": {"cpu": 1, "memoryBytes": 256 * 1024 * 1024, "swap": False},
        "fixture": {
            "entries": entry_count,
            "revisionsPerEntry": revisions,
            "payloadBytes": payload_bytes,
            "attachments": attachment_count,
            "attachmentBytes": attachment_bytes,
        },
        "writeSeconds": write_seconds,
        "writes": timings(write_times),
        "attachmentUploads": timings(attachment_times),
        "catchupSeconds": catchup_seconds,
        "pages": timings(page_times),
        "verifiedRevisions": len(seen),
        "dataKiB": int(storage),
        "afterWrites": after_writes,
        "afterCatchup": after_catchup,
        "settledSamples": settled,
    }
    docker("stop", name)
    state = json.loads(docker("inspect", name))[0]["State"]
    if state["ExitCode"] != 0 or state["OOMKilled"]:
        raise RuntimeError("Server exceeded memory or failed clean shutdown.")
    output.write_text(json.dumps(report, indent=2) + "\n")
    print("Measurement complete; exact record/attachment readback and clean shutdown passed.")
finally:
    if connection:
        connection.close()
    subprocess.run(["docker", "rm", "-f", name], capture_output=True, check=False)
    subprocess.run(["docker", "volume", "rm", volume], capture_output=True, check=False)
