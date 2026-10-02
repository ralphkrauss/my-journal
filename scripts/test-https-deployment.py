#!/usr/bin/env python3
"""Exercise the real HTTPS compose stack with a disposable, explicitly trusted local CA."""

import base64
import http.client
import json
import os
import ssl
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def verify_mounted_restore(command, backend):
    details = json.loads(run("docker", "inspect", backend))[0]
    image = details["Config"]["Image"]
    source = next(mount["Name"] for mount in details["Mounts"] if mount["Destination"] == "/data")
    target = "journal-restore-check-" + uuid.uuid4().hex
    command("exec", "-T", "journal", "dotnet", "Journal.Api.dll", "--backup", "/data/test-backup")
    run("docker", "volume", "create", target)
    try:
        common = [
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            "--read-only",
            "--tmpfs",
            "/tmp",
            "--mount",
            f"type=volume,source={target},target=/data",
        ]
        run(
            *common,
            "--mount",
            f"type=volume,source={source},target=/source,readonly",
            image,
            "--restore",
            "/source/test-backup",
        )
        # A second validated backup proves the mounted restoration is readable and complete.
        run(*common, image, "--backup", "/data/verified-backup")
    finally:
        run("docker", "volume", "rm", target)


def verify_stack(work):
    project = "journal-https-check-" + uuid.uuid4().hex[:12]
    caddy = work / "Caddyfile"
    source = (ROOT / "deploy/Caddyfile").read_text()
    caddy.write_text(source.replace("\treverse_proxy", "\ttls internal\n\treverse_proxy"))
    override = work / "override.yaml"
    override.write_text(
        "services:\n  proxy:\n    environment:\n      JOURNAL_DOMAIN: localhost\n"
        "    ports: !override\n      - '127.0.0.1::8443'\n      - '127.0.0.1::8080'\n"
        "    volumes:\n      - " + json.dumps(f"{caddy}:/etc/caddy/Caddyfile:ro") + "\n"
    )
    compose = [
        "docker",
        "compose",
        "--project-name",
        project,
        "-f",
        str(ROOT / "deploy/compose.https.yaml"),
        "-f",
        str(override),
    ]
    # Compose interpolates the base before merging the explicit local override.
    environment = os.environ.copy()
    environment["JOURNAL_DOMAIN"] = "localhost"

    def command(*args):
        return subprocess.check_output(
            [*compose, *args], cwd=ROOT, env=environment, text=True
        ).strip()

    try:
        command("up", "--build", "--wait", "--wait-timeout", "120")
        proxy = command("ps", "-q", "proxy")
        backend = command("ps", "-q", "journal")
        for identifier in [proxy, backend]:
            details = json.loads(run("docker", "inspect", identifier))[0]
            assert details["Config"]["User"] not in ["", "0", "root"]
            assert details["HostConfig"]["ReadonlyRootfs"]
        details = json.loads(run("docker", "inspect", backend))[0]
        assert not any(details["NetworkSettings"]["Ports"].values()), (
            "Backend port must stay private"
        )
        port = command("port", "proxy", "8443").rsplit(":", 1)[1]
        certificate = work / "root.crt"
        deadline = time.monotonic() + 15
        while not certificate.exists():
            attempt = subprocess.run(
                [
                    "docker",
                    "cp",
                    f"{proxy}:/data/caddy/pki/authorities/local/root.crt",
                    str(certificate),
                ],
                capture_output=True,
                check=False,
            )
            if attempt.returncode == 0:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("The disposable HTTPS proxy did not create its test certificate")
            time.sleep(0.1)
        context = ssl.create_default_context(cafile=str(certificate))
        # Do not use machine/environment HTTP proxies for this strictly loopback test.
        opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context)
        )
        address = f"https://localhost:{port}"

        def request(path, *, body=None, token=None):
            headers = {"Content-Type": "application/json"}
            if token:
                headers["Authorization"] = "Bearer " + token
            message = urllib.request.Request(
                address + path,
                data=json.dumps(body).encode() if body is not None else None,
                headers=headers,
            )
            try:
                with opener.open(message, timeout=10) as response:
                    return response.status, response.headers, response.read()
            except urllib.error.HTTPError as error:
                return error.code, error.headers, error.read()

        assert request("/ready")[0] == 200
        untrusted = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=ssl.create_default_context()),
        )
        try:
            untrusted.open(address + "/health", timeout=10)
        except urllib.error.URLError as error:
            assert isinstance(error.reason, ssl.SSLCertVerificationError)
        else:
            raise AssertionError("Test CA must not be installed in the machine trust store")
        http_port = command("port", "proxy", "8080").rsplit(":", 1)[1]
        connection = http.client.HTTPConnection("localhost", int(http_port), timeout=10)
        try:
            connection.request("GET", "/health", headers={"Host": "localhost"})
            redirect = connection.getresponse()
            assert redirect.status == 308
            assert redirect.getheader("Location") == "https://localhost/health"
        finally:
            connection.close()
        assert request("/v1/sync/?after=0")[0] == 401
        code = command("exec", "-T", "journal", "cat", "/data/setup-code")
        # Synthetic envelope tests transport/authentication, not encryption interoperability.
        setup = {
            "setupCode": code,
            "salt": base64.b64encode(os.urandom(16)).decode(),
            "wrappedKey": base64.b64encode(os.urandom(60)).decode(),
            "iterations": 600000,
            "recoverySecret": os.urandom(32).hex(),
            "deviceName": "Disposable HTTPS check",
        }
        status, _, data = request("/v1/setup", body=setup)
        assert status == 200, f"HTTPS setup returned {status}"
        grant = json.loads(data)
        status, headers, _ = request("/v1/sync/?after=0", token=grant["token"])
        assert status == 200
        assert headers.get("Cache-Control") == "no-store"
        assert request("/v1/sync/?after=0", token="invalid")[0] == 401
        command("restart", "journal")
        command("up", "--wait", "--wait-timeout", "60")
        assert request("/v1/sync/?after=0", token=grant["token"])[0] == 200
        verify_mounted_restore(command, backend)
        print(
            "HTTPS certificate validation, authentication, private backend, "
            "restart persistence, and mounted-volume restoration passed."
        )
    except Exception:
        print(command("logs", "--no-color", "--tail", "30", "proxy"))
        raise
    finally:
        # Only this unique disposable project and its volumes are removed.
        command("down", "--volumes", "--remove-orphans")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="journal-https-") as directory:
        verify_stack(Path(directory))
