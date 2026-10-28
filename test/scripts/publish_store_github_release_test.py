import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "publisher", ROOT / "scripts/publish_store_github_release.py"
)
PUBLISHER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLISHER)
SOURCE = "a" * 40
CONTROLLER = "b" * 40
PLAN = {
    "version": "1.8.8",
    "source_sha": SOURCE,
    "android_version_code": 1000,
    "date": "20261027",
}


def evidence():
    run = {
        "id": 9,
        "repository": {"full_name": "iebb/mithka"},
        "path": ".github/workflows/release.yml",
        "event": "workflow_dispatch",
        "head_sha": CONTROLLER,
        "status": "completed",
        "conclusion": "failure",
    }
    jobs = [
        {"name": name, "conclusion": "success"}
        for name in [
            f"Required quality gate / Analyze and test release source {SOURCE}",
            "Read pubspec version",
            "Build arm64-v8a APK",
            "Build armeabi-v7a APK",
            "Build Windows x64",
            "Build Windows arm64",
            "Build macOS universal",
            "Build Linux x64",
            "Build Linux arm64",
        ]
    ]
    jobs += [
        {
            "name": "Publish GitHub Release",
            "conclusion": "failure",
            "steps": [{"name": "Publish to GitHub Release", "conclusion": "failure"}],
        },
        {
            "name": "Required quality gate / Merge snapshot skipped",
            "conclusion": "skipped",
        },
    ]
    names = [
        "apk-1.8.8-20261027-arm64-v8a",
        "apk-1.8.8-20261027-armeabi-v7a",
        *[
            f"desktop-{platform}-20261027"
            for platform in [
                "windows-x64",
                "windows-arm64",
                "macos-universal",
                "linux-x64",
                "linux-arm64",
            ]
        ],
        "installer-windows-x64-20261027",
        "installer-windows-arm64-20261027",
        "appimage-linux-x64-20261027",
        "appimage-linux-arm64-20261027",
    ]
    return run, jobs, [{"name": name, "expired": False} for name in names]


