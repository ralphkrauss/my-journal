import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import urllib.request

if len(sys.argv) != 2:
    raise SystemExit("Usage: test-packaged-server.py <server-package-directory>")
package = pathlib.Path(sys.argv[1]).resolve()
launcher = package / "journal-server"
if not launcher.is_file():
    raise SystemExit("The packaged server launcher is missing")
with tempfile.TemporaryDirectory(prefix="journal-packaged-") as fixture:
    data = pathlib.Path(fixture)
    env = dict(
        os.environ,
        Journal__DataDirectory=str(data / "data"),
        ASPNETCORE_URLS="http://127.0.0.1:0",
        DOTNET_ROOT="/nonexistent-runtime",
    )
    log = data / "server.log"
    with log.open("w") as stream:
        process = subprocess.Popen(
            [str(launcher)], env=env, stdout=stream, stderr=subprocess.STDOUT
        )
    try:
        address = None
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError(log.read_text())
            for line in log.read_text().splitlines():
                if "Now listening on: " in line:
                    address = line.split("Now listening on: ", 1)[1].strip()
            if address:
                break
            time.sleep(0.1)
        if not address:
            raise RuntimeError("Packaged server did not become ready")
        with urllib.request.urlopen(address + "/ready", timeout=5) as response:
            assert json.load(response)["status"] == "ready"
        assert (data / "data/setup-code").is_file()
        print("PASS: self-contained server starts with nonexistent DOTNET_ROOT and reports ready")
    finally:
        process.terminate()
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            raise
        print("Packaged server shutdown exit:", process.returncode)
    if process.returncode != 0:
        raise RuntimeError("Packaged server did not shut down cleanly")
