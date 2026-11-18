#!/usr/bin/env python3
"""Package, sign and submit the HarmonyOS store build to Huawei AppGallery.

The store release publishes an unsigned HarmonyOS hap on the stable GitHub
release ``v<version>``. This script turns that exact hap into the signed
``.app`` AppGallery accepts and submits it through the AppGallery Connect
Publishing API (HarmonyOS 5+, API client authentication).

  tools     fetch the pinned HarmonyOS packing and signing jars
  download  fetch the release hap from GitHub
  package   pack the hap into an .app and sign it with the release profile
  submit    upload the signed .app and submit it for review

Credentials come from the environment only and are never printed.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

REPO = "iebb/mithka"
BUNDLE_NAME = "ad.neko.mithka"
DEFAULT_APP_ID = "6917622161433777330"
CONNECT_API = "https://connect-api.cloud.huawei.com/api"
# AppGallery states in which this version needs no new submission:
# 0 on shelf, 3 scheduled, 4 in review, 5 update in review, 12 pre-review.
SUBMITTED_STATES = {0, 3, 4, 5, 12}
STORE_VERSION = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.([1-9]\d*)$")
# Official HarmonyOS command-line tools SDK 26.0.0.105 jars (OpenHarmony
# developtools, Apache-2.0), republished on a tools-only GitHub release.
TOOLS_RELEASE = "ohos-signing-tools-26.0.0.105"
TOOLS = {
    "hap-sign-tool.jar": "a434b6747e6c5d0b14e73837a46b39f4816ab25b42d1833d6f767bf867cf616d",
    "app_packing_tool.jar": "7aff2a4737e3b240addc7bd03e1c9c4ba050cd332a3b478f080cf223b904ed3d",
}


class Error(Exception):
    pass


def store_version(value):
    """Return [value] when it is a store version: X.Y.Z with a nonzero patch."""
    if not STORE_VERSION.match(value or ""):
        raise Error(f"{value!r} is not a store version (X.Y.Z with a nonzero patch)")
    return value


def hap_summary(hap):
    """The bundle name, version name and version code a hap declares."""
    with zipfile.ZipFile(hap) as archive:
        try:
            pack_info = json.loads(archive.read("pack.info"))
        except KeyError:
            raise Error(f"{hap} has no pack.info") from None
    app = pack_info["summary"]["app"]
    return app["bundleName"], app["version"]["name"], int(app["version"]["code"])


def check_hap(hap, version):
    bundle, name, code = hap_summary(hap)
    if bundle != BUNDLE_NAME:
        raise Error(f"hap bundle {bundle} is not {BUNDLE_NAME}")
    if name != version:
        raise Error(f"hap version {name} does not match the store version {version}")
    return code


# --- GitHub -----------------------------------------------------------------


def github(url, token, accept="application/vnd.github+json"):
    request = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {token}", "Accept": accept}
    )
    return urllib.request.urlopen(request, timeout=600)


def release_hap_asset(release, version):
    pattern = re.compile(rf"^mithka-{re.escape(version)}-\d{{8}}-ohos-arm64\.hap$")
    assets = [asset for asset in release["assets"] if pattern.match(asset["name"])]
    if len(assets) != 1:
        raise Error(f"release v{version} carries {len(assets)} HarmonyOS haps, not one")
    return assets[0]


def download(version, out, token):
    with github(f"https://api.github.com/repos/{REPO}/releases/tags/v{version}", token) as response:
        release = json.load(response)
    if release.get("draft") or release.get("prerelease"):
        raise Error(f"v{version} is not a published stable release")
    asset = release_hap_asset(release, version)
    digest = hashlib.sha256()
    with github(asset["url"], token, "application/octet-stream") as response, open(out, "wb") as output:
        for chunk in iter(lambda: response.read(1 << 20), b""):
            digest.update(chunk)
            output.write(chunk)
    expected = asset.get("digest")
    if expected and expected != "sha256:" + digest.hexdigest():
        raise Error(f"{asset['name']} does not match its GitHub digest")
    print(f"Downloaded {asset['name']} ({asset['size']} bytes)", flush=True)


def fetch_tools(directory, opener=urllib.request.urlopen):
    Path(directory).mkdir(parents=True, exist_ok=True)
    for name, expected in TOOLS.items():
        url = f"https://github.com/{REPO}/releases/download/{TOOLS_RELEASE}/{name}"
        with opener(url, timeout=600) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise Error(f"{name} does not match its pinned SHA-256")
        (Path(directory) / name).write_bytes(data)
    print(f"Fetched the pinned HarmonyOS tools from {TOOLS_RELEASE}", flush=True)


# --- Packaging and signing ---------------------------------------------------


def java_tool(toolchains, jar, *args, secrets=()):
    result = subprocess.run(
        ["java", "-jar", str(Path(toolchains) / jar), *args],
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    for secret in secrets:
        output = output.replace(secret, "***")
    lines = [line for line in output.splitlines() if "WARNING" not in line]
    print("\n".join(lines[-5:]), flush=True)
    if result.returncode != 0 or re.search(r"\bERROR\b|failed", output, re.IGNORECASE):
        raise Error(f"{jar} {args[0]} failed")


def package(hap, out, version, toolchains, signing):
    code = check_hap(hap, version)
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        # pack.info names the module package entry-default.
        entry = work / "entry-default.hap"
        entry.write_bytes(Path(hap).read_bytes())
        with zipfile.ZipFile(hap) as archive:
            (work / "pack.info").write_bytes(archive.read("pack.info"))
        unsigned = work / "unsigned.app"
        java_tool(
            toolchains, "app_packing_tool.jar",
            "--mode", "app",
            "--hap-path", str(entry),
            "--pack-info-path", str(work / "pack.info"),
            "--out-path", str(unsigned),
            "--force", "true",
        )
        passwords = (signing["keystore_password"], signing["key_password"])
        java_tool(
            toolchains, "hap-sign-tool.jar",
            "sign-app",
            "-mode", "localSign",
            "-keyAlias", signing["key_alias"],
            "-keyPwd", signing["key_password"],
            "-keystoreFile", signing["keystore"],
            "-keystorePwd", signing["keystore_password"],
            "-signAlg", "SHA256withECDSA",
            "-appCertFile", signing["certificate"],
            "-profileFile", signing["profile"],
            "-inFile", str(unsigned),
            "-outFile", str(out),
            secrets=passwords,
        )
        java_tool(
            toolchains, "hap-sign-tool.jar",
            "verify-app",
            "-inFile", str(out),
            "-outCertChain", str(work / "chain.cer"),
            "-outProfile", str(work / "profile.p7b"),
        )
    print(f"Signed {Path(out).name}: {BUNDLE_NAME} {version} ({code})", flush=True)
    return code


def signing_from_env(env):
    keystore_password = env.get("OHOS_RELEASE_KEYSTORE_PASSWORD", "")
    signing = {
        "keystore": env.get("OHOS_RELEASE_KEYSTORE", ""),
        "keystore_password": keystore_password,
        "key_password": env.get("OHOS_RELEASE_KEY_PASSWORD") or keystore_password,
        "key_alias": env.get("OHOS_RELEASE_KEY_ALIAS") or "mithka-release",
        "certificate": env.get("OHOS_RELEASE_CERTIFICATE", ""),
        "profile": env.get("OHOS_RELEASE_PROFILE", ""),
    }
    missing = [name for name, value in signing.items() if not value]
    if missing:
        raise Error("missing HarmonyOS signing input: " + ", ".join(missing))
    for name in ("keystore", "certificate", "profile"):
        if not Path(signing[name]).is_file():
            raise Error(f"HarmonyOS signing {name} file is missing")
    return signing


# --- AppGallery Connect -----------------------------------------------------


class Connect:
    """A minimal AppGallery Connect Publishing API client."""

    def __init__(self, client_id, client_secret, app_id, opener=urllib.request.urlopen, sleep=time.sleep):
        self.client_id = client_id
        self.client_secret = client_secret
        self.app_id = app_id
        self.opener = opener
        self.sleep = sleep
        self.token = None

    def call(self, method, path, query=None, body=None, auth=True):
        url = f"{CONNECT_API}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {"Content-Type": "application/json"}
        if auth:
            headers.update({"client_id": self.client_id, "Authorization": f"Bearer {self.access_token()}"})
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self.opener(request, timeout=120) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            raise Error(f"{method} {path} returned HTTP {error.code}") from None
        ret = payload.get("ret")
        if ret is not None and ret.get("code") != 0:
            raise Error(f"{method} {path} failed: {ret.get('code')} {ret.get('msg')}")
        return payload

    def access_token(self):
        if self.token is None:
            payload = self.call(
                "POST",
                "/oauth2/v1/token",
                body={
                    "grant_type": "client_credentials",
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                },
                auth=False,
            )
            if not payload.get("access_token"):
                raise Error("AppGallery Connect did not issue an access token")
            self.token = payload["access_token"]
        return self.token

    def app_info(self):
        return self.call("GET", "/publish/v3/app-info", {"appId": self.app_id}).get("appInfo") or {}

    def upload(self, path, chinese_mainland):
        data = Path(path).read_bytes()
        target = self.call(
            "GET",
            "/publish/v2/upload-url/for-obs",
            {
                "appId": self.app_id,
                "fileName": Path(path).name,
                "contentLength": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "chineseMainlandFlag": 1 if chinese_mainland else 0,
            },
        )["urlInfo"]
        request = urllib.request.Request(
            target["url"], data=data, headers=target.get("headers") or {}, method=target.get("method", "PUT")
        )
        try:
            with self.opener(request, timeout=1800) as response:
                if response.status != 200:
                    raise Error(f"package upload returned HTTP {response.status}")
        except urllib.error.HTTPError as error:
            raise Error(f"package upload returned HTTP {error.code}") from None
        return target["objectId"]

    def wait_for_package(self, package_id, attempts=60, interval=30):
        for _ in range(attempts):
            states = self.call(
                "GET", "/publish/v3/package/compile/status", {"appId": self.app_id, "pkgIds": package_id}
            ).get("pkgStateList") or []
            status = next((state["successStatus"] for state in states if str(state["pkgId"]) == str(package_id)), 1)
            if status == 0:
                return
            if status == 2:
                raise Error("AppGallery rejected the package while parsing it")
            self.sleep(interval)
        raise Error("AppGallery is still parsing the package; submit it after parsing finishes")


def already_submitted(info, version, code):
    """Why this version needs no new submission, or None when it does."""
    if int(info.get("onShelfVersionCode") or 0) >= code:
        return f"version code {info['onShelfVersionCode']} is already on shelf"
    if info.get("versionNumber") == version and info.get("releaseState") in SUBMITTED_STATES:
        return f"{version} is already submitted (state {info['releaseState']})"
    return None


def submit(connect, app, version, code, chinese_mainland=False, apply=True):
    info = connect.app_info()
    reason = already_submitted(info, version, code)
    if reason:
        print(f"Skipping AppGallery: {reason}", flush=True)
        return False
    if not apply:
        print(f"PLAN upload {Path(app).name} and submit {version} ({code}) for review", flush=True)
        return False
    object_id = connect.upload(app, chinese_mainland)
    package_id = connect.call(
        "PUT",
        "/publish/v3/app-package-info",
        {"appId": connect.app_id},
        {"fileName": Path(app).name, "objectId": object_id},
    ).get("packageId")
    if not package_id:
        raise Error("AppGallery did not return a package ID")
    connect.wait_for_package(package_id)
    connect.call("POST", "/publish/v3/app-submit", {"appId": connect.app_id}, {"releaseType": 1})
    after = connect.app_info()
    print(
        f"Submitted {version} ({code}) to AppGallery: state {after.get('releaseState')}, "
        f"version {after.get('versionNumber')}",
        flush=True,
    )
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    tools = commands.add_parser("tools")
    tools.add_argument("--out", required=True)
    fetch = commands.add_parser("download")
    fetch.add_argument("--version", required=True, type=store_version)
    fetch.add_argument("--out", required=True)
    pack = commands.add_parser("package")
    pack.add_argument("--version", required=True, type=store_version)
    pack.add_argument("--hap", required=True)
    pack.add_argument("--out", required=True)
    pack.add_argument("--toolchains", required=True, help="OpenHarmony toolchains/lib directory")
    send = commands.add_parser("submit")
    send.add_argument("--version", required=True, type=store_version)
    send.add_argument("--app", required=True)
    send.add_argument("--plan", action="store_true", help="report without uploading or submitting")
    args = parser.parse_args(argv)

    if args.command == "tools":
        fetch_tools(args.out)
    elif args.command == "download":
        download(args.version, args.out, os.environ["GITHUB_TOKEN"])
    elif args.command == "package":
        package(args.hap, args.out, args.version, args.toolchains, signing_from_env(os.environ))
    else:
        with zipfile.ZipFile(args.app) as archive:
            (hap,) = [name for name in archive.namelist() if name.endswith(".hap")]
            with tempfile.TemporaryDirectory() as directory:
                archive.extract(hap, directory)
                code = check_hap(Path(directory) / hap, args.version)
        client_id = os.environ.get("AGC_CLIENT_ID", "")
        client_secret = os.environ.get("AGC_CLIENT_SECRET", "")
        if not client_id or not client_secret:
            raise Error("AGC_CLIENT_ID and AGC_CLIENT_SECRET are required")
        connect = Connect(client_id, client_secret, os.environ.get("AGC_APP_ID") or DEFAULT_APP_ID)
        submit(
            connect,
            args.app,
            args.version,
            code,
            chinese_mainland=os.environ.get("AGC_CHINESE_MAINLAND") == "1",
            apply=not args.plan,
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Error as error:
        print(f"::error::{error}", flush=True)
        raise SystemExit(1)
