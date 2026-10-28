#!/usr/bin/env python3
"""Coordinate pinned store releases using the existing, gated GitHub workflows."""

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

REPO = "iebb/mithka"
SHA = re.compile(r"[0-9a-f]{40}")
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
APPLE_WORKFLOWS = {"IOS": "ios-testflight.yml", "MAC_OS": "macos-testflight.yml"}
SUBMITTED = {
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_APPLE_RELEASE",
    "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_DISTRIBUTION",
    "READY_FOR_SALE",
    "READY_FOR_DISTRIBUTION",
}


class Error(RuntimeError):
    pass


def command(*args, data=None):
    result = subprocess.run(args, input=data, text=True, capture_output=True)
    if result.returncode:
        # Never include a provider body, environment or credential-bearing URL.
        if args[:2] == ("ruby", "scripts/store_release_state.rb"):
            safe = re.search(
                r"Store state lookup failed \([A-Za-z0-9_:]+(?:, HTTP \d{3})?\)",
                result.stderr,
            )
            if safe:
                raise Error(safe[0])
        raise Error(f"{args[0]} failed (exit {result.returncode})")
    return result.stdout.strip()


def version_tuple(value):
    if not SEMVER.fullmatch(value):
        raise Error("expected a normal X.Y.Z version")
    return tuple(map(int, value.split(".")))


def choose_version(master, used):
    current = version_tuple(master)
    versions = [version_tuple(value) for value in used]
    if any(value[:2] > current[:2] for value in versions):
        raise Error("a newer store release train needs a maintainer decision")
    floor = max(
        (value[2] for value in versions if value[:2] == current[:2]), default=-1
    )
    patch = max(current[2], floor + 1, 1)
    return f"{current[0]}.{current[1]}.{patch}"


def next_android_code(values, now):
    code = max(int(now), *(int(value) + 1 for value in values))
    if not 1 <= code <= 2100000000:
        raise Error("next Android code is outside Play's accepted range")
    return code


def development_target(current_version, released_version):
    released = version_tuple(released_version)
    target = (released[0], released[1] + 1, 0)
    current = version_tuple(current_version)
    if current >= target:
        return None
    if current != released:
        raise Error(
            "master's version changed during release; inspect it before advancing the minor"
        )
    return ".".join(map(str, target))


def release_key(requested, tags, today):
    pending = sorted(
        tag.removeprefix("store-")
        for tag in tags
        if re.fullmatch(r"store-\d{4}-\d{2}-\d{2}", tag)
        and f"store-complete-{tag.removeprefix('store-')}" not in tags
    )
    if len(pending) > 1:
        raise Error("multiple unfinished store snapshots need reconciliation")
    if pending:
        if requested and requested != pending[0]:
            raise Error(
                f"resume unfinished release {pending[0]} before allocating another snapshot"
            )
        return pending[0]
    return requested or today


def assert_context(env):
    if (
        env.get("GITHUB_REPOSITORY") != REPO
        or env.get("GITHUB_REF") != "refs/heads/master"
        or env.get("GITHUB_EVENT_NAME") not in {"schedule", "workflow_dispatch"}
    ):
        raise Error("store coordinator must run on canonical master in GitHub Actions")


def api(path, payload=None):
    args = ["gh", "api", f"repos/{REPO}/{path}"]
    if payload is not None:
        args.extend(["--method", "POST", "--input", "-"])
    raw = command(*args, data=json.dumps(payload) if payload is not None else None)
    return json.loads(raw) if raw else None


def runs(workflow, sha=None):
    query = f"actions/workflows/{workflow}/runs?event=workflow_dispatch&per_page=100"
    if sha:
        query += f"&head_sha={sha}"
    result = api(query)
    # Refuse an incomplete search rather than redispatch an unknown attempt.
    if result["total_count"] > len(result["workflow_runs"]):
        raise Error("workflow attempt history needs manual reconciliation")
    return result["workflow_runs"]


