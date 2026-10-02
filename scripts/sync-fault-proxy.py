#!/usr/bin/env python3
"""A loopback HTTP proxy in front of a disposable journal server, for sync fault and
bandwidth tests.

Usage: sync-fault-proxy.py <upstream http://127.0.0.1:port> <mode> <stats.json>

It prints "LISTENING http://127.0.0.1:<port>" once ready, counts requests and bytes in
each direction by kind of request, and writes them to <stats.json> after every request.
Modes change only waits (GET /v1/sync/wait) and pushes (PUT /v1/sync/<id>); everything
else is passed through:

  pass          pass everything through, counting (bandwidth measurements)
  cut           answer each wait 504 after 3 s, as a proxy with a short timeout would
  halfopen      hold each wait without forwarding or answering, never closing
  reset         reset the connection 1 s into each wait
  buffer        read each whole response from the server before sending any of it
  instant-true  answer each wait {"changed": true} at once
  cached-false  answer each wait {"changed": false} at once, as a stale cache would
  drop-push     forward the first push, then close the connection without its answer

A request for /__mark/<name> is answered by the proxy itself and recorded with the time,
so a measurement can count only what happened between two marks.

Loopback only; it never contacts anything but the upstream given.
"""

import asyncio
import json
import sys
import time
from urllib.parse import urlsplit

UPSTREAM = urlsplit(sys.argv[1])
MODE = sys.argv[2]
STATS_PATH = sys.argv[3]
stats: dict[str, dict[str, int]] = {}
events: list[list] = []
dropped_push = False
held: list[asyncio.StreamWriter] = []


def kind(method: str, path: str) -> str:
    if path.startswith("/v1/sync/wait"):
        return "wait"
    if path.startswith("/v1/sync/?") or path == "/v1/sync/":
        return "page"
    if method == "PUT" and path.startswith("/v1/sync/"):
        return "push"
    return path.split("?")[0].rstrip("/").split("/")[2] if path.startswith("/v1/") else "other"


def count(name: str, sent: int, received: int) -> None:
    entry = stats.setdefault(name, {"requests": 0, "up": 0, "down": 0})
    entry["requests"] += 1
    entry["up"] += sent
    entry["down"] += received
    events.append([time.time(), name, sent, received])
    with open(STATS_PATH, "w", encoding="utf-8") as file:
        json.dump({"totals": stats, "events": events}, file)


async def read_message(reader: asyncio.StreamReader) -> bytes | None:
    head = await reader.readuntil(b"\r\n\r\n")
    length = 0
    for line in head.split(b"\r\n")[1:]:
        name, _, value = line.partition(b":")
        if name.strip().lower() == b"content-length":
            length = int(value.strip())
    body = await reader.readexactly(length) if length else b""
    return head + body


def with_connection_close(message: bytes) -> bytes:
    head, _, body = message.partition(b"\r\n\r\n")
    lines = [line for line in head.split(b"\r\n") if not line.lower().startswith(b"connection:")]
    return b"\r\n".join(lines + [b"Connection: close"]) + b"\r\n\r\n" + body


def answer(status: str, body: bytes) -> bytes:
    return (
        f"HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n"
        "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    ).encode() + body


async def forward(request: bytes) -> bytes:
    reader, writer = await asyncio.open_connection(UPSTREAM.hostname, UPSTREAM.port)
    writer.write(with_connection_close(request))
    await writer.drain()
    response = await reader.read()
    writer.close()
    return response


async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    global dropped_push
    try:
        request = await read_message(reader)
    except (asyncio.IncompleteReadError, ConnectionError):
        writer.close()
        return
    request_line = request.split(b"\r\n", 1)[0].decode()
    method, path, _ = request_line.split(" ", 2)
    name = kind(method, path)
    response = b""
    if path.startswith("/__mark/"):
        events.append([time.time(), "mark:" + path.removeprefix("/__mark/"), 0, 0])
        with open(STATS_PATH, "w", encoding="utf-8") as file:
            json.dump({"totals": stats, "events": events}, file)
        writer.write(answer("200 OK", b"{}"))
        await writer.drain()
        writer.close()
        return
    try:
        if name == "wait" and MODE == "cut":
            await asyncio.sleep(3)
            response = answer("504 Gateway Timeout", b"")
        elif name == "wait" and MODE == "halfopen":
            held.append(writer)
            return
        elif name == "wait" and MODE == "reset":
            await asyncio.sleep(1)
            writer.transport.abort()
            return
        elif name == "wait" and MODE == "instant-true":
            response = answer("200 OK", b'{"changed":true}')
        elif name == "wait" and MODE == "cached-false":
            response = answer("200 OK", b'{"changed":false}')
        elif name == "push" and MODE == "drop-push" and not dropped_push:
            dropped_push = True
            await forward(request)
            writer.transport.abort()
            name = "push-dropped"
            return
        else:
            response = await forward(request)
        writer.write(response)
        await writer.drain()
    except ConnectionError:
        pass
    finally:
        count(name, len(request), len(response))
        if writer not in held:
            writer.close()


async def main() -> None:
    server = await asyncio.start_server(handle, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    print(f"LISTENING http://127.0.0.1:{port}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
