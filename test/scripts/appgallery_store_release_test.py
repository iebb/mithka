import hashlib
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "scripts/appgallery_store_release.py"
SPEC = importlib.util.spec_from_file_location("appgallery_store_release", SOURCE)
AGC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AGC)


def write_png(path, size=(64, 64), mode="RGBA"):
    from PIL import Image

    Image.new(mode, size, (10, 20, 30, 255)[: len(mode)]).save(path)


def write_listing(directory, languages=("en-US", "zh-CN"), screenshots=3):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    listings = []
    for lang in languages:
        write_png(directory / f"{lang}-icon-1.png", (512, 512))
        shots = []
        for index in range(1, screenshots + 1):
            write_png(directory / f"{lang}-phoneScreenshots-{index}.png", (90, 160), "RGB")
            shots.append(f"{lang}-phoneScreenshots-{index}.png")
        listings.append({
            "language": lang,
            "title": "Mithka",
            "shortDescription": f"A Telegram client ({lang})",
            "fullDescription": f"Mithka is a fast Telegram client. ({lang})",
            "icon": [f"{lang}-icon-1.png"],
            "phoneScreenshots": shots,
        })
    (directory / "listing.json").write_text(json.dumps(listings))
    return listings


NOTES = {"en-US": "Bug fixes.", "zh-CN": "错误修复。"}


def write_hap(path, bundle="ad.neko.mithka", name="1.13.1", code=310, pack_info=True):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("module.json", "{}")
        if pack_info:
            archive.writestr(
                "pack.info",
                json.dumps({"summary": {"app": {"bundleName": bundle, "version": {"name": name, "code": code}}}}),
            )


class Response(io.BytesIO):
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class FakeConnect:
    """Records Publishing API requests and answers them in order."""

    def __init__(self, info, compile_states=(0,)):
        self.requests = []
        self.info = info
        self.compile_states = list(compile_states)

    def __call__(self, request, timeout=None):
        url = request.full_url
        self.requests.append((request.get_method(), url, request.headers, request.data))
        if "/app-language-info" in url or "/app-file-info" in url:
            body = {"ret": {"code": 0}}
        elif "/oauth2/v1/token" in url:
            body = {"access_token": "token", "expires_in": 3600}
        elif "/app-info" in url:
            body = {"ret": {"code": 0}, "appInfo": self.info}
        elif "/upload-url/for-obs" in url:
            body = {"ret": {"code": 0}, "urlInfo": {
                "objectId": "CN/obj.app", "url": "https://obs.example/upload", "method": "PUT",
                "headers": {"x-amz-date": "now"},
            }}
        elif url == "https://obs.example/upload":
            return Response(b"")
        elif "/app-package-info" in url:
            body = {"ret": {"code": 0}, "packageId": "77"}
        elif "/compile/status" in url:
            body = {"ret": {"code": 0}, "pkgStateList": [{"pkgId": "77", "successStatus": self.compile_states.pop(0)}]}
        elif "/app-submit" in url:
            body = {"ret": {"code": 0}}
            self.info = {**self.info, "releaseState": 4, "versionNumber": "1.13.1"}
        else:
            raise AssertionError(url)
        return Response(json.dumps(body).encode())

    def paths(self):
        return [(method, url.split("/api", 1)[-1].split("?")[0]) for method, url, _, _ in self.requests]


class AppGalleryReleaseTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "mithka.app"
        self.app.write_bytes(b"signed app")

    def run_submit(self, fake, **options):
        connect = AGC.Connect("client", "secret", "6917622161433777330", opener=fake, sleep=lambda _: None)
        with patch("sys.stdout", io.StringIO()) as output:
            submitted = AGC.submit(connect, self.app, "1.13.1", 310, **options)
        return submitted, output.getvalue()

    def test_store_versions_need_a_nonzero_patch(self):
        self.assertEqual(AGC.store_version("1.13.1"), "1.13.1")
        for value in ("1.13.0", "1.13", "v1.13.1", "1.13.1-nightly", "01.2.3", ""):
            with self.assertRaises(AGC.Error):
                AGC.store_version(value)

    def test_hap_must_be_mithka_at_the_store_version(self):
        hap = Path(self.directory.name) / "entry.hap"
        write_hap(hap)
        self.assertEqual(AGC.check_hap(hap, "1.13.1"), 310)
        with self.assertRaisesRegex(AGC.Error, "does not match the store version"):
            AGC.check_hap(hap, "1.13.2")
        write_hap(hap, bundle="com.example.other")
        with self.assertRaisesRegex(AGC.Error, "bundle"):
            AGC.check_hap(hap, "1.13.1")
        write_hap(hap, pack_info=False)
        with self.assertRaisesRegex(AGC.Error, "no pack.info"):
            AGC.check_hap(hap, "1.13.1")

    def test_release_must_carry_exactly_one_hap_for_the_version(self):
        release = {"assets": [
            {"name": "mithka-1.13.1-20261201-ohos-arm64.hap"},
            {"name": "mithka-1.13.10-20261201-ohos-arm64.hap"},
            {"name": "mithka-1.13.1-20261201-android-arm64-v8a.apk"},
        ]}
        self.assertEqual(AGC.release_hap_asset(release, "1.13.1")["name"], "mithka-1.13.1-20261201-ohos-arm64.hap")
        with self.assertRaisesRegex(AGC.Error, "2 HarmonyOS haps"):
            AGC.release_hap_asset({"assets": release["assets"] * 2}, "1.13.1")

    def extract(self, contents, fail=None):
        """Run extract_tools against a fake docker that copies [contents]."""
        commands = []

        def run(command, capture_output, text):
            commands.append(command)
            verb = command[1]
            if verb == fail:
                return subprocess.CompletedProcess(command, 1, "", "denied")
            if verb == "cp":
                name = command[2].rsplit("/", 1)[1]
                Path(command[3]).write_bytes(contents[name])
            return subprocess.CompletedProcess(command, 0, "c0ffee\n" if verb == "create" else "", "")

        tools = Path(self.directory.name) / "tools"
        with patch("sys.stdout", io.StringIO()):
            try:
                AGC.extract_tools(tools, run=run)
            finally:
                self.commands = commands
        return tools

    def test_tools_come_from_the_pinned_image_and_match_their_digests(self):
        contents = {"hap-sign-tool.jar": b"sign", "app_packing_tool.jar": b"pack"}
        digests = {name: hashlib.sha256(data).hexdigest() for name, data in contents.items()}
        with patch.dict(AGC.TOOLS, digests, clear=True):
            tools = self.extract(contents)
            self.assertEqual((tools / "hap-sign-tool.jar").read_bytes(), b"sign")
            self.assertEqual(self.commands[0][:4], ["docker", "create", "--platform", "linux/amd64"])
            self.assertIn("@sha256:", self.commands[0][4])
            self.assertEqual(self.commands[1][2], f"c0ffee:{AGC.TOOLCHAIN_LIB}/hap-sign-tool.jar")
            self.assertEqual(self.commands[-1], ["docker", "rm", "--force", "c0ffee"])

            with self.assertRaisesRegex(AGC.Error, "pinned SHA-256"):
                self.extract({**contents, "app_packing_tool.jar": b"tampered"})
            self.assertEqual(self.commands[-1], ["docker", "rm", "--force", "c0ffee"])

            with self.assertRaisesRegex(AGC.Error, "docker cp failed: denied"):
                self.extract(contents, fail="cp")
            self.assertEqual(self.commands[-1], ["docker", "rm", "--force", "c0ffee"])

    def test_listing_fills_each_language_from_google_play(self):
        listings = write_listing(Path(self.directory.name) / "listing")
        infos = AGC.language_infos(listings, NOTES)
        self.assertEqual([info["lang"] for info in infos], ["en-US", "zh-CN"])
        self.assertEqual(infos[1], {
            "lang": "zh-CN",
            "appName": "Mithka",
            "appDesc": "Mithka is a fast Telegram client. (zh-CN)",
            # AppGallery caps a Chinese brief at 17 characters.
            "briefInfo": "基于TDLib的轻快消息客户端",
            "newFeatures": "错误修复。",
        })
        self.assertLessEqual(len(infos[1]["briefInfo"]), 17)
        self.assertEqual(infos[0]["briefInfo"], "A Telegram client (en-US)")

    def test_listing_rejects_what_appgallery_would_refuse(self):
        def broken(**changes):
            listing = write_listing(Path(self.directory.name) / "listing", ("en-US",))[0]
            return [{**listing, **changes}]

        cases = [
            (broken(shortDescription="x" * 81), "briefInfo exceeds 80"),
            (broken(shortDescription="Same", fullDescription="Same"), "must differ"),
            (broken(title=" "), "appName is empty"),
            (broken(phoneScreenshots=["a.png", "b.png"]), "3-10 phone screenshots"),
            (broken(language="zh-CN"), "no en-US"),
        ]
        for listings, message in cases:
            with self.subTest(message), self.assertRaisesRegex(AGC.Error, message):
                AGC.language_infos(listings, NOTES)
        with self.assertRaisesRegex(AGC.Error, "newFeatures is empty"):
            AGC.language_infos(broken(), {})

    def test_release_notes_map_store_locales(self):
        root = Path(self.directory.name)
        (root / "distribution/app-store").mkdir(parents=True)
        (root / "distribution/app-store/release-notes-1.13.1.json").write_text(
            json.dumps({"en-US": " Fixes. ", "zh-Hans": "修复。", "ja": "修正。"})
        )
        self.assertEqual(AGC.release_notes("1.13.1", root), {"en-US": "Fixes.", "zh-CN": "修复。"})
        with self.assertRaisesRegex(AGC.Error, "release-notes-1.13.2.json is missing"):
            AGC.release_notes("1.13.2", root)

    def test_play_listing_is_read_through_an_edit_that_is_always_deleted(self):
        requests = []

        def opener(request, timeout=None):
            if isinstance(request, str):
                requests.append(("GET", request))
                return Response(b"png")
            method, url = request.get_method(), request.full_url
            requests.append((method, url))
            if method == "POST":
                return Response(b'{"id": "e1"}')
            if method == "DELETE":
                return Response(b"")
            if url.endswith("/listings"):
                return Response(json.dumps({"listings": [
                    {"language": "en-US", "title": "Mithka", "shortDescription": "s", "fullDescription": "f"},
                    {"language": "ja-JP", "title": "Mithka"},
                ]}).encode())
            if url.endswith("/phoneScreenshots") and fail:
                raise AGC.urllib.error.HTTPError(url, 500, "", {}, None)
            return Response(json.dumps({"images": [
                {"url": "https://play.example/i", "sha256": hashlib.sha256(b"png").hexdigest()}
            ]}).encode())

        out = Path(self.directory.name) / "play"
        fail = False
        with patch("sys.stdout", io.StringIO()):
            listings = AGC.fetch_play_listing(out, "token", opener=opener)
        self.assertEqual([l["language"] for l in listings], ["en-US"])
        self.assertEqual(listings[0]["phoneScreenshots"], ["en-US-phoneScreenshots-1.png"])
        self.assertIn(("GET", "https://play.example/i=s0"), requests)
        self.assertEqual(json.loads((out / "listing.json").read_text()), listings)
        self.assertEqual(requests[-1][0], "DELETE")
        self.assertFalse(any(method == "POST" and ":commit" in url for method, url in requests))

        requests.clear()
        fail = True
        with self.assertRaisesRegex(AGC.Error, "HTTP 500"):
            AGC.fetch_play_listing(out, "token", opener=opener)
        self.assertEqual(requests[-1][0], "DELETE")

    def test_signing_needs_every_secret_and_reuses_the_keystore_password(self):
        with self.assertRaisesRegex(AGC.Error, "keystore, keystore_password"):
            AGC.signing_from_env({})
        files = {}
        for name in ("p12", "cer", "p7b"):
            files[name] = Path(self.directory.name) / f"release.{name}"
            files[name].write_bytes(b"x")
        signing = AGC.signing_from_env({
            "OHOS_RELEASE_KEYSTORE": str(files["p12"]),
            "OHOS_RELEASE_CERTIFICATE": str(files["cer"]),
            "OHOS_RELEASE_PROFILE": str(files["p7b"]),
            "OHOS_RELEASE_KEYSTORE_PASSWORD": "pw",
        })
        self.assertEqual((signing["key_password"], signing["key_alias"]), ("pw", "mithka-release"))

    def test_submission_uploads_waits_for_parsing_then_submits(self):
        fake = FakeConnect({"releaseState": 0, "versionNumber": "1.12.8", "onShelfVersionCode": 304}, compile_states=(1, 0))
        submitted, output = self.run_submit(fake)
        self.assertTrue(submitted)
        self.assertEqual(fake.paths(), [
            ("POST", "/oauth2/v1/token"),
            ("GET", "/publish/v3/app-info"),
            ("GET", "/publish/v2/upload-url/for-obs"),
            ("PUT", "https://obs.example/upload"),
            ("PUT", "/publish/v3/app-package-info"),
            ("GET", "/publish/v3/package/compile/status"),
            ("GET", "/publish/v3/package/compile/status"),
            ("POST", "/publish/v3/app-submit"),
            ("GET", "/publish/v3/app-info"),
        ])
        _, upload_url, _, _ = fake.requests[2]
        self.assertIn("chineseMainlandFlag=0", upload_url)
        self.assertIn("contentLength=10", upload_url)
        package = json.loads(fake.requests[4][3])
        self.assertEqual(package, {"fileName": "mithka.app", "objectId": "CN/obj.app"})
        self.assertEqual(json.loads(fake.requests[7][3]), {"releaseType": 1})
        self.assertIn("state 4", output)

    def test_submission_syncs_the_play_listing_before_the_package(self):
        listing = Path(self.directory.name) / "listing"
        write_listing(listing)
        fake = FakeConnect({
            "releaseState": 0, "versionNumber": "1.12.8", "onShelfVersionCode": 304,
            # Phone, PC/2in1 and tablet, as AppGallery lists them.
            "deviceTypes": [{"deviceType": 19}, {"deviceType": 4}, {"deviceType": 5}],
        })
        uploads = []
        sizes = {}
        upload = AGC.Connect.upload

        def record(connect, path, chinese_mainland):
            uploads.append(Path(path).name)
            if Path(path).suffix in (".png", ".jpg"):
                from PIL import Image

                with Image.open(path) as image:
                    sizes[Path(path).name] = image.size
                    if Path(path).name.endswith("-icon.png"):
                        self.assertEqual((image.size, image.mode), ((216, 216), "RGB"))
            return upload(connect, path, chinese_mainland)

        with patch.object(AGC.Connect, "upload", record):
            submitted, output = self.run_submit(fake, listing_dir=listing, notes=NOTES)
        self.assertTrue(submitted)
        paths = fake.paths()
        self.assertEqual(paths.count(("PUT", "/publish/v3/app-language-info")), 2)
        files = paths.index(("PUT", "/publish/v3/app-file-info"))
        self.assertLess(files, paths.index(("PUT", "/publish/v3/app-package-info")))
        self.assertEqual(uploads[:4], ["en-US-icon.png", "en-US-phoneScreenshots-1.png",
                                       "en-US-phoneScreenshots-2.png", "en-US-phoneScreenshots-3.png"])
        self.assertEqual(uploads[-1], "mithka.app")
        body = json.loads(fake.requests[files][3])
        self.assertEqual([icon["lang"] for icon in body["appIconList"]], ["en-US", "zh-CN"])
        # Every supported device gets the icon; AppGallery blocks submission
        # while any of them lacks one.
        self.assertEqual(body["appIconList"][0]["fileInfoList"], [
            {"deviceType": device, "objectIdList": ["CN/obj.app"], "showType": 0} for device in (4, 5, 19)
        ])
        # AppGallery blocks submission while a supported device lacks
        # screenshots: the tablet (3:2) and PC (16:9) get landscape canvases
        # composed from the phone screenshots.
        self.assertEqual(body["screenShotList"][1]["fileInfoList"], [
            {"deviceType": 4, "objectIdList": ["CN/obj.app"] * 3, "showType": 0},
            {"deviceType": 5, "objectIdList": ["CN/obj.app"] * 3, "showType": 1},
            {"deviceType": 19, "objectIdList": ["CN/obj.app"] * 3, "showType": 1},
        ])
        self.assertEqual(sizes["en-US-5-1.jpg"], (2400, 1600))
        self.assertEqual(sizes["zh-CN-19-3.jpg"], (2560, 1440))
        zh = [json.loads(data) for method, url, _, data in fake.requests if "/app-language-info" in url][1]
        self.assertEqual((zh["lang"], zh["newFeatures"]), ("zh-CN", "错误修复。"))
        self.assertIn("Synced the Google Play listing to AppGallery: en-US, zh-CN", output)

    def test_a_version_already_in_review_or_on_shelf_is_not_resubmitted(self):
        for info in (
            {"releaseState": 4, "versionNumber": "1.13.1", "onShelfVersionCode": 304},
            {"releaseState": 0, "versionNumber": "1.13.1", "onShelfVersionCode": 310},
        ):
            fake = FakeConnect(info)
            submitted, output = self.run_submit(fake)
            self.assertFalse(submitted)
            self.assertIn("Skipping AppGallery", output)
            self.assertEqual(fake.paths()[-1], ("GET", "/publish/v3/app-info"))

    def test_plan_reads_state_without_uploading(self):
        fake = FakeConnect({"releaseState": 7, "versionNumber": "", "onShelfVersionCode": 0})
        submitted, output = self.run_submit(fake, apply=False)
        self.assertFalse(submitted)
        self.assertIn("PLAN upload", output)
        self.assertEqual(len(fake.paths()), 2)

        listing = Path(self.directory.name) / "listing"
        write_listing(listing)
        fake = FakeConnect({"releaseState": 7, "versionNumber": "", "onShelfVersionCode": 0})
        _, output = self.run_submit(fake, apply=False, listing_dir=listing, notes=NOTES)
        self.assertIn("PLAN sync the Google Play listing for en-US, zh-CN", output)
        self.assertEqual(len(fake.paths()), 2)

    def test_a_rejected_package_is_never_submitted(self):
        fake = FakeConnect({"releaseState": 7, "onShelfVersionCode": 0}, compile_states=(2,))
        with self.assertRaisesRegex(AGC.Error, "rejected the package"):
            self.run_submit(fake)
        self.assertNotIn(("POST", "/publish/v3/app-submit"), fake.paths())

    def test_api_errors_report_codes_but_not_credentials(self):
        def opener(request, timeout=None):
            return Response(json.dumps({"ret": {"code": 204144660, "msg": "no permission"}}).encode())

        connect = AGC.Connect("client", "very-secret", "1", opener=opener)
        with self.assertRaises(AGC.Error) as raised:
            connect.call("GET", "/publish/v3/app-info", auth=False)
        self.assertIn("204144660", str(raised.exception))
        self.assertNotIn("very-secret", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
