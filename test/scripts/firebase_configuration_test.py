import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "firebase_configuration", ROOT / "scripts/verify_firebase_configuration.py"
)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class FirebaseReleaseConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.options = {
            "appId": "1:123:android:abc",
            "messagingSenderId": "123",
            "projectId": "mithka",
            "apiKey": "public-client-key-for-test",
            "storageBucket": "mithka.firebasestorage.app",
            "iosBundleId": "ad.neko.mithka",
        }
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_android_selects_the_mithka_client_and_rejects_mismatches(self):
        native = {
            "project_info": {
                "project_id": "mithka",
                "project_number": "123",
                "storage_bucket": self.options["storageBucket"],
            },
            "client": [
                {
                    "client_info": {
                        "android_client_info": {"package_name": "other.app"}
                    },
                },
                {
                    "client_info": {
                        "android_client_info": {"package_name": "ad.neko.mithka"},
                        "mobilesdk_app_id": self.options["appId"],
                    },
                    "api_key": [{"current_key": self.options["apiKey"]}],
                },
            ],
        }
        path = self.root / "google-services.json"
        path.write_text(json.dumps(native))
        guard.check_android(path, self.options)
        for field in ("projectId", "messagingSenderId", "apiKey", "appId"):
            options = dict(self.options, **{field: "wrong"})
            with self.subTest(field=field), self.assertRaises(ValueError):
                guard.check_android(path, options)
        native["client"].append(copy.deepcopy(native["client"][1]))
        path.write_text(json.dumps(native))
        with self.assertRaises(ValueError):
            guard.check_android(path, self.options)

    def test_ios_checks_compiled_client_identity(self):
        self.options["appId"] = "1:123:ios:abc"
        native = dict(
            zip(
                (
                    "PROJECT_ID",
                    "GOOGLE_APP_ID",
                    "GCM_SENDER_ID",
                    "API_KEY",
                    "BUNDLE_ID",
                    "STORAGE_BUCKET",
                ),
                (
                    self.options[field]
                    for field in (
                        "projectId",
                        "appId",
                        "messagingSenderId",
                        "apiKey",
                        "iosBundleId",
                        "storageBucket",
                    )
                ),
            )
        )
        path = self.root / "GoogleService-Info.plist"
        path.write_bytes(plistlib.dumps(native, fmt=plistlib.FMT_BINARY))
        guard.check_ios(path, self.options)
        for field in ("PROJECT_ID", "GOOGLE_APP_ID", "BUNDLE_ID", "API_KEY"):
            bad = dict(native, **{field: "wrong"})
            path.write_bytes(plistlib.dumps(bad))
            with self.subTest(field=field), self.assertRaises(ValueError):
                guard.check_ios(path, self.options)

    def test_configuration_errors_never_print_client_values(self):
        output = io.StringIO()
        with (
            patch.object(guard, "options_for", return_value=self.options),
            patch.object(
                guard, "check_android", side_effect=ValueError(self.options["apiKey"])
            ),
            patch("sys.argv", ["verify", "--platform", "android"]),
            contextlib.redirect_stderr(output),
        ):
            self.assertEqual(guard.main(), 1)
        self.assertNotIn(self.options["apiKey"], output.getvalue())
        self.assertIn("verification failed", output.getvalue())


if __name__ == "__main__":
    unittest.main()