class StorePublicationTest(unittest.TestCase):
    def test_published_only_tag_lookup_falls_back_to_unique_authenticated_draft(self):
        missing = PUBLISHER.subprocess.CompletedProcess([], 1, "", "HTTP 404")
        draft = {"id": 7, "tag_name": "v1.8.8", "draft": True}
        with (
            patch.object(PUBLISHER.subprocess, "run", return_value=missing),
            patch.object(PUBLISHER, "api", return_value=[draft]) as api,
        ):
            self.assertEqual(PUBLISHER.existing_release("v1.8.8"), draft)
            api.assert_called_once_with("releases?per_page=100&page=1")
        with (
            patch.object(PUBLISHER.subprocess, "run", return_value=missing),
            patch.object(PUBLISHER, "api", return_value=[draft, draft]),
            self.assertRaises(PUBLISHER.Error),
        ):
            PUBLISHER.existing_release("v1.8.8")

    def test_only_publication_failure_is_recoverable_after_every_build_passed(self):
        run, jobs, artifacts = evidence()
        self.assertEqual(
            PUBLISHER.verify_build(run, jobs, artifacts, SOURCE, CONTROLLER, "1.8.8"),
            "20261027",
        )
        for index in range(9):
            changed = copy.deepcopy(jobs)
            changed[index]["conclusion"] = "failure"
            with self.assertRaises(PUBLISHER.Error):
                PUBLISHER.verify_build(
                    run, changed, artifacts, SOURCE, CONTROLLER, "1.8.8"
                )
        for steps in [
            [{"name": "Verify and list artifacts", "conclusion": "failure"}],
            [
                {"name": "Publish to GitHub Release", "conclusion": "failure"},
                {"name": "Create release tag", "conclusion": "failure"},
            ],
        ]:
            changed = copy.deepcopy(jobs)
            changed[9]["steps"] = steps
            with self.assertRaises(PUBLISHER.Error):
                PUBLISHER.verify_build(
                    run, changed, artifacts, SOURCE, CONTROLLER, "1.8.8"
                )

    def test_wrong_repository_event_controller_and_ambiguous_jobs_are_rejected(self):
        run, jobs, artifacts = evidence()
        for changed in [
            dict(run, event="pull_request"),
            dict(run, head_sha=SOURCE),
            dict(run, repository={"full_name": "fork/mithka"}),
            dict(run, status="in_progress"),
            dict(run, path=".github/workflows/quality.yml"),
        ]:
            with self.assertRaises(PUBLISHER.Error):
                PUBLISHER.verify_build(
                    changed, jobs, artifacts, SOURCE, CONTROLLER, "1.8.8"
                )
        with self.assertRaises(PUBLISHER.Error):
            PUBLISHER.verify_build(
                run, jobs + [jobs[0]], artifacts, SOURCE, CONTROLLER, "1.8.8"
            )

    def test_incomplete_expired_duplicate_or_mixed_date_artifacts_stop_recovery(self):
        run, jobs, artifacts = evidence()
        for changed in [
            artifacts[:-1],
            artifacts + [artifacts[0]],
            [dict(artifacts[0], expired=True)] + artifacts[1:],
            [
                dict(
                    artifacts[0],
                    name=artifacts[0]["name"].replace("20261027", "20261028"),
                )
            ]
            + artifacts[1:],
        ]:
            with self.assertRaises(PUBLISHER.Error):
                PUBLISHER.verify_build(run, jobs, changed, SOURCE, CONTROLLER, "1.8.8")

    def test_source_requires_matching_existing_tags_and_a_nonzero_patch(self):
        def command(*args, data=None):
            if args[:2] == ("git", "show"):
                return (
                    "version: 1.8.8+296" if args[2].endswith("pubspec.yaml") else "1000"
                )
            if args[:2] == ("git", "rev-parse"):
                return SOURCE
            return ""

        with patch.object(PUBLISHER, "command", side_effect=command) as calls:
            self.assertEqual(
                PUBLISHER.verify_source(SOURCE, CONTROLLER)["version"], "1.8.8"
            )
            self.assertFalse(
                any(
                    "push" in call.args or "tag" in call.args
                    for call in calls.call_args_list
                )
            )

        def wrong_tag(*args, data=None):
            return (
                CONTROLLER
                if args[:2] == ("git", "rev-parse")
                else command(*args, data=data)
            )

        with (
            patch.object(PUBLISHER, "command", side_effect=wrong_tag),
            self.assertRaises(PUBLISHER.Error),
        ):
            PUBLISHER.verify_source(SOURCE, CONTROLLER)
        with (
            patch.object(PUBLISHER, "command", return_value="version: 1.9.0+297"),
            self.assertRaises(PUBLISHER.Error),
        ):
            PUBLISHER.verify_source(SOURCE, CONTROLLER)

    def test_canonical_context_is_required_and_a_schedule_cannot_publish(self):
        env = {
            "GITHUB_REPOSITORY": "iebb/mithka",
            "GITHUB_REF": "refs/heads/master",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
        }
        with patch.dict(PUBLISHER.os.environ, env, clear=True):
            PUBLISHER.context(publishing=True)
        for changed in [
            dict(env, GITHUB_REPOSITORY="fork/mithka"),
            dict(env, GITHUB_REF="refs/pull/1/merge"),
            dict(env, GITHUB_EVENT_NAME="pull_request"),
            dict(env, GITHUB_EVENT_NAME="schedule"),
        ]:
            with (
                patch.dict(PUBLISHER.os.environ, changed, clear=True),
                self.assertRaises(PUBLISHER.Error),
            ):
                PUBLISHER.context(publishing=True)

    def test_complete_publication_uses_master_api_target_but_original_source_manifest(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for suffix in PUBLISHER.SUFFIXES:
                (root / f"mithka-1.8.8-20261027-{suffix}").write_bytes(suffix.encode())
            remote = None
            mutations = []
            uploads = []
            uploaded_bytes = {}

            def api(path, payload=None, method=None):
                nonlocal remote
                if payload is None:
                    self.assertEqual(path, "releases/7")
                    return copy.deepcopy(remote)
                mutations.append((path, copy.deepcopy(payload), method))
                self.assertEqual(payload["target_commitish"], "master")
                if remote is None:
                    remote = {"id": 7, "assets": [], **payload}
                else:
                    remote.update(payload)
                return copy.deepcopy(remote)

            def command(*args, data=None):
                if args[:2] == ("git", "show"):
                    return json.dumps({"en-US": "Release notes", "zh-Hans": "发布说明"})
                if args[:2] == ("git", "rev-parse"):
                    return CONTROLLER
                if args[:3] == ("gh", "release", "upload"):
                    self.assertNotIn("--clobber", args)
                    path = Path(args[4])
                    uploads.append(path.name)
                    uploaded_bytes[path.name] = path.read_bytes()
                    remote["assets"].append(
                        {
                            "id": 100 + len(remote["assets"]),
                            "name": path.name,
                            "size": path.stat().st_size,
                            "digest": "sha256:"
                            + hashlib.sha256(path.read_bytes()).hexdigest(),
                        }
                    )
                    return ""
                self.fail(f"unexpected mutation: {args[0]}")

            with (
                patch.object(PUBLISHER, "api", side_effect=api),
                patch.object(
                    PUBLISHER,
                    "existing_release",
                    side_effect=lambda _: copy.deepcopy(remote),
                ),
                patch.object(PUBLISHER, "command", side_effect=command),
                patch.object(PUBLISHER, "verify_source", return_value=PLAN) as tags,
                patch.object(
                    PUBLISHER,
                    "asset_content",
                    side_effect=lambda _id: uploaded_bytes["release-manifest.json"],
                ),
            ):
                PUBLISHER.publish(PLAN, 9, root, 88)
                self.assertEqual(len(uploads), 12)
                self.assertFalse(remote["draft"])
                self.assertEqual(tags.call_count, 3)
                manifest = json.loads((root / "release-manifest.json").read_text())
                self.assertEqual(manifest["source_sha"], SOURCE)
                self.assertEqual(manifest["workflow_run_id"], "9")
                self.assertEqual(manifest["publication_workflow_run_id"], "88")
                self.assertEqual(len(manifest["files"]), 11)
                # A retry with the same provenance and immutable packages is read-only.
                (root / "release-manifest.json").unlink()
                mutations.clear()
                uploads.clear()
                PUBLISHER.publish(PLAN, 9, root, 99)
                self.assertEqual(mutations, [])
                self.assertEqual(uploads, [])
                self.assertEqual(
                    json.loads((root / "release-manifest.json").read_bytes())[
                        "publication_workflow_run_id"
                    ],
                    "88",
                )

    def test_existing_draft_digest_conflict_never_overwrites_or_publishes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for suffix in PUBLISHER.SUFFIXES:
                (root / f"mithka-1.8.8-20261027-{suffix}").write_bytes(b"package")
            bad = {
                "id": 7,
                "draft": True,
                "assets": [
                    {
                        "name": f"mithka-1.8.8-20261027-{PUBLISHER.SUFFIXES[0]}",
                        "size": 7,
                        "digest": "sha256:" + "0" * 64,
                    }
                ],
            }
            with (
                patch.object(PUBLISHER, "existing_release", return_value=bad),
                patch.object(PUBLISHER, "api") as api,
                patch.object(PUBLISHER, "command") as command,
                self.assertRaises(PUBLISHER.Error),
            ):
                PUBLISHER.publish(PLAN, 9, root, 88)
            api.assert_not_called()
            command.assert_not_called()

    def test_downloaded_extra_file_is_rejected_before_any_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for suffix in PUBLISHER.SUFFIXES:
                (root / f"mithka-1.8.8-20261027-{suffix}").write_bytes(b"package")
            (root / "unexpected-package.zip").write_bytes(b"unrelated")
            with (
                patch.object(PUBLISHER, "api") as api,
                self.assertRaises(PUBLISHER.Error),
            ):
                PUBLISHER.publish(PLAN, 9, root, 88)
            api.assert_not_called()


if __name__ == "__main__":
    unittest.main()
