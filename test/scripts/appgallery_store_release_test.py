import importlib.util
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "scripts/appgallery_store_release.py"
SPEC = importlib.util.spec_from_file_location("appgallery_store_release", SOURCE)
AGC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AGC)


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
        if "/oauth2/v1/token" in url:
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

    def test_tools_must_match_their_pinned_digests(self):
        tools = Path(self.directory.name) / "tools"
        with self.assertRaisesRegex(AGC.Error, "pinned SHA-256"):
            AGC.fetch_tools(tools, opener=lambda url, timeout=None: Response(b"tampered"))

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