def verify_play_publication(run_id, source_sha):
    run = api(f"actions/runs/{run_id}")
    if (
        run["head_sha"] != source_sha
        or run["path"] != ".github/workflows/google-play.yml"
        or run["event"] not in {"push", "workflow_dispatch"}
    ):
        raise Error("Play publication run identity mismatch")
    jobs = api(f"actions/runs/{run_id}/jobs?per_page=100")["jobs"]
    required = {
        "Verify source snapshot",
        "Required quality gate / Analyze and test",
        "Read release version",
        "Publish AAB to Google Play",
    }
    for name in required:
        matches = [job for job in jobs if job["name"] == name]
        if len(matches) != 1 or matches[0]["conclusion"] != "success":
            raise Error(f"Play publication prerequisite did not succeed: {name}")
    for job in jobs:
        if job["name"] == "Record published Play version code":
            continue
        if job["conclusion"] == "success":
            continue
        if (
            job["name"].startswith("Required quality gate / Merge snapshot ")
            and job["conclusion"] == "skipped"
        ):
            continue
        raise Error("Play publication has a failure outside its marker job")
    return jobs


def wait_run(run, sha, workflow, timeout=14400, allow_play_marker_failure=False):
    deadline = time.monotonic() + timeout
    while True:
        current = api(f"actions/runs/{run['id']}")
        if (
            current["head_sha"] != sha
            or current["path"] != f".github/workflows/{workflow}"
            or current.get("event") != "workflow_dispatch"
        ):
            raise Error("workflow run identity changed")
        if current["status"] == "completed":
            if current["conclusion"] != "success":
                if (
                    allow_play_marker_failure
                    and workflow == "google-play.yml"
                    and current["conclusion"] == "failure"
                ):
                    jobs = verify_play_publication(run["id"], sha)
                    failed = [job for job in jobs if job["conclusion"] == "failure"]
                    if (
                        len(failed) == 1
                        and failed[0]["name"] == "Record published Play version code"
                    ):
                        # No second upload: the caller must verify the actual
                        # production code and repair only its immutable marker.
                        return current
                raise Error(
                    f"workflow {workflow} run {run['id']} needs attention ({current['conclusion']})"
                )
            return current
        if time.monotonic() >= deadline:
            raise Error(
                f"workflow {workflow} run {run['id']} timed out; reconcile it before retrying"
            )
        time.sleep(30)


def dispatch(workflow, ref, sha, inputs):
    started = dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=5)
    api(f"actions/workflows/{workflow}/dispatches", {"ref": ref, "inputs": inputs})
    for _ in range(24):
        matches = [
            run
            for run in runs(workflow, sha)
            if dt.datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
            >= started
        ]
        if len(matches) > 1:
            raise Error("multiple matching dispatches; reconcile them before retrying")
        if matches:
            print(f"Started {workflow}: {matches[0]['html_url']}", flush=True)
            return matches[0]
        time.sleep(5)
    raise Error("dispatch result is unknown; do not submit a duplicate")


def build_run(workflow, plan):
    existing = runs(workflow, plan["source_sha"])
    if len(existing) > 1:
        raise Error(f"multiple {workflow} attempts need reconciliation")
    return (
        existing[0]
        if existing
        else dispatch(
            workflow,
            plan["tag"],
            plan["source_sha"],
            {
                "expected_source_commit": plan["source_sha"],
                "distribute_testflight": "false",
            },
        )
    )


def asc_state(build_number=None):
    args = ["ruby", "scripts/store_release_state.rb"]
    if build_number:
        args.append(str(build_number))
    return json.loads(command(*args))


def play_state(expected=None):
    # Its protected job shares the publication lock with every Play upload.
    sha = api("git/ref/heads/master")["object"]["sha"]
    run = dispatch(
        "store-checks.yml",
        "master",
        sha,
        {"expected_play_version_code": str(expected) if expected else ""},
    )
    wait_run(run, sha, "store-checks.yml")
    with tempfile.TemporaryDirectory() as directory:
        command(
            "gh",
            "run",
            "download",
            str(run["id"]),
            "--repo",
            REPO,
            "--name",
            "play-state",
            "--dir",
            directory,
        )
        state = json.loads((Path(directory) / "play-state.json").read_text())
    if expected is not None and int(expected) not in state["production_codes"]:
        raise Error("Play production does not contain the intended version code")
    return state


def ensure_master_quality(commit):
    existing = api(f"actions/workflows/quality.yml/runs?head_sha={commit}&per_page=1")
    if not existing["workflow_runs"]:
        api("actions/workflows/quality.yml/dispatches", {"ref": "master", "inputs": {}})


