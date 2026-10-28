import importlib.util
import io
import json
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import Mock, patch

SOURCE = (
    Path(__file__).resolve().parents[2] / "scripts/check_google_play_credentials.py"
)
SPEC = importlib.util.spec_from_file_location("play_credentials", SOURCE)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class PlayCredentialsTest(unittest.TestCase):
    def session(self):
        session = Mock()
        session.post.return_value.json.return_value = {"id": "edit-123"}
        session.get.return_value.json.return_value = {"tracks": []}
        return session

    def test_success_reads_tracks_then_discards_the_edit(self):
        session = self.session()
        CHECK.check_access(session)
        session.post.assert_called_once_with(CHECK.BASE, json={}, timeout=30)
        session.get.assert_called_once_with(f"{CHECK.BASE}/edit-123/tracks", timeout=30)
        session.delete.assert_called_once_with(f"{CHECK.BASE}/edit-123", timeout=30)
        self.assertEqual(
            [call[0] for call in session.method_calls], ["post", "get", "delete"]
        )

    def test_failed_track_request_still_deletes_the_edit(self):
        session = self.session()
        session.get.return_value.raise_for_status.side_effect = RuntimeError("failed")
        with self.assertRaises(RuntimeError):
            CHECK.check_access(session)
        session.delete.assert_called_once()

    def test_malformed_track_response_still_deletes_the_edit(self):
        session = self.session()
        session.get.return_value.json.return_value = {"tracks": None}
        with self.assertRaises(ValueError):
            CHECK.check_access(session)
        session.delete.assert_called_once()

    def test_cleanup_failure_is_not_reported_as_success(self):
        session = self.session()
        session.delete.return_value.raise_for_status.side_effect = RuntimeError(
            "failed"
        )
        with self.assertRaises(RuntimeError):
            CHECK.check_access(session)

    def test_report_reads_all_used_codes_and_completed_production(self):
        session = self.session()
        payloads = [
            {
                "tracks": [
                    {
                        "track": "production",
                        "releases": [{"status": "completed", "versionCodes": ["200"]}],
                    },
                    {
                        "track": "beta",
                        "releases": [{"status": "completed", "versionCodes": ["300"]}],
                    },
                    {
                        "track": "production",
                        "releases": [{"status": "draft", "versionCodes": ["400"]}],
                    },
                ]
            },
            {"bundles": [{"versionCode": 500}]},
            {"apks": [{"versionCode": 450}]},
        ]
        responses = []
        for payload in payloads:
            response = Mock()
            response.json.return_value = payload
            responses.append(response)
        session.get.side_effect = responses
        self.assertEqual(
            CHECK.check_access(session, report=True),
            {"production_codes": [200], "highest_version_code": 500},
        )
        session.delete.assert_called_once()

    def test_report_failure_discards_edit_and_does_not_commit(self):
        session = self.session()
        session.get.side_effect = RuntimeError("failed")
        with self.assertRaises(RuntimeError):
            CHECK.check_access(session, report=True)
        session.delete.assert_called_once()

    def test_edit_identifier_cannot_redirect_or_traverse(self):
        for identifier in ["../other", "https://other.example", "", None, 123]:
            with self.subTest(identifier=identifier):
                session = self.session()
                session.post.return_value.json.return_value = {"id": identifier}
                with self.assertRaises(ValueError):
                    CHECK.check_access(session)
                session.get.assert_not_called()
                session.delete.assert_not_called()

    def test_provider_exception_cannot_expose_credentials(self):
        info = {
            "type": "service_account",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
        errors = io.StringIO()
        with (
            patch.dict(
                CHECK.os.environ, {"GOOGLE_PLAY_SERVICE_ACCOUNT_JSON": json.dumps(info)}
            ),
            patch.object(
                CHECK.Credentials,
                "from_service_account_info",
                side_effect=ValueError("private-secret-value"),
            ),
            redirect_stderr(errors),
        ):
            self.assertEqual(CHECK.main(), 1)
        self.assertNotIn("private-secret-value", errors.getvalue())
        self.assertIn("ValueError", errors.getvalue())

    def test_credentials_cannot_send_keys_to_an_unexpected_oauth_host(self):
        info = {"type": "service_account", "token_uri": "https://other.example/token"}
        with (
            patch.dict(
                CHECK.os.environ, {"GOOGLE_PLAY_SERVICE_ACCOUNT_JSON": json.dumps(info)}
            ),
            patch.object(CHECK.Credentials, "from_service_account_info") as credentials,
            redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(CHECK.main(), 1)
            credentials.assert_not_called()


if __name__ == "__main__":
    unittest.main()
