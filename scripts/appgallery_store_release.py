#!/usr/bin/env python3
"""Package, sign and submit the HarmonyOS store build to Huawei AppGallery.

The store release publishes an unsigned HarmonyOS hap on the stable GitHub
release ``v<version>``. This script turns that exact hap into the signed
``.app`` AppGallery accepts and submits it through the AppGallery Connect
Publishing API (HarmonyOS 5+, API client authentication).

The store listing reuses the Google Play one: its text, icon and phone
screenshots per language, with the release notes the other stores get.

  tools     copy the pinned packing and signing jars out of the toolchain image
  download  fetch the release hap from GitHub
  listing   read the Google Play listing and its images
  package   pack the hap into an .app and sign it with the release profile
  submit    sync the listing, upload the signed .app and submit it for review

Credentials come from the environment only and are never printed.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
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
# The digest-pinned toolchain image release.yml builds the hap in. Its
# HarmonyOS command-line tools (6.0.2.642) carry the packing and signing jars,
# so the jars are copied out of the image rather than hosted anywhere. The
# container never runs, and the signing secrets never enter it.
TOOLCHAIN_IMAGE = (
    "ghcr.io/niuhuan/harmony-next-flutter-pipeline-docker/image"
    "@sha256:2ec15fafd8f57ff74ea58e4ca934266eb11409169d39ef99b038be07db54e2a9"
)
TOOLCHAIN_LIB = "/opt/harmonyos-tools/command-line-tools/sdk/default/openharmony/toolchains/lib"
TOOLS = {
    "hap-sign-tool.jar": "bb820486777cc28cf3f8a53365fe41ffe6fcd05c31de3387e6ede0ed03a11702",
    "app_packing_tool.jar": "5149d9748cea95e2511f51e6dce8a2e9eac95106537703cee74d234f09098171",
}
ROOT = Path(__file__).resolve().parents[1]
PLAY_API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
# Google Play listing languages and the AppGallery languages they fill.
LISTING_LANGUAGES = {"en-US": "en-US", "zh-CN": "zh-CN"}
# Release-notes locales (shared with App Store Connect) per AppGallery language.
NOTES_LANGUAGES = {"en-US": "en-US", "zh-Hans": "zh-CN"}
# AppGallery caps a Chinese brief introduction at 17 characters, shorter than
# the Play short description, so that language uses its own brief.
BRIEF_LIMITS = {"zh-CN": 17}
BRIEF_INFO = {"zh-CN": "基于TDLib的轻快消息客户端"}
PHONE = 4
TABLET = 5
PC = 19
PORTRAIT = 0
LANDSCAPE = 1
ICON_SIZE = 216
# AppGallery refuses to submit while a supported device lacks screenshots, and
# no Play image fits the tablet (3:2) or PC/2in1 (16:9) ratios. Those devices
# get landscape canvases of real phone screenshots side by side:
# device -> (canvas size, phones per image).
COMPOSED_SCREENSHOTS = {TABLET: ((2400, 1600), 2), PC: ((2560, 1440), 3)}
COMPOSED_COUNT = 3


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


def verify_tools(directory):
    for name, expected in TOOLS.items():
        path = Path(directory) / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise Error(f"{name} does not match its pinned SHA-256")


def extract_tools(directory, run=subprocess.run):
    """Copy the packing and signing jars out of the pinned toolchain image."""
    Path(directory).mkdir(parents=True, exist_ok=True)

    def docker(*args):
        result = run(["docker", *args], capture_output=True, text=True)
        if result.returncode != 0:
            raise Error(f"docker {args[0]} failed: {result.stderr.strip()[-300:]}")
        return result.stdout.strip()

    container = docker("create", "--platform", "linux/amd64", TOOLCHAIN_IMAGE, "/bin/true")
    try:
        for name in TOOLS:
            docker("cp", f"{container}:{TOOLCHAIN_LIB}/{name}", str(Path(directory) / name))
    finally:
        docker("rm", "--force", container)
    verify_tools(directory)
    print("Copied the pinned HarmonyOS tools out of the toolchain image", flush=True)


# --- Google Play listing -----------------------------------------------------


def play_token(service_account):
    from google.auth.transport.requests import Request
    from google.oauth2.service_account import Credentials

    credentials = Credentials.from_service_account_info(
        service_account, scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )
    credentials.refresh(Request())
    return credentials.token


def fetch_play_listing(out, token, opener=urllib.request.urlopen):
    """Save the Google Play listing text and images under [out].

    Reads through a temporary edit that is always deleted, never committed.
    """
    edits = f"{PLAY_API}/{BUNDLE_NAME}/edits"

    def call(method, url, body=None):
        request = urllib.request.Request(
            url,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            method=method,
        )
        try:
            with opener(request, timeout=120) as response:
                data = response.read()
        except urllib.error.HTTPError as error:
            raise Error(f"Google Play {method} returned HTTP {error.code}") from None
        return json.loads(data) if data else {}

    Path(out).mkdir(parents=True, exist_ok=True)
    edit = call("POST", edits, {})["id"]
    listings = []
    try:
        for listing in call("GET", f"{edits}/{edit}/listings").get("listings", []):
            lang = listing["language"]
            if lang not in LISTING_LANGUAGES:
                continue
            images = {}
            for kind in ("icon", "phoneScreenshots"):
                paths = []
                for index, image in enumerate(
                    call("GET", f"{edits}/{edit}/listings/{lang}/{kind}").get("images", []), 1
                ):
                    url = image["url"] if "=" in image["url"] else image["url"] + "=s0"
                    with opener(url, timeout=120) as response:
                        data = response.read()
                    if image.get("sha256") and hashlib.sha256(data).hexdigest() != image["sha256"]:
                        raise Error(f"Google Play {lang} {kind} {index} does not match its SHA-256")
                    path = Path(out) / f"{lang}-{kind}-{index}.png"
                    path.write_bytes(data)
                    paths.append(path.name)
                images[kind] = paths
            listings.append({
                "language": lang,
                "title": listing.get("title", ""),
                "shortDescription": listing.get("shortDescription", ""),
                "fullDescription": listing.get("fullDescription", ""),
                **images,
            })
    finally:
        call("DELETE", f"{edits}/{edit}")
    (Path(out) / "listing.json").write_text(json.dumps(listings, ensure_ascii=False, indent=1))
    print("Read the Google Play listing: " + ", ".join(l["language"] for l in listings), flush=True)
    return listings


def release_notes(version, root=ROOT):
    path = Path(root) / f"distribution/app-store/release-notes-{version}.json"
    try:
        notes = json.loads(path.read_text())
    except FileNotFoundError:
        raise Error(f"{path.relative_to(root)} is missing") from None
    return {lang: notes[locale].strip() for locale, lang in NOTES_LANGUAGES.items() if notes.get(locale)}


def language_infos(listings, notes):
    """The AppGallery language information each Play listing language fills."""
    infos = []
    for listing in listings:
        lang = LISTING_LANGUAGES.get(listing["language"])
        if not lang:
            continue
        info = {
            "lang": lang,
            "appName": listing["title"].strip(),
            "appDesc": listing["fullDescription"].strip(),
            "briefInfo": BRIEF_INFO.get(lang, listing["shortDescription"].strip()),
            "newFeatures": notes.get(lang, ""),
        }
        brief_limit = BRIEF_LIMITS.get(lang, 80)
        for field, limit in (("appName", 64), ("appDesc", 8000), ("briefInfo", brief_limit), ("newFeatures", 1000)):
            if not info[field]:
                raise Error(f"{lang} {field} is empty")
            if len(info[field]) > limit:
                raise Error(f"{lang} {field} exceeds {limit} characters")
        if len({info["appDesc"], info["briefInfo"], info["newFeatures"]}) != 3:
            raise Error(f"{lang} description, brief and release notes must differ")
        if not listing.get("icon") or not 3 <= len(listing.get("phoneScreenshots", [])) <= 10:
            raise Error(f"{lang} needs an icon and 3-10 phone screenshots")
        infos.append(info)
    if "en-US" not in {info["lang"] for info in infos}:
        raise Error("the Google Play listing has no en-US language")
    return infos


def appgallery_icon(source, out):
    from PIL import Image

    with Image.open(source) as image:
        image.convert("RGB").resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS).save(out, optimize=True)
    return out


def composed_screenshots(phone_shots, device, out_dir, prefix):
    """Landscape screenshots for a tablet or PC, built from phone screenshots."""
    from PIL import Image

    (width, height), per_image = COMPOSED_SCREENSHOTS[device]
    phones = [Image.open(path).convert("RGB") for path in phone_shots]
    # The Play screenshots sit on a solid backdrop; reuse its colour.
    background = phones[0].getpixel((0, phones[0].height // 2))
    shot_height = int(height * 0.94)
    shot_width = int(shot_height * phones[0].width / phones[0].height)
    gap = (width - shot_width * per_image) // (per_image + 1)
    out = []
    for index in range(COMPOSED_COUNT):
        canvas = Image.new("RGB", (width, height), background)
        for slot in range(per_image):
            phone = phones[(index * per_image + slot) % len(phones)]
            canvas.paste(
                phone.resize((shot_width, shot_height), Image.LANCZOS),
                (gap + slot * (shot_width + gap), (height - shot_height) // 2),
            )
        path = Path(out_dir) / f"{prefix}-{device}-{index + 1}.jpg"
        canvas.save(path, quality=90)
        out.append(path)
    return out


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
    verify_tools(toolchains)
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

    def update_language(self, info):
        self.call("PUT", "/publish/v3/app-language-info", {"appId": self.app_id}, info)

    def update_files(self, icons, screenshots):
        self.call(
            "PUT",
            "/publish/v3/app-file-info",
            {"appId": self.app_id},
            {"appIconList": icons, "screenShotList": screenshots},
        )

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
                    raise Error(f"upload of {Path(path).name} returned HTTP {response.status}")
        except urllib.error.HTTPError as error:
            raise Error(f"upload of {Path(path).name} returned HTTP {error.code}") from None
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


def device_types(info):
    """The device types the app supports, phone first; each needs its own icon."""
    types = {int(device["deviceType"]) for device in info.get("deviceTypes") or []}
    return [PHONE, *sorted(types - {PHONE})]


def sync_listing(connect, listing_dir, notes, chinese_mainland=False, devices=(PHONE,)):
    """Copy the Google Play listing and the release notes to AppGallery.

    Every supported device type gets the icon. The phone gets the Play phone
    screenshots; a supported tablet or PC gets them composed onto landscape
    canvases of its ratio.
    """
    listing_dir = Path(listing_dir)
    listings = json.loads((listing_dir / "listing.json").read_text())
    infos = {info["lang"]: info for info in language_infos(listings, notes)}
    icons, screenshots = [], []
    with tempfile.TemporaryDirectory() as directory:
        for listing in listings:
            lang = LISTING_LANGUAGES.get(listing["language"])
            if lang not in infos:
                continue
            connect.update_language(infos[lang])
            icon = appgallery_icon(listing_dir / listing["icon"][0], Path(directory) / f"{lang}-icon.png")
            icon_id = connect.upload(icon, chinese_mainland)
            icons.append({"lang": lang, "fileInfoList": [
                {"deviceType": device, "objectIdList": [icon_id], "showType": PORTRAIT} for device in devices
            ]})
            phone_shots = [listing_dir / name for name in listing["phoneScreenshots"]]
            files = [{
                "deviceType": PHONE,
                "objectIdList": [connect.upload(path, chinese_mainland) for path in phone_shots],
                "showType": PORTRAIT,
            }]
            for device in devices:
                if device in COMPOSED_SCREENSHOTS:
                    composed = composed_screenshots(phone_shots, device, directory, lang)
                    files.append({
                        "deviceType": device,
                        "objectIdList": [connect.upload(path, chinese_mainland) for path in composed],
                        "showType": LANDSCAPE,
                    })
            screenshots.append({"lang": lang, "fileInfoList": files})
    connect.update_files(icons, screenshots)
    print("Synced the Google Play listing to AppGallery: " + ", ".join(infos), flush=True)


def submit(connect, app, version, code, chinese_mainland=False, apply=True, listing_dir=None, notes=None):
    info = connect.app_info()
    reason = already_submitted(info, version, code)
    if reason:
        print(f"Skipping AppGallery: {reason}", flush=True)
        return False
    if not apply:
        if listing_dir:
            listings = json.loads((Path(listing_dir) / "listing.json").read_text())
            langs = [info["lang"] for info in language_infos(listings, notes or {})]
            print(f"PLAN sync the Google Play listing for {', '.join(langs)}", flush=True)
        print(f"PLAN upload {Path(app).name} and submit {version} ({code}) for review", flush=True)
        return False
    if listing_dir:
        sync_listing(connect, listing_dir, notes or {}, chinese_mainland, device_types(info))
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
    listing = commands.add_parser("listing")
    listing.add_argument("--out", required=True)
    pack = commands.add_parser("package")
    pack.add_argument("--version", required=True, type=store_version)
    pack.add_argument("--hap", required=True)
    pack.add_argument("--out", required=True)
    pack.add_argument("--toolchains", required=True, help="OpenHarmony toolchains/lib directory")
    send = commands.add_parser("submit")
    send.add_argument("--version", required=True, type=store_version)
    send.add_argument("--app", required=True)
    send.add_argument("--listing", help="Google Play listing directory to sync first")
    send.add_argument("--plan", action="store_true", help="report without uploading or submitting")
    args = parser.parse_args(argv)

    if args.command == "tools":
        extract_tools(args.out)
    elif args.command == "download":
        download(args.version, args.out, os.environ["GITHUB_TOKEN"])
    elif args.command == "listing":
        account = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "")
        if not account:
            raise Error("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is required")
        fetch_play_listing(args.out, play_token(json.loads(account)))
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
            listing_dir=args.listing,
            notes=release_notes(args.version) if args.listing else None,
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Error as error:
        print(f"::error::{error}", flush=True)
        raise SystemExit(1)