def validate_release_base(commit):
    existing = api(
        f"actions/workflows/quality.yml/runs?head_sha={commit}&per_page=100"
    )["workflow_runs"]
    if not existing:
        run = dispatch("quality.yml", "master", commit, {})
    else:
        run = max(
            existing,
            key=lambda candidate: candidate.get(
                "updated_at", candidate.get("created_at", "")
            ),
        )
        if (
            run.get("head_sha") != commit
            or run.get("path") != ".github/workflows/quality.yml"
        ):
            raise Error("base Quality identity changed")
        # Direct push/manual Quality has the same trusted workflow definition.
        if run["status"] == "completed" and run["conclusion"] == "success":
            return
        if run["status"] == "completed":
            raise Error(
                "current master Quality failed; do not reserve a new store snapshot"
            )
        deadline = time.monotonic() + 3600
        while True:
            current = api(f"actions/runs/{run['id']}")
            if (
                current["head_sha"] != commit
                or current["path"] != ".github/workflows/quality.yml"
            ):
                raise Error("base Quality identity changed")
            if current["status"] == "completed":
                if current["conclusion"] != "success":
                    raise Error(
                        "current master Quality failed; do not reserve a new store snapshot"
                    )
                return
            if time.monotonic() >= deadline:
                raise Error("base Quality timed out")
            time.sleep(30)
    wait_run(run, commit, "quality.yml", timeout=3600)


def validate_plan(plan, key):
    version_tuple(plan["version"])
    if not re.fullmatch(re.escape(plan["version"]) + r"\+\d+", plan["raw_version"]):
        raise Error("snapshot raw version does not preserve the normal patch")
    if not SHA.fullmatch(plan["source_sha"]) or not SHA.fullmatch(plan["base_sha"]):
        raise Error("snapshot has an invalid source commit")
    if (
        plan["schema_version"] != 1
        or plan["release_key"] != key
        or plan["tag"] != f"store-v{plan['version']}"
        or plan["day_tag"] != f"store-{key}"
        or plan["notes_path"]
        != f"distribution/app-store/release-notes-{plan['version']}.json"
        or version_tuple(plan["version"])[2] == 0
    ):
        raise Error("snapshot metadata does not match its immutable tags")
    if command("git", "rev-parse", f"{plan['tag']}^{{commit}}") != plan["source_sha"]:
        raise Error("snapshot version tag changed")
    raw = command("git", "show", f"{plan['source_sha']}:pubspec.yaml")
    if not re.search(rf"^version:\s*{re.escape(plan['raw_version'])}\s*$", raw, re.M):
        raise Error("snapshot source version changed")
    code = command("git", "show", f"{plan['source_sha']}:android/version-code.txt")
    if int(code) != plan["android_version_code"]:
        raise Error("snapshot Android code changed")
    height = command("git", "rev-list", "--count", plan["source_sha"])
    if height != plan["apple_build_number"]:
        raise Error("snapshot Apple build identity changed")
    command("git", "merge-base", "--is-ancestor", plan["source_sha"], "origin/master")
    return plan


