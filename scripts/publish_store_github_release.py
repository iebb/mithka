#!/usr/bin/env python3
"""Recover only GitHub publication after verified store package builds."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

REPO = "iebb/mithka"
SHA = re.compile(r"[0-9a-f]{40}")
SUFFIXES = (
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
)


class Error(RuntimeError):
    pass


def command(*args, data=None):
    result = subprocess.run(args, input=data, capture_output=True, text=True)
    if result.returncode:
        # Never echo provider responses or credential-bearing command output.
        raise Error(f"{args[0]} operation failed")
    return result.stdout.strip()


def api(path, payload=None, method=None):
    args = ["gh", "api", f"repos/{REPO}/{path}"]
    if payload is not None:
        args += ["--method", method or "POST", "--input", "-"]
    return json.loads(
        command(*args, data=json.dumps(payload) if payload is not None else None)
    )


def context(publishing=False):
    if (
        os.environ.get("GITHUB_REPOSITORY") != REPO
        or os.environ.get("GITHUB_REF") != "refs/heads/master"
        or os.environ.get("GITHUB_EVENT_NAME") not in {"workflow_dispatch", "schedule"}
        or publishing
        and os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
    ):
        raise Error("only canonical master workflows may recover publication")


def verify_build(run, jobs, artifacts, source, controller, version):
    if (
        run.get("repository", {}).get("full_name") != REPO
        or run.get("path") != ".github/workflows/release.yml"
        or run.get("event") != "workflow_dispatch"
        or run.get("head_sha") != controller
        or run.get("status") != "completed"
        or run.get("conclusion") != "failure"
    ):
        raise Error("package workflow identity or completed failure does not match")
    required = {
        f"Required quality gate / Analyze and test release source {source}",
        "Read pubspec version",
        "Build arm64-v8a APK",
        "Build armeabi-v7a APK",
        "Build Windows x64",
        "Build Windows arm64",
        "Build macOS universal",
        "Build Linux x64",
        "Build Linux arm64",
    }
    for name in required:
        matches = [job for job in jobs if job["name"] == name]
        if len(matches) != 1 or matches[0].get("conclusion") != "success":
            raise Error(f"package prerequisite did not pass: {name}")
    failed = [job for job in jobs if job.get("conclusion") == "failure"]
    if len(failed) != 1 or failed[0]["name"] != "Publish GitHub Release":
        raise Error("failure was not confined to GitHub publication")
    failed_steps = [
        step["name"]
        for step in failed[0].get("steps", [])
        if step.get("conclusion") == "failure"
    ]
    if failed_steps != ["Publish to GitHub Release"]:
        raise Error("publication failed outside its release API step")
    for job in jobs:
        if job["name"] in required or job is failed[0]:
            continue
        if (
            job["name"].startswith("Required quality gate / Merge snapshot ")
            and job.get("conclusion") == "skipped"
        ):
            continue
        raise Error("unexpected or unsuccessful package job")
    names = [artifact["name"] for artifact in artifacts]
    dates = {
        match[1]
        for name in names
        if (match := re.fullmatch(r"desktop-linux-x64-(\d{8})", name))
    }
    if len(dates) != 1:
        raise Error("package artifact date is missing or ambiguous")
    date = dates.pop()
    expected = {
        f"apk-{version}-{date}-arm64-v8a",
        f"apk-{version}-{date}-armeabi-v7a",
        *[
            f"desktop-{platform}-{date}"
            for platform in (
                "windows-x64",
                "windows-arm64",
                "macos-universal",
                "linux-x64",
                "linux-arm64",
            )
        ],
        f"installer-windows-x64-{date}",
        f"installer-windows-arm64-{date}",
        f"appimage-linux-x64-{date}",
        f"appimage-linux-arm64-{date}",
    }
    if (
        len(names) != 11
        or set(names) != expected
        or any(a.get("expired") for a in artifacts)
    ):
        raise Error(
            "original run does not have exactly the eleven live package artifacts"
        )
    return date


def verify_source(source, controller):
    if not SHA.fullmatch(source) or not SHA.fullmatch(controller):
        raise Error("source and controller must be full commit SHAs")
    command("git", "fetch", "origin", "master", "--tags")
    for sha in (source, controller):
        command("git", "merge-base", "--is-ancestor", sha, "origin/master")
    pubspec = command("git", "show", f"{source}:pubspec.yaml")
    match = re.search(r"^version:\s*(\d+\.\d+\.[1-9]\d*)\+\d+\s*$", pubspec, re.M)
    if not match:
        raise Error("store source must have a normal nonzero patch version")
    version = match[1]
    for tag in (f"store-v{version}", f"v{version}"):
        if command("git", "rev-parse", f"refs/tags/{tag}^{{commit}}") != source:
            raise Error("immutable source tags do not match")
    code = command("git", "show", f"{source}:android/version-code.txt")
    if not code.isdigit() or not 1 <= int(code) <= 2100000000:
        raise Error("source Android code is invalid")
    return {"version": version, "source_sha": source, "android_version_code": int(code)}


def inspect(run_id, source, controller):
    if not str(run_id).isdigit():
        raise Error("package run ID must be numeric")
    plan = verify_source(source, controller)
    run = api(f"actions/runs/{run_id}")
    job_data = api(f"actions/runs/{run_id}/jobs?per_page=100")
    artifact_data = api(f"actions/runs/{run_id}/artifacts?per_page=100")
    if job_data["total_count"] != len(job_data["jobs"]) or artifact_data[
        "total_count"
    ] != len(artifact_data["artifacts"]):
        raise Error("package evidence pagination is incomplete")
    plan["date"] = verify_build(
        run,
        job_data["jobs"],
        artifact_data["artifacts"],
        source,
        controller,
        plan["version"],
    )
    return plan


def existing_release(tag):
    result = subprocess.run(
        ["gh", "api", f"repos/{REPO}/releases/tags/{tag}"],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        if "HTTP 404" in result.stderr:
            # The tag endpoint returns published releases only. Authenticated
            # listing includes drafts; refuse duplicate drafts rather than
            # creating another release after an interrupted upload.
            matches = []
            page = 1
            while True:
                releases = api(f"releases?per_page=100&page={page}")
                matches.extend(item for item in releases if item["tag_name"] == tag)
                if len(releases) < 100:
                    break
                page += 1
            if len(matches) > 1:
                raise Error("multiple matching draft releases need reconciliation")
            return matches[0] if matches else None
        raise Error("could not inspect the GitHub release")
    return json.loads(result.stdout)


def verify_assets(release, files):
    remote = {asset["name"]: asset for asset in release["assets"]}
    if len(remote) != len(release["assets"]) or set(remote) != set(files):
        raise Error("release asset set is incomplete, duplicated or unrelated")
    for name, expected in files.items():
        if (
            remote[name]["size"] != expected["size"]
            or remote[name].get("digest") != "sha256:" + expected["sha256"]
        ):
            raise Error(f"release asset digest mismatch: {name}")


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def asset_content(asset_id):
    if not isinstance(asset_id, int) or asset_id <= 0:
        raise Error("invalid manifest asset ID")
    result = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{REPO}/releases/assets/{asset_id}",
            "-H",
            "Accept: application/octet-stream",
        ],
        capture_output=True,
    )
    if result.returncode or len(result.stdout) > 1024 * 1024:
        raise Error("could not read the existing release manifest")
    return result.stdout


def publish(plan, run_id, directory, publication_run_id):
    root = Path(directory)
    expected = {
        f"mithka-{plan['version']}-{plan['date']}-{suffix}" for suffix in SUFFIXES
    }
    paths = list(root.iterdir())
    if {p.name for p in paths} != expected or any(
        not p.is_file() or p.is_symlink() for p in paths
    ):
        raise Error("downloaded files do not match the eleven verified packages")
    files = {
        p.name: {
            "size": p.stat().st_size,
            "sha256": digest(p),
        }
        for p in sorted(paths)
    }
    if any(value["size"] <= 0 for value in files.values()):
        raise Error("empty package")
    manifest = {
        "schema_version": 1,
        **{key: plan[key] for key in ("version", "source_sha", "android_version_code")},
        "workflow_run_id": str(run_id),
        "publication_workflow_run_id": str(publication_run_id),
        "files": files,
    }
    tag = f"v{plan['version']}"
    release = existing_release(tag)
    manifest_path = root / "release-manifest.json"
    raw_manifest = (json.dumps(manifest, sort_keys=True, indent=2) + "\n").encode()
    if release:
        matches = [
            asset for asset in release["assets"] if asset["name"] == manifest_path.name
        ]
        if len(matches) > 1:
            raise Error("duplicate release manifest assets")
        if matches:
            previous = asset_content(matches[0]["id"])
            recorded = json.loads(previous)
            expected_core = {
                key: value
                for key, value in manifest.items()
                if key != "publication_workflow_run_id"
            }
            actual_core = {
                key: value
                for key, value in recorded.items()
                if key != "publication_workflow_run_id"
            }
            if (
                actual_core != expected_core
                or matches[0]["size"] != len(previous)
                or matches[0].get("digest")
                != "sha256:" + hashlib.sha256(previous).hexdigest()
            ):
                raise Error(
                    "existing manifest does not match the verified original packages"
                )
            if (
                "publication_workflow_run_id" in recorded
                and not str(recorded["publication_workflow_run_id"]).isdigit()
            ):
                raise Error("invalid initial publication identity")
            # Preserve the first upload's bytes and provenance on a later
            # finalization attempt. No asset is replaced merely for a run ID.
            raw_manifest = previous
    manifest_path.write_bytes(raw_manifest)
    files[manifest_path.name] = {
        "size": manifest_path.stat().st_size,
        "sha256": digest(manifest_path),
    }
    if release and not release["draft"]:
        if release["prerelease"]:
            raise Error("existing release is a prerelease")
        verify_assets(release, files)
        return
    if release:
        remote = {asset["name"]: asset for asset in release["assets"]}
        if not set(remote) <= set(files):
            raise Error("existing draft contains unrelated files")
        for name, asset in remote.items():
            if (
                asset["size"] != files[name]["size"]
                or asset.get("digest") != "sha256:" + files[name]["sha256"]
            ):
                raise Error("existing draft asset differs; refusing overwrite")
    notes = json.loads(
        command(
            "git",
            "show",
            f"{plan['source_sha']}:distribution/app-store/release-notes-{plan['version']}.json",
        )
    )
    body = notes["en-US"] + "\n\n" + notes["zh-Hans"]
    # The existing tag, checked immediately before and after publication,
    # remains the source identity. target_commitish is only an API default.
    verify_source(plan["source_sha"], command("git", "rev-parse", "HEAD"))
    metadata = {
        "tag_name": tag,
        "target_commitish": "master",
        "name": f"Mithka {plan['version']}",
        "body": body,
        "draft": True,
        "prerelease": False,
        "make_latest": "false",
    }
    if release:
        release = api(f"releases/{release['id']}", metadata, method="PATCH")
    else:
        release = api("releases", metadata)
    remote = {asset["name"] for asset in release["assets"]}
    for name in sorted(set(files) - remote):
        command("gh", "release", "upload", tag, str(root / name), "--repo", REPO)
    release = api(f"releases/{release['id']}")
    verify_assets(release, files)
    verify_source(plan["source_sha"], command("git", "rev-parse", "HEAD"))
    release = api(
        f"releases/{release['id']}",
        {
            "target_commitish": "master",
            "draft": False,
            "prerelease": False,
            "make_latest": "true",
        },
        method="PATCH",
    )
    if release["draft"] or release["prerelease"]:
        raise Error("release was not published as stable")
    verify_assets(release, files)
    verify_source(plan["source_sha"], command("git", "rev-parse", "HEAD"))
    print(f"Published {tag}: eleven verified packages from {plan['source_sha']}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-run-id", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--controller", required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--assets")
    args = parser.parse_args()
    context(publishing=not args.verify)
    plan = inspect(args.package_run_id, args.source, args.controller)
    if not args.verify:
        if not args.assets:
            raise Error("publication needs verified downloaded artifacts")
        publish(plan, args.package_run_id, args.assets, os.environ["GITHUB_RUN_ID"])
    print(f"Verified original package run {args.package_run_id} for {plan['version']}.")


if __name__ == "__main__":
    try:
        main()
    except (Error, KeyError, ValueError) as error:
        print(f"Store GitHub publication stopped: {error}")
        raise SystemExit(1)
