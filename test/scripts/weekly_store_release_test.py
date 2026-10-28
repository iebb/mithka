import importlib.util
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "scripts/weekly_store_release.py"
SPEC = importlib.util.spec_from_file_location("weekly_store_release", SOURCE)
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class WeeklyReleaseTest(unittest.TestCase):
    def test_package_recovery_reuses_its_recorded_dispatch_and_never_rebuilds(self):
        plan = {"version": "1.8.8", "source_sha": "a" * 40}
        original = {"id": 9}
        intent = {
            "workflow_sha": "c" * 40,
            "started_after": "2026-10-27T00:00:00+00:00",
        }
        recovery = {"id": 11, "created_at": "2026-10-27T00:00:01Z"}
        with (
            patch.object(RELEASE, "command") as command,
            patch.object(RELEASE, "package_intent", return_value=(intent, False)),
            patch.object(RELEASE, "runs", return_value=[recovery]),
            patch.object(
                RELEASE,
                "api",
                return_value={"status": "completed", "conclusion": "success"},
            ),
            patch.object(RELEASE, "dispatch") as dispatch,
            patch.object(RELEASE, "wait_run") as wait,
        ):
            self.assertEqual(
                RELEASE.recover_github_publication(plan, original, "b" * 40), recovery
            )
            self.assertIn("--verify", command.call_args.args)
            dispatch.assert_not_called()
            wait.assert_called_once_with(recovery, "c" * 40, "github-store-publish.yml")

    def test_failed_publication_can_resume_only_after_a_real_publisher_correction(self):
        plan = {"version": "1.8.8", "source_sha": "a" * 40}
        old_intent = {
            "workflow_sha": "c" * 40,
            "started_after": "2026-10-27T00:00:00+00:00",
        }
        new_intent = dict(old_intent, workflow_sha="d" * 40)
        old = {"id": 11, "created_at": "2026-10-27T00:00:01Z"}
        failed = {
            "status": "completed",
            "conclusion": "failure",
            "head_sha": "c" * 40,
            "path": ".github/workflows/github-store-publish.yml",
            "event": "workflow_dispatch",
        }
        head = {"object": {"sha": "d" * 40}}
        for changed in (False, True):
            with (
                patch.object(
                    RELEASE,
                    "command",
                    return_value="scripts/publish_store_github_release.py"
                    if changed
                    else "",
                ),
                patch.object(
                    RELEASE,
                    "package_intent",
                    side_effect=[(old_intent, False), (new_intent, True)],
                ) as intents,
                patch.object(RELEASE, "runs", side_effect=[[old], []]),
                patch.object(RELEASE, "api", side_effect=[failed, head, head]),
                patch.object(RELEASE, "dispatch", return_value={"id": 12}) as dispatch,
                patch.object(
                    RELEASE,
                    "wait_run",
                    side_effect=None
                    if changed
                    else RELEASE.Error("old attempt failed"),
                ),
            ):
                if changed:
                    self.assertEqual(
                        RELEASE.recover_github_publication(plan, {"id": 9}, "b" * 40),
                        {"id": 12},
                    )
                    self.assertEqual(
                        intents.call_args.kwargs["retry_controller"], "d" * 40
                    )
                    self.assertEqual(
                        dispatch.call_args.args[0], "github-store-publish.yml"
                    )
                else:
                    with self.assertRaises(RELEASE.Error):
                        RELEASE.recover_github_publication(plan, {"id": 9}, "b" * 40)
                    self.assertEqual(intents.call_count, 1)
                    dispatch.assert_not_called()

    def test_unknown_recovery_is_not_redispatched_and_failed_builds_cannot_reserve_it(
        self,
    ):
        plan = {"version": "1.8.8", "source_sha": "a" * 40}
        intent = {
            "workflow_sha": "c" * 40,
            "started_after": "2026-10-27T00:00:00+00:00",
        }
        with (
            patch.object(RELEASE, "command"),
            patch.object(RELEASE, "package_intent", return_value=(intent, False)),
            patch.object(RELEASE, "runs", return_value=[]),
            patch.object(RELEASE, "dispatch") as dispatch,
            self.assertRaises(RELEASE.Error),
        ):
            RELEASE.recover_github_publication(plan, {"id": 9}, "b" * 40)
        dispatch.assert_not_called()
        with (
            patch.object(
                RELEASE, "command", side_effect=RELEASE.Error("build evidence failed")
            ),
            patch.object(RELEASE, "package_intent") as marker,
            self.assertRaises(RELEASE.Error),
        ):
            RELEASE.recover_github_publication(plan, {"id": 9}, "b" * 40)
        marker.assert_not_called()

    def test_completion_waits_for_stores_development_bump_and_same_version_github_packages(
        self,
    ):
        events = []
        plan = {"version": "1.8.8", "source_sha": "a" * 40}
        with (
            patch.object(
                RELEASE.argparse.ArgumentParser,
                "parse_args",
                return_value=argparse.Namespace(
                    operation="release", release_key="2026-10-27"
                ),
            ),
            patch.object(RELEASE, "assert_context"),
            patch.object(RELEASE, "play_state", return_value={}),
            patch.object(RELEASE, "asc_state", return_value={}),
            patch.object(RELEASE, "prepare", return_value=plan),
            patch.object(
                RELEASE, "submit", side_effect=lambda _plan: events.append("stores")
            ),
            patch.object(
                RELEASE,
                "advance_development_version",
                side_effect=lambda _plan: events.append("development"),
            ),
            patch.object(
                RELEASE,
                "publish_github_release",
                side_effect=lambda _plan: events.append("github"),
            ),
            patch.object(
                RELEASE,
                "record_completion",
                side_effect=lambda _plan: events.append("complete"),
            ),
        ):
            self.assertEqual(RELEASE.main(), 0)
        self.assertEqual(events, ["stores", "development", "github", "complete"])

    def test_post_bump_quality_is_requested_only_when_missing(self):
        with patch.object(
            RELEASE, "api", side_effect=[{"workflow_runs": []}, None]
        ) as api:
            RELEASE.ensure_master_quality("a" * 40)
            self.assertEqual(api.call_count, 2)
            self.assertEqual(api.call_args.args[1], {"ref": "master", "inputs": {}})
        with patch.object(
            RELEASE, "api", return_value={"workflow_runs": [{"id": 1}]}
        ) as api:
            RELEASE.ensure_master_quality("a" * 40)
            self.assertEqual(api.call_count, 1)

    def test_failed_base_quality_cannot_reserve_another_store_snapshot(self):
        with patch.object(
            RELEASE,
            "api",
            return_value={
                "workflow_runs": [
                    {"id": 1, "status": "completed", "conclusion": "failure"}
                ]
            },
        ):
            with self.assertRaises(RELEASE.Error):
                RELEASE.validate_release_base("a" * 40)

    def test_github_packages_require_the_store_source_version_and_server_digests(self):
        plan = {"source_sha": "a" * 40, "version": "1.8.8", "android_version_code": 500}
        suffixes = [
            "android-arm64-v8a.apk",
            "android-armeabi-v7a.apk",
            "windows-x64.zip",
            "windows-arm64.zip",
            "windows-x64-setup.exe",
            "windows-arm64-setup.exe",
            "macos-universal.zip",
            "linux-x64.tar.gz",
            "linux-arm64.tar.gz",
            "linux-x64.AppImage",
            "linux-arm64.AppImage",
        ]
        files = {
            f"mithka-1.8.8-20261027-{suffix}": {"sha256": "c" * 64, "size": 100}
            for suffix in suffixes
        }
        manifest = dict(plan, files=files)
        release = {
            "tag_name": "v1.8.8",
            "draft": False,
            "prerelease": False,
            "assets": [
                {
                    "name": name,
                    "digest": "sha256:" + value["sha256"],
                    "size": value["size"],
                }
                for name, value in files.items()
            ],
        }
        RELEASE.verify_github_packages(release, manifest, plan)
        release["assets"][0]["digest"] = "sha256:" + "d" * 64
        with self.assertRaises(RELEASE.Error):
            RELEASE.verify_github_packages(release, manifest, plan)
        release["assets"][0]["digest"] = "sha256:" + "c" * 64
        for changed in [
            dict(manifest, version="1.8.0"),
            dict(manifest, source_sha="b" * 40),
            dict(manifest, files={}),
        ]:
            with self.assertRaises(RELEASE.Error):
                RELEASE.verify_github_packages(release, changed, plan)
        release["draft"] = True
        with self.assertRaises(RELEASE.Error):
            RELEASE.verify_github_packages(release, manifest, plan)

    def test_development_advances_one_minor_from_the_submitted_version_only(self):
        self.assertEqual(RELEASE.development_target("1.8.8", "1.8.8"), "1.9.0")
        self.assertEqual(RELEASE.development_target("1.9.11", "1.9.11"), "1.10.0")
        self.assertIsNone(RELEASE.development_target("1.9.0", "1.8.8"))
        self.assertIsNone(RELEASE.development_target("1.9.2", "1.8.8"))
        with self.assertRaises(RELEASE.Error):
            RELEASE.development_target("1.8.9", "1.8.8")

    def test_state_lookup_failure_reports_only_sanitized_class_and_status(self):
        result = subprocess.CompletedProcess(
            [],
            1,
            "",
            "private-key-or-response\nStore state lookup failed (MithkaAppStoreRelease::ApiError, HTTP 503)\nother-private-value",
        )
        with patch.object(RELEASE.subprocess, "run", return_value=result):
            with self.assertRaises(RELEASE.Error) as raised:
                RELEASE.command("ruby", "scripts/store_release_state.rb")
        self.assertEqual(
            str(raised.exception),
            "Store state lookup failed (MithkaAppStoreRelease::ApiError, HTTP 503)",
        )

    def test_a_later_friday_resumes_unfinished_snapshots_before_allocating(self):
        tags = ["store-2026-10-27", "store-v1.8.8"]
        self.assertEqual(RELEASE.release_key(None, tags, "2026-10-30"), "2026-10-27")
        with self.assertRaises(RELEASE.Error):
            RELEASE.release_key("2026-10-30", tags, "2026-10-30")
        tags.append("store-complete-2026-10-27")
        self.assertEqual(RELEASE.release_key(None, tags, "2026-10-30"), "2026-10-30")
        tags.extend(["store-2026-10-29", "store-2026-10-30"])
        with self.assertRaises(RELEASE.Error):
            RELEASE.release_key(None, tags, "2026-11-06")

    def test_normal_patch_is_preserved_or_advanced_above_used_versions(self):
        self.assertEqual(RELEASE.choose_version("1.8.6", ["1.7.11", "1.8.5"]), "1.8.6")
        self.assertEqual(RELEASE.choose_version("1.8.6", ["1.8.7", "1.8.4"]), "1.8.8")
        self.assertEqual(RELEASE.choose_version("1.8.0", []), "1.8.1")
        self.assertEqual(RELEASE.choose_version("1.8.11", ["1.8.9"]), "1.8.11")

    def test_new_major_or_minor_and_abnormal_versions_require_attention(self):
        for used in [["1.9.0"], ["2.0.1"], ["1.8"], ["1.8.01"]]:
            with self.subTest(used=used), self.assertRaises(RELEASE.Error):
                RELEASE.choose_version("1.8.6", used)

    def test_android_code_exceeds_live_and_nightly_even_if_clock_lags(self):
        self.assertEqual(RELEASE.next_android_code([100, 300, 200], 250), 301)
        self.assertEqual(RELEASE.next_android_code([100], 350), 350)
        with self.assertRaises(RELEASE.Error):
            RELEASE.next_android_code([2100000000], 100)

    def test_provider_and_branch_context_cannot_be_overridden(self):
        good = {
            "GITHUB_REPOSITORY": "iebb/mithka",
            "GITHUB_REF": "refs/heads/master",
            "GITHUB_EVENT_NAME": "schedule",
        }
        RELEASE.assert_context(good)
        for key, value in [
            ("GITHUB_REPOSITORY", "attacker/mithka"),
            ("GITHUB_REF", "refs/heads/nightly"),
            ("GITHUB_EVENT_NAME", "pull_request"),
        ]:
            with self.assertRaises(RELEASE.Error):
                RELEASE.assert_context(dict(good, **{key: value}))

    def test_failed_or_changed_native_run_is_never_treated_as_success(self):
        run = {"id": 10}
        state = {
            "head_sha": "a" * 40,
            "path": ".github/workflows/ios-testflight.yml",
            "event": "workflow_dispatch",
            "status": "completed",
            "conclusion": "failure",
        }
        with (
            patch.object(RELEASE, "api", return_value=state),
            self.assertRaises(RELEASE.Error),
        ):
            RELEASE.wait_run(run, "a" * 40, "ios-testflight.yml")
        state["conclusion"] = "success"
        with (
            patch.object(RELEASE, "api", return_value=state),
            self.assertRaises(RELEASE.Error),
        ):
            RELEASE.wait_run(run, "b" * 40, "ios-testflight.yml")

    def play_run_and_jobs(self):
        run = {
            "id": 99,
            "head_sha": "a" * 40,
            "path": ".github/workflows/google-play.yml",
            "event": "workflow_dispatch",
            "status": "completed",
            "conclusion": "failure",
        }
        jobs = [
            {"name": name, "conclusion": "success"}
            for name in [
                "Verify source snapshot",
                "Required quality gate / Analyze and test",
                "Read release version",
                "Publish AAB to Google Play",
            ]
        ]
        jobs.append(
            {"name": "Record published Play version code", "conclusion": "failure"}
        )
        return run, jobs

    def test_only_a_failed_marker_can_be_reconciled_without_another_upload(self):
        run, jobs = self.play_run_and_jobs()

        def api(path):
            return {"jobs": jobs} if "/jobs?" in path else run

        with patch.object(RELEASE, "api", side_effect=api):
            self.assertEqual(
                RELEASE.wait_run(
                    {"id": 99},
                    "a" * 40,
                    "google-play.yml",
                    allow_play_marker_failure=True,
                ),
                run,
            )
            with self.assertRaises(RELEASE.Error):
                RELEASE.wait_run({"id": 99}, "a" * 40, "google-play.yml")
            # Actual upload or Quality failures are never treated as a marker
            # issue, even when the marker job failed too.
            for index in [1, 3]:
                jobs[index]["conclusion"] = "failure"
                with self.assertRaises(RELEASE.Error):
                    RELEASE.wait_run(
                        {"id": 99},
                        "a" * 40,
                        "google-play.yml",
                        allow_play_marker_failure=True,
                    )
                jobs[index]["conclusion"] = "success"
            run["head_sha"] = "b" * 40
            with self.assertRaises(RELEASE.Error):
                RELEASE.verify_play_publication(99, "a" * 40)

    def test_existing_upload_attempt_is_resumed_without_redispatch(self):
        with (
            patch.object(RELEASE, "runs", return_value=[{"id": 10}]),
            patch.object(RELEASE, "dispatch") as dispatch,
        ):
            self.assertEqual(
                RELEASE.build_run("ios-testflight.yml", {"source_sha": "a" * 40}),
                {"id": 10},
            )
            dispatch.assert_not_called()

    def test_ambiguous_upload_attempts_block(self):
        with (
            patch.object(RELEASE, "runs", return_value=[{"id": 10}, {"id": 11}]),
            patch.object(RELEASE, "dispatch") as dispatch,
        ):
            with self.assertRaises(RELEASE.Error):
                RELEASE.build_run("ios-testflight.yml", {"source_sha": "a" * 40})
            dispatch.assert_not_called()

    def test_exact_builds_require_both_platforms_and_app_store_eligibility(self):
        plan = {"version": "1.8.8", "apple_build_number": "1698"}
        builds = [
            {
                "id": platform,
                "platform": platform,
                "marketing_version": "1.8.8",
                "version": "1698",
                "processingState": "VALID",
                "expired": False,
                "buildAudienceType": "APP_STORE_ELIGIBLE",
            }
            for platform in ["IOS", "MAC_OS"]
        ]
        self.assertEqual(
            set(RELEASE.exact_builds({"builds": builds}, plan)), {"IOS", "MAC_OS"}
        )
        self.assertIsNone(RELEASE.exact_builds({"builds": builds[:1]}, plan))
        builds[1]["buildAudienceType"] = "INTERNAL_ONLY"
        with self.assertRaises(RELEASE.Error):
            RELEASE.exact_builds({"builds": builds}, plan)

    def test_store_submission_validates_both_apple_plans_before_play_and_verifies_poststate(
        self,
    ):
        plan = {
            "version": "1.8.8",
            "apple_build_number": "1698",
            "source_sha": "a" * 40,
            "tag": "store-v1.8.8",
            "android_version_code": 500,
            "notes_path": "distribution/app-store/release-notes-1.8.8.json",
        }
        state = {
            "versions": [],
            "builds": [
                {
                    "id": platform,
                    "platform": platform,
                    "marketing_version": "1.8.8",
                    "version": "1698",
                    "processingState": "VALID",
                    "expired": False,
                    "buildAudienceType": "APP_STORE_ELIGIBLE",
                }
                for platform in ["IOS", "MAC_OS"]
            ],
        }
        events = []

        def dispatch(workflow, ref, sha, inputs):
            events.append((workflow, inputs.get("operation"), inputs.get("platform")))
            if workflow == "app-store-submit.yml" and inputs["operation"] == "submit":
                state["versions"].append(
                    {
                        "platform": inputs["platform"],
                        "version": "1.8.8",
                        "build_id": inputs["uploaded_build_id"],
                        "state": "WAITING_FOR_REVIEW",
                    }
                )
            return {"id": len(events)}

        with (
            patch.object(RELEASE, "build_run", return_value={"id": 10}),
            patch.object(RELEASE, "wait_run"),
            patch.object(RELEASE, "asc_state", return_value=state),
            patch.object(RELEASE, "api", return_value={"object": {"sha": "b" * 40}}),
            patch.object(RELEASE, "runs", return_value=[]),
            patch.object(RELEASE, "dispatch", side_effect=dispatch),
            patch.object(RELEASE, "play_state") as play,
            patch.object(RELEASE, "record_play_marker") as marker,
        ):
            RELEASE.submit(plan)
            play.assert_called_once_with(500)
            marker.assert_called_once_with("a" * 40, 500, 3)
        self.assertEqual(
            events,
            [
                ("app-store-submit.yml", "validate", "IOS"),
                ("app-store-submit.yml", "validate", "MAC_OS"),
                ("google-play.yml", None, None),
                ("app-store-submit.yml", "submit", "IOS"),
                ("app-store-submit.yml", "submit", "MAC_OS"),
            ],
        )

    def test_existing_failed_play_run_is_not_redispatched_or_followed_by_asc_submission(
        self,
    ):
        plan = {
            "version": "1.8.8",
            "apple_build_number": "1698",
            "source_sha": "a" * 40,
            "tag": "store-v1.8.8",
            "android_version_code": 500,
            "notes_path": "distribution/app-store/release-notes-1.8.8.json",
        }
        builds = {platform: {"id": platform} for platform in ["IOS", "MAC_OS"]}

        def wait(run, *_args, **_kwargs):
            if run["id"] == 99:
                raise RELEASE.Error("failed publication")

        with (
            patch.object(RELEASE, "build_run", return_value={"id": 10}),
            patch.object(RELEASE, "wait_run", side_effect=wait),
            patch.object(RELEASE, "asc_state", return_value={"versions": []}),
            patch.object(RELEASE, "exact_builds", return_value=builds),
            patch.object(RELEASE, "api", return_value={"object": {"sha": "b" * 40}}),
            patch.object(RELEASE, "runs", return_value=[{"id": 99}]),
            patch.object(RELEASE, "dispatch", return_value={"id": 20}) as dispatch,
        ):
            with self.assertRaises(RELEASE.Error):
                RELEASE.submit(plan)
            self.assertEqual(dispatch.call_count, 2)
            self.assertTrue(
                all(
                    call.args[0] == "app-store-submit.yml"
                    and call.args[3]["operation"] == "validate"
                    for call in dispatch.call_args_list
                )
            )

    def test_snapshot_publication_and_resume_use_real_git_and_immutable_tags(self):
        # Exercise the production allocator against a local bare remote. No
        # signing keys, provider credentials or real repository writes.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            remote = root / "remote.git"
            repo = root / "repo"
            subprocess.run(
                ["git", "init", "--bare", "--initial-branch=master", str(remote)],
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["git", "clone", str(remote), str(repo)],
                check=True,
                capture_output=True,
            )
            previous = Path.cwd()
            os.chdir(repo)
            try:
                RELEASE.command("git", "config", "user.name", "Store test")
                RELEASE.command("git", "config", "user.email", "test@example.com")
                Path("pubspec.yaml").write_text(
                    "name: example\nversion: 1.8.6+295\n\ndependencies: {}\n"
                )
                Path("android").mkdir()
                Path("android/version-code.txt").write_text("100\n")
                Path("distribution/app-store").mkdir(parents=True)
                RELEASE.command("git", "add", ".")
                RELEASE.command("git", "commit", "-m", "Initial")
                RELEASE.command("git", "push", "origin", "master", "master:nightly")
                state = {"versions": [], "trains": [{"version": "1.8.7"}]}
                play = {"highest_version_code": 400}
                with patch.object(RELEASE.time, "time", return_value=200):
                    planned = RELEASE.prepare("2026-10-30", state, play)
                    self.assertEqual(planned["version"], "1.8.8")
                    self.assertEqual(planned["android_version_code"], 401)
                    self.assertEqual(
                        RELEASE.command("git", "status", "--porcelain"), ""
                    )

                    def reject_base(_commit):
                        raise RELEASE.Error("failed base")

                    with self.assertRaises(RELEASE.Error):
                        RELEASE.prepare(
                            "2026-10-30",
                            state,
                            play,
                            apply=True,
                            base_validator=reject_base,
                        )
                    self.assertEqual(
                        RELEASE.command("git", "status", "--porcelain"), ""
                    )
                    self.assertEqual(
                        RELEASE.command("git", "rev-list", "--count", "HEAD"), "1"
                    )
                    plan = RELEASE.prepare("2026-10-30", state, play, apply=True)
                self.assertEqual(plan["apple_build_number"], "2")
                self.assertEqual(
                    RELEASE.command("git", "rev-parse", "v1.8.8^{commit}"),
                    plan["source_sha"],
                )
                self.assertEqual(
                    RELEASE.command(
                        "git", "ls-remote", "origin", "refs/heads/master"
                    ).split()[0],
                    plan["source_sha"],
                )
                self.assertIn("dependencies: {}", Path("pubspec.yaml").read_text())
                self.assertEqual(RELEASE.command("git", "status", "--porcelain"), "")
                # A retry must keep the same source/code despite a higher live
                # version or clock. It must not allocate a second release.
                resumed = RELEASE.prepare(
                    "2026-10-30",
                    {"versions": [], "trains": [{"version": "1.8.10"}]},
                    {"highest_version_code": 900},
                    apply=True,
                )
                self.assertEqual(resumed, plan)
                self.assertEqual(
                    RELEASE.command("git", "rev-list", "--count", "HEAD"), "2"
                )
                # The next date cannot conceal an unresolved publication.
                with self.assertRaises(RELEASE.Error):
                    RELEASE.prepare("2026-10-31", state, play, apply=True)
                Path("controller.txt").write_text("new controller commit\n")
                RELEASE.command("git", "add", "controller.txt")
                RELEASE.command("git", "commit", "-m", "Advance controller")
                RELEASE.command("git", "push", "origin", "master")
                RELEASE.record_completion(plan)
                self.assertEqual(
                    RELEASE.command(
                        "git",
                        "ls-remote",
                        "origin",
                        "refs/tags/store-complete-2026-10-30^{}",
                    ).split()[0],
                    RELEASE.command("git", "rev-parse", "HEAD"),
                )
                recorded = json.loads(
                    RELEASE.command(
                        "git",
                        "for-each-ref",
                        "--format=%(contents)",
                        "refs/tags/store-complete-2026-10-30",
                    )
                )
                self.assertEqual(recorded["source_sha"], plan["source_sha"])
                self.assertEqual(recorded["kind"], "store_complete")
                with patch.object(RELEASE.time, "time", return_value=200):
                    RELEASE.advance_development_version(
                        plan,
                        state_reader=lambda: {"highest_version_code": 1000},
                        quality_requester=lambda _sha: None,
                    )
                self.assertIn("version: 1.9.0+297", Path("pubspec.yaml").read_text())
                self.assertIn("dependencies: {}", Path("pubspec.yaml").read_text())
                self.assertEqual(Path("android/version-code.txt").read_text(), "1001\n")
                self.assertEqual(
                    RELEASE.command("git", "rev-parse", "store-v1.8.8^{commit}"),
                    plan["source_sha"],
                )
                self.assertEqual(
                    RELEASE.command(
                        "git", "ls-remote", "origin", "refs/heads/master"
                    ).split()[0],
                    RELEASE.command("git", "rev-parse", "HEAD"),
                )
                with patch.object(RELEASE, "play_state") as provider:
                    RELEASE.advance_development_version(
                        plan, state_reader=provider, quality_requester=lambda _sha: None
                    )
                    provider.assert_not_called()
                # Resume is idempotent and refuses another source identity.
                RELEASE.record_completion(plan)
                with self.assertRaises(RELEASE.Error):
                    RELEASE.record_marker(
                        "store-complete-2026-10-30",
                        "b" * 40,
                        {"kind": "store_complete"},
                    )
                with self.assertRaises(RELEASE.Error):
                    RELEASE.prepare(
                        "2026-10-31",
                        {"versions": [{"state": "WAITING_FOR_REVIEW"}], "trains": []},
                        play,
                        apply=True,
                    )
            finally:
                os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