def prepare(key, state, play, apply=False, base_validator=None):
    if key is not None and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", key):
        raise Error("release key must be YYYY-MM-DD")
    if command("git", "branch", "--show-current") != "master" or command(
        "git", "status", "--porcelain"
    ):
        raise Error("snapshot preparation requires a clean master checkout")
    command("git", "fetch", "origin", "master", "nightly", "--tags")
    command("git", "merge", "--ff-only", "origin/master")
    if command("git", "rev-parse", "HEAD") != command(
        "git", "rev-parse", "origin/master"
    ):
        raise Error("local master contains unpublished work")
    tags = command("git", "tag", "--list").splitlines()
    today = dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).date().isoformat()
    key = release_key(key, tags, today)
    dt.date.fromisoformat(key)
    day_tag = f"store-{key}"
    if day_tag in tags:
        if command("git", "cat-file", "-t", f"refs/tags/{day_tag}") != "tag":
            raise Error("release marker must be an annotated immutable tag")
        plan = json.loads(
            command(
                "git", "for-each-ref", "--format=%(contents)", f"refs/tags/{day_tag}"
            )
        )
        if command("git", "rev-parse", f"{day_tag}^{{commit}}") != plan["source_sha"]:
            raise Error("release marker does not point to its source")
        return validate_plan(plan, key)
    active = [
        version
        for version in state["versions"]
        if version["state"] in SUBMITTED - {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
    ]
    if active:
        raise Error(
            "an Apple version is already under review or awaiting release; preserve it"
        )
    pubspec = Path("pubspec.yaml").read_text()
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec, re.M)
    if not match:
        raise Error("master has no normal version and numeric build metadata")
    used = [item["version"] for item in state["versions"] + state["trains"]]
    nightly_raw = command("git", "show", "origin/nightly:pubspec.yaml")
    nightly_version = re.search(
        r"^version:[ \t]*(\d+\.\d+\.\d+)(?:\+\d+)?[ \t]*$", nightly_raw, re.M
    )
    if not nightly_version:
        raise Error("nightly has no normal version")
    used.append(nightly_version[1])
    version = choose_version(match[1], used)
    code_floor = [
        Path("android/version-code.txt").read_text().strip(),
        command("git", "show", "origin/nightly:android/version-code.txt"),
        play["highest_version_code"],
    ]
    code_floor.extend(
        tag.removeprefix("play-version-code-")
        for tag in tags
        if re.fullmatch(r"play-version-code-\d+", tag)
    )
    code = next_android_code(code_floor, time.time())
    plan = {
        "schema_version": 1,
        "release_key": key,
        "version": version,
        "raw_version": f"{version}+{int(match[2]) + 1}",
        "base_sha": command("git", "rev-parse", "HEAD"),
        "android_version_code": code,
        "notes_path": f"distribution/app-store/release-notes-{version}.json",
        "tag": f"store-v{version}",
        "release_tag": f"v{version}",
        "day_tag": day_tag,
    }
    if plan["tag"] in tags or plan["release_tag"] in tags:
        raise Error("selected version already has a release snapshot")
    if not apply:
        return plan
    if base_validator:
        base_validator(plan["base_sha"])
    Path("pubspec.yaml").write_text(
        pubspec[: match.start()]
        + f"version: {plan['raw_version']}\n"
        + pubspec[match.end() :]
    )
    Path("android/version-code.txt").write_text(f"{code}\n")
    notes = Path(plan["notes_path"])
    if not notes.exists():
        notes.write_text(
            json.dumps(
                {
                    "en-US": f"Mithka {version} includes the latest app updates and maintenance improvements.",
                    "zh-Hans": f"Mithka {version} 包含最新的应用更新与维护改进。",
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n"
        )
    command(
        "git",
        "add",
        "--",
        "pubspec.yaml",
        "android/version-code.txt",
        plan["notes_path"],
    )
    command("git", "diff", "--cached", "--check")
    changed = set(command("git", "diff", "--cached", "--name-only").splitlines())
    allowed = {"pubspec.yaml", "android/version-code.txt", plan["notes_path"]}
    if not {"pubspec.yaml", "android/version-code.txt"} <= changed <= allowed:
        raise Error("snapshot staged unexpected files")
    command("git", "commit", "-m", f"chore: prepare store release {version}")
    plan["source_sha"] = command("git", "rev-parse", "HEAD")
    plan["apple_build_number"] = command("git", "rev-list", "--count", "HEAD")
    for tag in (plan["tag"], day_tag, plan["release_tag"]):
        command("git", "tag", "-a", tag, "-m", json.dumps(plan, sort_keys=True))
    # Recheck immediately before one atomic, non-force publication.
    command("git", "fetch", "origin", "master")
    if command("git", "rev-parse", "origin/master") != plan["base_sha"]:
        raise Error(
            "master advanced during snapshot preparation; nothing was published"
        )
    command(
        "git",
        "push",
        "--atomic",
        "origin",
        "master",
        plan["tag"],
        day_tag,
        plan["release_tag"],
    )
    return validate_plan(plan, key)


def exact_builds(state, plan):
    selected = {}
    for platform in APPLE_WORKFLOWS:
        matches = [
            build
            for build in state["builds"]
            if build["platform"] == platform
            and build["marketing_version"] == plan["version"]
            and build["version"] == plan["apple_build_number"]
        ]
        if len(matches) > 1:
            raise Error("multiple matching Apple builds need reconciliation")
        if not matches or matches[0]["processingState"] == "PROCESSING":
            return None
        build = matches[0]
        if (
            build["processingState"] != "VALID"
            or build.get("expired") is not False
            or build.get("buildAudienceType") != "APP_STORE_ELIGIBLE"
        ):
            raise Error("Apple build is not valid and App Store eligible")
        selected[platform] = build
    return selected


def submit(plan):
    uploads = {
        platform: build_run(workflow, plan)
        for platform, workflow in APPLE_WORKFLOWS.items()
    }
    for platform, run in uploads.items():
        wait_run(run, plan["source_sha"], APPLE_WORKFLOWS[platform])
    deadline = time.monotonic() + 1800
    while True:
        state = asc_state(plan["apple_build_number"])
        builds = exact_builds(state, plan)
        if builds:
            break
        if time.monotonic() >= deadline:
            raise Error("Apple processing is incomplete; resume this snapshot later")
        time.sleep(30)
    master = api("git/ref/heads/master")["object"]["sha"]
    # Validate both listings before any new production publication.
    for operation in ("validate", "submit"):
        if operation == "submit":
            previous = runs("google-play.yml", plan["source_sha"])
            if len(previous) > 1:
                raise Error("multiple Play publication attempts need reconciliation")
            run = (
                previous[0]
                if previous
                else dispatch(
                    "google-play.yml",
                    plan["tag"],
                    plan["source_sha"],
                    {"expected_source_commit": plan["source_sha"]},
                )
            )
            wait_run(
                run,
                plan["source_sha"],
                "google-play.yml",
                allow_play_marker_failure=True,
            )
            play_state(plan["android_version_code"])
            record_play_marker(
                plan["source_sha"], plan["android_version_code"], run["id"]
            )
        # Sequential: the reusable Quality gate is scoped to workflow + ref.
        for platform in APPLE_WORKFLOWS:
            state = asc_state(plan["apple_build_number"])
            existing = [
                version
                for version in state["versions"]
                if version["platform"] == platform
                and version["version"] == plan["version"]
            ]
            if existing and existing[0]["state"] in SUBMITTED:
                if existing[0]["build_id"] != builds[platform]["id"]:
                    raise Error("submitted version has a different build")
                continue
            if api("git/ref/heads/master")["object"]["sha"] != master:
                raise Error(
                    "store submission workflow changed during release; reconcile before continuing"
                )
            run = dispatch(
                "app-store-submit.yml",
                "master",
                master,
                {
                    "operation": operation,
                    "platform": platform,
                    "version": plan["version"],
                    "binary_version": plan["version"],
                    "build_number": plan["apple_build_number"],
                    "source_commit": plan["source_sha"],
                    "provenance": "github_actions",
                    "build_run_id": str(uploads[platform]["id"]),
                    "uploaded_build_id": builds[platform]["id"],
                    "release_notes_path": plan["notes_path"],
                },
            )
            wait_run(run, master, "app-store-submit.yml")
    state = asc_state(plan["apple_build_number"])
    for platform, build in builds.items():
        versions = [
            version
            for version in state["versions"]
            if version["platform"] == platform and version["version"] == plan["version"]
        ]
        if (
            len(versions) != 1
            or versions[0]["state"] not in SUBMITTED
            or versions[0]["build_id"] != build["id"]
        ):
            raise Error(
                "final App Store submission state did not match the release snapshot"
            )
    print(
        f"Verified {plan['version']}: Play production committed; iOS and macOS submitted.",
        flush=True,
    )


def record_marker(tag, source_sha, metadata):
    if not SHA.fullmatch(source_sha):
        raise Error("marker requires a full source SHA")
    command("git", "fetch", "origin", "master", "--tags")
    if command("git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}"):
        target = command("git", "rev-parse", f"{tag}^{{commit}}")
        # Legacy markers point directly to the built source. New markers use
        # current master as their Git ref; their annotation binds the source.
        if target == source_sha:
            return
        if command("git", "cat-file", "-t", f"refs/tags/{tag}") != "tag":
            raise Error("marker must be annotated")
        recorded = json.loads(
            command("git", "for-each-ref", "--format=%(contents)", f"refs/tags/{tag}")
        )
        if recorded.get("source_sha") != source_sha or any(
            recorded.get(key) != value for key, value in metadata.items()
        ):
            raise Error("immutable marker belongs to a different publication")
        command("git", "merge-base", "--is-ancestor", source_sha, target)
        return
    target = command("git", "rev-parse", "origin/master")
    command("git", "merge-base", "--is-ancestor", source_sha, target)
    message = json.dumps(
        dict(metadata, source_sha=source_sha, marker_commit=target), sort_keys=True
    )
    command("git", "tag", "-a", tag, target, "-m", message)
    command("git", "fetch", "origin", "master")
    if command("git", "rev-parse", "origin/master") != target:
        raise Error("master advanced before marker publication; resume safely")
    command("git", "push", "origin", tag)


def record_play_marker(source_sha, code, run_id):
    if not str(code).isdigit() or not 1 <= int(code) <= 2100000000:
        raise Error("invalid Play marker code")
    verify_play_publication(run_id, source_sha)
    record_marker(
        f"play-version-code-{code}",
        source_sha,
        {
            "schema_version": 2,
            "kind": "google_play",
            "android_version_code": int(code),
            "publication_run_id": str(run_id),
        },
    )


def record_completion(plan):
    # Only after actual Play/ASC postconditions pass. The annotation keeps the
    # immutable built source even when master has advanced since the snapshot.
    record_marker(
        f"store-complete-{plan['release_key']}",
        plan["source_sha"],
        {
            "schema_version": 1,
            "kind": "store_complete",
            "version": plan["version"],
            "android_version_code": plan["android_version_code"],
            "apple_build_number": plan["apple_build_number"],
            "google_play_verified": True,
            "apple_platforms_verified": ["IOS", "MAC_OS"],
        },
    )


def advance_development_version(
    plan, state_reader=play_state, quality_requester=ensure_master_quality
):
    # After verified store submission, under the shared nightly allocator lock.
    # Preserve app work and the immutable submitted snapshot.
    if command("git", "branch", "--show-current") != "master" or command(
        "git", "status", "--porcelain"
    ):
        raise Error("development bump requires a clean master checkout")
    command("git", "fetch", "origin", "master", "nightly")
    command("git", "merge", "--ff-only", "origin/master")
    base = command("git", "rev-parse", "origin/master")
    if command("git", "rev-parse", "HEAD") != base:
        raise Error("development bump found unpublished master work")
    pubspec = Path("pubspec.yaml").read_text()
    match = re.search(r"^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)[ \t]*$", pubspec, re.M)
    if not match:
        raise Error("master has no normal version and numeric build metadata")
    target = development_target(match[1], plan["version"])
    if target is None:
        print(
            "Master is already on the next development version; no extra bump.",
            flush=True,
        )
        quality_requester(base)
        return
    state = state_reader()
    code = next_android_code(
        [
            Path("android/version-code.txt").read_text().strip(),
            command("git", "show", "origin/nightly:android/version-code.txt"),
            plan["android_version_code"],
            state["highest_version_code"],
        ],
        time.time(),
    )
    raw = f"{target}+{int(match[2]) + 1}"
    Path("pubspec.yaml").write_text(
        pubspec[: match.start()] + f"version: {raw}" + pubspec[match.end() :]
    )
    Path("android/version-code.txt").write_text(f"{code}\n")
    command("git", "add", "--", "pubspec.yaml", "android/version-code.txt")
    command("git", "diff", "--cached", "--check")
    if set(command("git", "diff", "--cached", "--name-only").splitlines()) != {
        "pubspec.yaml",
        "android/version-code.txt",
    }:
        raise Error("development bump staged unrelated files")
    command(
        "git",
        "commit",
        "-m",
        f"chore: begin {target} development after store {plan['version']}",
    )
    command("git", "fetch", "origin", "master")
    if command("git", "rev-parse", "origin/master") != base:
        raise Error(
            "master advanced before the development bump; no bump was published"
        )
    command("git", "push", "origin", "master")
    quality_requester(command("git", "rev-parse", "HEAD"))
    print(
        f"Advanced master to {raw}; submitted stores remain {plan['version']}.",
        flush=True,
    )


def github_release(tag):
    result = subprocess.run(
        ["gh", "api", f"repos/{REPO}/releases/tags/{tag}"],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        if "HTTP 404" in result.stderr:
            return None
        raise Error("could not inspect the GitHub release")
    return json.loads(result.stdout)


def package_intent(plan, publication_run=None, retry_controller=None):
    kind = (
        "github_packages" if publication_run is None else "github_package_publication"
    )
    tag = f"github-package-{'build' if publication_run is None else 'publication'}-v{plan['version']}"
    if retry_controller is not None:
        if publication_run is None or not SHA.fullmatch(retry_controller):
            raise Error("publication retry requires an exact controller")
        tag += f"-retry-{retry_controller[:12]}"
    command("git", "fetch", "origin", "master", "--tags")
    if command("git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}"):
        data = json.loads(
            command("git", "for-each-ref", "--format=%(contents)", f"refs/tags/{tag}")
        )
        if (
            data.get("kind") != kind
            or data.get("source_sha") != plan["source_sha"]
            or not SHA.fullmatch(data.get("workflow_sha", ""))
            or publication_run is not None
            and data.get("package_run_id") != str(publication_run)
            or retry_controller is not None
            and data.get("workflow_sha") != retry_controller
        ):
            raise Error("GitHub package intent belongs to another source")
        return data, False
    sha = api("git/ref/heads/master")["object"]["sha"]
    if retry_controller is not None and sha != retry_controller:
        raise Error("master advanced before recording the publication retry")
    data = {
        "kind": kind,
        "workflow_sha": sha,
        "started_after": (
            dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=5)
        ).isoformat(),
    }
    if publication_run is not None:
        data["package_run_id"] = str(publication_run)
    record_marker(tag, plan["source_sha"], data)
    return dict(data, source_sha=plan["source_sha"]), True


def recover_github_publication(plan, original, controller):
    # This refuses every failure outside the release API step; no Quality or
    # native build can be waived. Only the original immutable artifacts move.
    command(
        sys.executable,
        str(Path(__file__).with_name("publish_store_github_release.py")),
        "--verify",
        "--package-run-id",
        str(original["id"]),
        "--source",
        plan["source_sha"],
        "--controller",
        controller,
    )
    intent, new_intent = package_intent(plan, publication_run=original["id"])
    candidates = [
        run
        for run in runs("github-store-publish.yml", intent["workflow_sha"])
        if dt.datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
        >= dt.datetime.fromisoformat(intent["started_after"])
    ]
    if len(candidates) > 1:
        raise Error("multiple package publication recoveries need reconciliation")
    if candidates:
        previous = api(f"actions/runs/{candidates[0]['id']}")
        if previous["status"] == "completed" and previous["conclusion"] == "failure":
            if (
                previous["head_sha"] != intent["workflow_sha"]
                or previous["path"] != ".github/workflows/github-store-publish.yml"
                or previous["event"] != "workflow_dispatch"
            ):
                raise Error("failed publication recovery identity changed")
            current = api("git/ref/heads/master")["object"]["sha"]
            if current != intent["workflow_sha"] and command(
                "git",
                "diff",
                "--name-only",
                intent["workflow_sha"],
                current,
                "--",
                "scripts/publish_store_github_release.py",
                ".github/workflows/github-store-publish.yml",
            ):
                # A known failed attempt plus an actual reviewed publisher
                # correction may use a new immutable intent. Unchanged code,
                # ambiguous dispatches and in-flight attempts never redispatch.
                intent, new_intent = package_intent(
                    plan, publication_run=original["id"], retry_controller=current
                )
                candidates = [
                    run
                    for run in runs("github-store-publish.yml", intent["workflow_sha"])
                    if dt.datetime.fromisoformat(
                        run["created_at"].replace("Z", "+00:00")
                    )
                    >= dt.datetime.fromisoformat(intent["started_after"])
                ]
                if len(candidates) > 1:
                    raise Error(
                        "multiple corrected publication attempts need reconciliation"
                    )
    if candidates:
        recovery = candidates[0]
    elif new_intent:
        if api("git/ref/heads/master")["object"]["sha"] != intent["workflow_sha"]:
            raise Error("master advanced before publication recovery dispatch")
        recovery = dispatch(
            "github-store-publish.yml",
            "master",
            intent["workflow_sha"],
            {
                "package_run_id": str(original["id"]),
                "source_commit": plan["source_sha"],
                "controller_commit": controller,
            },
        )
    else:
        raise Error("publication recovery dispatch is unknown; reconcile it")
    wait_run(recovery, intent["workflow_sha"], "github-store-publish.yml")
    return recovery


def verify_github_packages(release, manifest, plan):
    if (
        release["tag_name"] != f"v{plan['version']}"
        or release["draft"]
        or release["prerelease"]
        or manifest.get("source_sha") != plan["source_sha"]
        or manifest.get("version") != plan["version"]
        or manifest.get("android_version_code") != plan["android_version_code"]
    ):
        raise Error(
            "GitHub release identity does not match the submitted store snapshot"
        )
    files = manifest.get("files", {})
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
    if len(files) != len(suffixes):
        raise Error("GitHub release does not contain the complete package set")
    for suffix in suffixes:
        if (
            sum(
                name.startswith(f"mithka-{plan['version']}-") and name.endswith(suffix)
                for name in files
            )
            != 1
        ):
            raise Error(f"GitHub release is missing or duplicates {suffix}")
    remote = {asset["name"]: asset for asset in release["assets"]}
    for name, expected in files.items():
        actual = remote.get(name)
        if (
            not actual
            or actual["size"] != expected["size"]
            or actual.get("digest") != "sha256:" + expected["sha256"]
        ):
            raise Error(f"GitHub package checksum mismatch: {name}")


def publish_github_release(plan):
    tag = f"v{plan['version']}"
    command("git", "fetch", "origin", "--tags")
    if command("git", "rev-parse", f"{tag}^{{commit}}") != plan["source_sha"]:
        raise Error("canonical GitHub release tag points to another source")
    release = github_release(tag)
    intent, new_intent = package_intent(plan)
    candidates = [
        run
        for run in runs("release.yml", intent["workflow_sha"])
        if dt.datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
        >= dt.datetime.fromisoformat(intent["started_after"])
    ]
    if len(candidates) > 1:
        raise Error("multiple GitHub package builds need reconciliation")
    if candidates:
        run = candidates[0]
    elif new_intent and release is None:
        if api("git/ref/heads/master")["object"]["sha"] != intent["workflow_sha"]:
            raise Error("master advanced before GitHub package dispatch")
        run = dispatch(
            "release.yml",
            "master",
            intent["workflow_sha"],
            {"source_commit": plan["source_sha"], "desktop_test_only": "false"},
        )
    else:
        raise Error(
            "GitHub package dispatch is unknown; reconcile it instead of repeating it"
        )
    try:
        wait_run(run, intent["workflow_sha"], "release.yml")
    except Error:
        failed = api(f"actions/runs/{run['id']}")
        if failed["status"] != "completed" or failed["conclusion"] != "failure":
            raise
        recover_github_publication(plan, run, intent["workflow_sha"])
    release = github_release(tag)
    if release is None:
        raise Error("completed package workflow did not publish its GitHub release")
    with tempfile.TemporaryDirectory() as directory:
        command(
            "gh",
            "release",
            "download",
            tag,
            "--repo",
            REPO,
            "--pattern",
            "release-manifest.json",
            "--dir",
            directory,
        )
        manifest = json.loads((Path(directory) / "release-manifest.json").read_text())
    if manifest.get("workflow_run_id") != str(run["id"]):
        raise Error("GitHub package manifest belongs to another workflow run")
    verify_github_packages(release, manifest, plan)
    print(
        f"Verified GitHub release {tag}: 11 packages match the store source.",
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--operation", choices=["plan", "release"], default="plan")
    parser.add_argument(
        "--release-key",
        default=None,
    )
    args = parser.parse_args()
    assert_context(os.environ)
    play = play_state()
    plan = prepare(
        args.release_key,
        asc_state(),
        play,
        apply=args.operation == "release",
        base_validator=validate_release_base,
    )
    print(json.dumps(plan, indent=2), flush=True)
    if args.operation == "release":
        submit(plan)
        advance_development_version(plan)
        publish_github_release(plan)
        record_completion(plan)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write(
                f"Store {args.operation}: **{plan['version']}** ({plan.get('source_sha', 'not published')}).\n"
            )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (Error, ValueError, KeyError) as error:
        # Our Error messages contain public identities only. Parsing failures
        # can include raw response fragments, so report only their class.
        print(
            str(error) if isinstance(error, Error) else type(error).__name__, flush=True
        )
        raise SystemExit(1)
