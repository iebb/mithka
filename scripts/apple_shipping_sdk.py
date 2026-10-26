#!/usr/bin/env python3
"""Fail-closed iOS shipping SDK selection and compiled-artifact provenance.

No signing, downloading, xcode-select mutation, or XCODE_XCCONFIG_FILE changes.
Uses actual tools, not application names, as version authority. Python stdlib only.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile

MINIMUM = (27, 1, 0)
# Shipping approval is for the 27.1 RC/GA series, not any numerically newer seed.
# Review Apple's upload compatibility before advancing this policy.
SHIPPING_SERIES = MINIMUM[:2]


class GuardError(Exception):
    pass


def version(value):
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise GuardError(f"Invalid numeric version: {value!r}")
    parts = tuple(map(int, value.split(".")))
    return parts + (0,) * (3 - len(parts))


def run(arguments, developer):
    # Preserve injected AirBuild signing/cache settings, including XCODE_XCCONFIG_FILE.
    env = dict(os.environ, DEVELOPER_DIR=str(developer))
    try:
        return subprocess.check_output(arguments, env=env, text=True, stderr=subprocess.PIPE).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        # Do not dump an arbitrary environment or command stderr (could contain secrets).
        raise GuardError(f"Cannot run {' '.join(arguments)} for {developer}") from error


def inspect(developer):
    developer = Path(developer).resolve()
    output = run(["xcodebuild", "-version"], developer)
    xcode = re.search(r"^Xcode (\d+(?:\.\d+){0,2})(.*)$", output, re.M)
    build = re.search(r"^Build version (\S+)$", output, re.M)
    if not xcode or not build:
        raise GuardError(f"Unrecognized xcodebuild -version from {developer}")
    # Reject explicitly labeled seeds; numeric-only output is not a seed oracle.
    # The shipping-series restriction below also avoids unrelated newer betas.
    if re.search(r"beta|preview", output, re.I):
        raise GuardError(f"Beta/preview Xcode is not a shipping RC: {developer}")
    sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], developer)
    sdk_build = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-build-version"], developer)
    if version(xcode[1]) < MINIMUM or version(sdk) < MINIMUM:
        raise GuardError(f"{developer}: actual Xcode {xcode[1]}, iphoneos SDK {sdk}; both must be >= 27.1 (RC accepted)")
    if version(xcode[1])[:2] != SHIPPING_SERIES or version(sdk)[:2] != SHIPPING_SERIES:
        raise GuardError(f"{developer}: Xcode {xcode[1]} / SDK {sdk} outside approved shipping series 27.1; newer seeds require explicit policy review")
    major, minor, patch = version(xcode[1])
    return {
        "developer_dir": str(developer),
        "xcode_version": xcode[1],
        "xcode_build": build[1],
        "dtxcode": f"{major}{minor}{patch}",
        "iphoneos_sdk_version": sdk,
        "iphoneos_sdk_build": sdk_build,
        "xcodebuild_version_output": output,
    }


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def select(args):
    candidates = list(Path(args.applications).glob("Xcode*.app/Contents/Developer"))
    if os.environ.get("DEVELOPER_DIR"):
        candidates.append(Path(os.environ["DEVELOPER_DIR"]))
    try:
        active = subprocess.check_output(["xcode-select", "-p"], text=True, stderr=subprocess.PIPE).strip()
        if active:
            candidates.append(Path(active))
    except (OSError, subprocess.CalledProcessError):
        pass
    available, rejected = [], []
    for candidate in sorted(set(p.resolve() for p in candidates)):
        try:
            available.append(inspect(candidate))
        except GuardError as error:
            rejected.append(str(error))
    provenance = {
        "schema": 1,
        "guard_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "minimum_xcode_and_iphoneos_sdk": "27.1",
        "approved_shipping_series": "27.1",
        "source_sha": os.environ.get("GITHUB_SHA", os.environ.get("SHIPPING_SOURCE_SHA", "unknown")),
        "xccconfig_injected": bool(os.environ.get("XCODE_XCCONFIG_FILE")),
        "rejected_candidates": rejected,
    }
    if not available:
        provenance["status"] = "blocked"
        write_json(args.provenance, provenance)
        raise GuardError("RELEASE BLOCKER: approved Xcode 27.1 RC/GA series with iphoneos SDK 27.1 unavailable; no older-SDK fallback. Provision a compatible runner. " + "; ".join(rejected))
    selected = max(available, key=lambda item: (version(item["xcode_version"]), version(item["iphoneos_sdk_version"]), item["developer_dir"]))
    provenance.update(status="selected", toolchain=selected)
    write_json(args.provenance, provenance)
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        if any(c in selected["developer_dir"] for c in "\r\n"):
            raise GuardError("Developer path cannot contain newlines")
        with open(github_env, "a") as stream:
            stream.write(f"DEVELOPER_DIR={selected['developer_dir']}\n")
    print(json.dumps(provenance, indent=2))


def artifact_plists(artifact):
    if artifact.suffix == ".ipa":
        with zipfile.ZipFile(artifact) as archive:
            names = [name for name in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info.plist", name)]
            if len(names) != 1:
                raise GuardError("IPA must contain exactly one top-level application")
            root = names[0].removesuffix("Info.plist")
            names += [name for name in archive.namelist() if name.startswith(root) and name != names[0] and re.search(r"\.(app|appex)/Info.plist$", name)]
            return [(name, plistlib.loads(archive.read(name))) for name in names]
    applications = artifact / "Products/Applications" if artifact.suffix == ".xcarchive" else artifact.parent
    apps = list(applications.glob("*.app")) if artifact.suffix == ".xcarchive" else [artifact]
    if len(apps) != 1 or not apps[0].is_dir():
        raise GuardError("Artifact must contain exactly one top-level application")
    paths = [apps[0] / "Info.plist"]
    paths += sorted(p / "Info.plist" for p in apps[0].rglob("*") if p.is_dir() and p.suffix in (".app", ".appex"))
    return [(str(p.relative_to(artifact if artifact.is_dir() else artifact.parent)), plistlib.loads(p.read_bytes())) for p in paths]


def verify(args):
    provenance = json.loads(Path(args.provenance).read_text())
    if provenance.get("status") != "selected":
        raise GuardError("No successful SDK selection provenance")
    expected = provenance["toolchain"]
    if str(Path(os.environ.get("DEVELOPER_DIR", "")).resolve()) != expected["developer_dir"]:
        raise GuardError("DEVELOPER_DIR changed or missing since selection")
    actual = inspect(expected["developer_dir"])
    if actual != expected:
        raise GuardError("Actual Xcode/iphoneos SDK changed since selection")
    artifact = Path(args.artifact)
    records = []
    for name, info in artifact_plists(artifact):
        fields = {key: info.get(key) for key in ("DTSDKName", "DTSDKBuild", "DTXcode", "DTXcodeBuild", "DTPlatformName", "DTPlatformVersion")}
        sdk_match = re.fullmatch(r"iphoneos(\d+(?:\.\d+){0,2})", str(fields["DTSDKName"]))
        if not sdk_match or version(sdk_match[1]) < MINIMUM or version(sdk_match[1]) != version(actual["iphoneos_sdk_version"]):
            raise GuardError(f"RELEASE BLOCKER: {name}: compiled DTSDKName {fields['DTSDKName']!r} does not match selected iphoneos SDK >= 27.1")
        required = {"DTSDKBuild": actual["iphoneos_sdk_build"], "DTXcode": actual["dtxcode"], "DTXcodeBuild": actual["xcode_build"], "DTPlatformName": "iphoneos"}
        for key, value in required.items():
            if fields[key] != value:
                raise GuardError(f"RELEASE BLOCKER: {name}: {key}={fields[key]!r}, expected {value!r}")
        if version(str(fields["DTPlatformVersion"])) != version(actual["iphoneos_sdk_version"]):
            raise GuardError(f"RELEASE BLOCKER: {name}: DTPlatformVersion does not match selected SDK")
        records.append({"plist": name, **fields})
    report = {"status": "verified", "selection": provenance, "artifact": str(artifact), "compiled_bundles": records}
    if artifact.is_file():
        digest = hashlib.sha256()
        with artifact.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        report["artifact_sha256"] = digest.hexdigest()
    write_json(args.report, report)
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    selection = commands.add_parser("select")
    selection.add_argument("--applications", default="/Applications")
    selection.add_argument("--provenance", required=True)
    verification = commands.add_parser("verify")
    verification.add_argument("--provenance", required=True)
    verification.add_argument("--artifact", required=True, help=".xcarchive, .ipa, or device .app")
    verification.add_argument("--report", required=True)
    args = parser.parse_args()
    try:
        (select if args.command == "select" else verify)(args)
    except (GuardError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f"Shipping SDK guard: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
