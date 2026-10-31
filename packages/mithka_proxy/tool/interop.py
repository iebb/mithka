#!/usr/bin/env python3
"""Exercise the bundled engine against Xray using loopback HTTP/HTTPS origins.

Usage: python3 tool/interop.py --xray /path/to/xray
Run cargo build --release --locked --lib in native/ first. Requires curl and
openssl. The supplied Xray executable is used only as a local test server.
"""

import argparse
import contextlib
import ctypes
import hashlib
import http.server
import json
import pathlib
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time


PAYLOAD = bytes(range(256)) * 8192
UUID = "d342d11e-d424-4583-b36e-524ab1f0afa4"
PASSWORD = "local-interop-test"


class Origin(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(PAYLOAD)))
        self.end_headers()
        self.wfile.write(PAYLOAD)

    def do_POST(self):
        content = self.rfile.read(int(self.headers["Content-Length"]))
        digest = hashlib.sha256(content).hexdigest().encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(digest)))
        self.end_headers()
        self.wfile.write(digest)

    def log_message(self, *_):
        pass


def unused_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def wait_for_server(port, process):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Xray exited before opening its listener")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError:
            time.sleep(0.02)
    raise TimeoutError("Xray did not open its listener")


def configurations(protocol, port, transport, method, certificate, key):
    secure = transport in ("tls", "wss", "vision")
    ws = transport in ("ws", "wss")
    vision = transport == "vision"
    if protocol == "shadowsocks":
        settings = {"method": method, "password": PASSWORD, "network": "tcp"}
        leaf_settings = {"method": method, "password": PASSWORD}
    elif protocol == "trojan":
        settings = {"clients": [{"password": PASSWORD}]}
        leaf_settings = {"password": PASSWORD}
    else:
        user = {"id": UUID}
        if protocol == "vless":
            user["flow"] = "xtls-rprx-vision" if vision else ""
            settings = {"clients": [user], "decryption": "none"}
            leaf_settings = {"uuid": UUID, "flow": user["flow"]}
        else:
            settings = {"clients": [user]}
            leaf_settings = {"uuid": UUID, "security": method}
    stream = {"network": "ws" if ws else "tcp", "security": "tls" if secure else "none"}
    if secure:
        stream["tlsSettings"] = {
            "minVersion": "1.3",
            "alpn": ["http/1.1"],
            "certificates": [{"certificateFile": str(certificate), "keyFile": str(key)}],
        }
    if ws:
        stream["wsSettings"] = {"path": "/mithka-interop"}
    server = {
        "log": {"loglevel": "debug"},
        "inbounds": [{
            "listen": "127.0.0.1", "port": port, "protocol": protocol,
            "settings": settings, "streamSettings": stream,
        }],
        # Recent Xray releases block loopback destinations by default.
        "outbounds": [{
            "protocol": "freedom",
            "settings": {"finalRules": [{"action": "allow", "ip": ["127.0.0.0/8"]}]},
        }],
    }
    actors = []
    outbounds = []
    if secure:
        actors.append("tls")
        outbounds.append({
            "tag": "tls", "protocol": "tls",
            # Test fixture only: this local server uses a self-signed cert.
            "settings": {"serverName": "localhost", "alpn": ["http/1.1"], "insecure": True},
        })
    if ws:
        actors.append("ws")
        outbounds.append({
            "tag": "ws", "protocol": "ws",
            "settings": {"path": "/mithka-interop", "headers": {"Host": "localhost"}},
        })
    actors.append("protocol")
    outbounds.append({
        "tag": "protocol", "protocol": protocol,
        "settings": {"address": "127.0.0.1", "port": port, **leaf_settings},
    })
    client = {"outbounds": [
        {"tag": "proxy", "protocol": "chain", "settings": {"actors": actors}},
        *outbounds,
    ]}
    return server, client


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xray", required=True, type=pathlib.Path)
    parser.add_argument("--library", type=pathlib.Path)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    library_path = args.library or root / "native/target/release" / (
        "libmithka_proxy.dylib" if sys.platform == "darwin" else "libmithka_proxy.so"
    )
    library = ctypes.CDLL(str(library_path.resolve()))
    library.mithka_proxy_start.argtypes = [ctypes.c_char_p]
    library.mithka_proxy_start.restype = ctypes.c_int64
    library.mithka_proxy_stop.argtypes = [ctypes.c_uint16]
    xray = args.xray.resolve()
    cases = [
        ("shadowsocks", "tcp", cipher)
        for cipher in ("aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305")
    ] + [
        ("trojan", transport, "") for transport in ("tls", "wss")
    ] + [
        ("vless", transport, "") for transport in ("tcp", "tls", "ws", "wss", "vision")
    ] + [
        ("vmess", transport, cipher)
        for transport in ("tcp", "tls", "ws", "wss")
        for cipher in ("aes-128-gcm", "chacha20-poly1305")
    ]
    with tempfile.TemporaryDirectory(prefix="mithka-interop-") as temp, contextlib.ExitStack() as cleanup:
        work = pathlib.Path(temp)
        certificate, key = work / "cert.pem", work / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(key), "-out", str(certificate), "-days", "1",
            "-subj", "/CN=localhost",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        origins = []
        for secure in (False, True):
            origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
            cleanup.callback(origin.server_close)
            cleanup.callback(origin.shutdown)
            if secure:
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.minimum_version = ssl.TLSVersion.TLSv1_3
                context.load_cert_chain(certificate, key)
                origin.socket = context.wrap_socket(origin.socket, server_side=True)
            threading.Thread(target=origin.serve_forever, daemon=True).start()
            origins.append(("https" if secure else "http", origin.server_port))
        for protocol, transport, method in cases:
            label = "/".join(filter(None, (protocol, transport, method)))
            port = unused_port()
            server, client = configurations(protocol, port, transport, method, certificate, key)
            config_path = work / "xray.json"
            config_path.write_text(json.dumps(server))
            with (work / "xray.log").open("w+") as log:
                process = subprocess.Popen(
                    [str(xray), "run", "-config", str(config_path)],
                    cwd=work, stdout=log, stderr=subprocess.STDOUT,
                )
                code = -1
                try:
                    wait_for_server(port, process)
                    code = library.mithka_proxy_start(json.dumps(client).encode())
                    if code < 0:
                        raise RuntimeError(f"Leaf start failed: {code}")
                    for scheme, origin_port in origins:
                        base = [
                            "curl", "--silent", "--show-error", "--fail", "--max-time", "15",
                            "--noproxy", "", "--proxy", f"http://127.0.0.1:{code & 65535}",
                            "--insecure", f"{scheme}://127.0.0.1:{origin_port}/",
                        ]
                        for upload in (False, True):
                            command = base + (["--data-binary", "@-"] if upload else [])
                            result = subprocess.run(
                                command, input=PAYLOAD if upload else None,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
                            )
                            expected = hashlib.sha256(PAYLOAD).hexdigest().encode() if upload else PAYLOAD
                            if result.stdout != expected:
                                raise AssertionError(f"{label}: {scheme} payload differs")
                    print(f"PASS {label}: HTTP + TLS 1.3 HTTPS, 2 MiB download and upload", flush=True)
                except Exception as error:
                    log.flush()
                    log.seek(0)
                    print(f"FAIL {label}\n{log.read()}", file=sys.stderr)
                    if isinstance(error, subprocess.CalledProcessError):
                        print(error.stderr.decode(errors="replace"), file=sys.stderr)
                    raise
                finally:
                    if code >= 0:
                        library.mithka_proxy_stop(code >> 32)
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    print(f"All {len(cases)} reference-server cases passed")


if __name__ == "__main__":
    main()
