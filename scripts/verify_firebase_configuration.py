#!/usr/bin/env python3
"""Verify FlutterFire options against native release inputs and built artifacts.

Client configuration is public SDK metadata, not an administrative credential.
Never print client keys or the contents of a native configuration on failure.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "ad.neko.mithka"


def require_equal(actual, expected, field):
    if actual != expected or not expected:
        raise ValueError(
            f"Firebase {field} is missing or differs from FlutterFire options"
        )


def options_for(root, platform):
    text = (root / "lib/firebase_options.dart").read_text(encoding="utf-8")
    match = re.search(
        rf"static const FirebaseOptions {platform} = FirebaseOptions\((.*?)\n  \);",
        text,
        re.S,
    )
    if not match:
        raise ValueError(f"No generated FlutterFire options for {platform}")
    options = dict(re.findall(r"(\w+): '([^']*)'", match[1]))
    manifest = json.loads((root / "firebase.json").read_text(encoding="utf-8"))
    platforms = manifest["flutter"]["platforms"]
    require_equal(options.get("projectId"), "mithka", "project")
    require_equal(
        platforms[platform]["default"]["projectId"],
        options["projectId"],
        "manifest project",
    )
    require_equal(
        platforms[platform]["default"]["appId"], options["appId"], "manifest app"
    )
    require_equal(
        platforms["dart"]["lib/firebase_options.dart"]["configurations"][platform],
        options["appId"],
        "Dart app",
    )
    return options


def check_ios(path, options):
    with path.open("rb") as stream:
        native = plistlib.load(stream)
    for field, key in {
        "projectId": "PROJECT_ID",
        "appId": "GOOGLE_APP_ID",
        "messagingSenderId": "GCM_SENDER_ID",
        "apiKey": "API_KEY",
        "iosBundleId": "BUNDLE_ID",
        "storageBucket": "STORAGE_BUCKET",
    }.items():
        require_equal(native.get(key), options.get(field), field)
    require_equal(native.get("BUNDLE_ID"), BUNDLE, "bundle")


def check_android(path, options):
    native = json.loads(path.read_text(encoding="utf-8"))
    matches = [
        client
        for client in native["client"]
        if client["client_info"]["android_client_info"]["package_name"] == BUNDLE
    ]
    if len(matches) != 1:
        raise ValueError("Expected exactly one Firebase Android client for Mithka")
    client = matches[0]
    require_equal(
        native["project_info"].get("project_id"), options.get("projectId"), "projectId"
    )
    require_equal(
        native["project_info"].get("project_number"),
        options.get("messagingSenderId"),
        "messagingSenderId",
    )
    require_equal(
        native["project_info"].get("storage_bucket"),
        options.get("storageBucket"),
        "storageBucket",
    )
    require_equal(
        client["client_info"].get("mobilesdk_app_id"), options.get("appId"), "appId"
    )
    keys = [item.get("current_key") for item in client.get("api_key", [])]
    if not options.get("apiKey") or options["apiKey"] not in keys:
        raise ValueError("Firebase Android client key differs from FlutterFire options")


def check_apk(apk, options):
    sdk = Path(os.environ.get("ANDROID_HOME", os.environ.get("ANDROID_SDK_ROOT", "")))
    analyzer = shutil.which("apkanalyzer") or str(
        sdk / "cmdline-tools/latest/bin/apkanalyzer"
    )
    package = subprocess.check_output(
        [analyzer, "manifest", "application-id", str(apk)],
        text=True,
        stderr=subprocess.PIPE,
    ).strip()
    require_equal(package, BUNDLE, "compiled Android package")
    for name, field in {
        "google_app_id": "appId",
        "gcm_defaultSenderId": "messagingSenderId",
        "project_id": "projectId",
        "google_api_key": "apiKey",
        "google_storage_bucket": "storageBucket",
    }.items():
        value = (
            subprocess.check_output(
                [
                    analyzer,
                    "resources",
                    "value",
                    "--config",
                    "default",
                    "--type",
                    "string",
                    "--name",
                    name,
                    str(apk),
                ],
                text=True,
                stderr=subprocess.PIPE,
            )
            .strip()
            .strip('"')
        )
        require_equal(value, options.get(field), f"compiled Android {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--ios-app", type=Path)
    parser.add_argument("--apk", type=Path)
    args = parser.parse_args()
    try:
        options = options_for(args.root, args.platform)
        if args.platform == "ios":
            check_ios(args.root / "ios/Runner/GoogleService-Info.plist", options)
            if args.ios_app:
                check_ios(args.ios_app / "GoogleService-Info.plist", options)
                with (args.ios_app / "Info.plist").open("rb") as stream:
                    info = plistlib.load(stream)
                require_equal(
                    info.get("CFBundleIdentifier"), BUNDLE, "compiled iOS bundle"
                )
        else:
            check_android(args.root / "android/app/google-services.json", options)
            if args.apk:
                check_apk(args.apk, options)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Do not echo parsing errors or command output that might contain keys.
        print(
            f"Firebase {args.platform} configuration verification failed",
            file=sys.stderr,
        )
        return 1
    print(
        f"Firebase {args.platform} inputs/artifacts match project mithka and FlutterFire options"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
