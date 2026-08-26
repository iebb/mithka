#!/usr/bin/env python3
"""Install one pinned mithka-tdjson release asset.

The checked-in schema-v2 manifest is the trust anchor. Archives downloaded from
the release are accepted only when their complete shape, sizes, and SHA-256
digests match that manifest.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


SCHEMA_VERSION = 2
REPOSITORY = "iebb/mithka-tdjson"
DEFAULT_MANIFEST = Path(__file__).with_name("tdjson-manifest.json")
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
GIT_SHA_PATTERN = re.compile(r"[0-9a-f]{40}")
RELEASE_TAG_PATTERN = re.compile(r"[A-Za-z0-9._-]+")

EXPECTED_MEMBERS = {
    "tdjson-android-arm64-v8a.zip": {
        "arm64-v8a/libtdjson.so",
    },
    "tdjson-android-armeabi-v7a.zip": {
        "armeabi-v7a/libtdjson.so",
    },
    "tdjson-android-x86_64.zip": {
        "x86_64/libtdjson.so",
    },
    "tdjson-ios.xcframework.zip": {
        "tdjson.xcframework/Info.plist",
        "tdjson.xcframework/ios-arm64/tdjson.framework/Headers/tdjson.h",
        "tdjson.xcframework/ios-arm64/tdjson.framework/Info.plist",
        "tdjson.xcframework/ios-arm64/tdjson.framework/Modules/module.modulemap",
        "tdjson.xcframework/ios-arm64/tdjson.framework/tdjson",
        "tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Headers/tdjson.h",
        "tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Info.plist",
        "tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Modules/module.modulemap",
        "tdjson.xcframework/ios-arm64-simulator/tdjson.framework/tdjson",
    },
    "tdjson-linux-arm64.zip": {"libtdjson.so"},
    "tdjson-linux-x64.zip": {"libtdjson.so"},
    "tdjson-macos-universal.zip": {"libtdjson.dylib"},
    "tdjson-windows-arm64.zip": {"tdjson.dll"},
    "tdjson-windows-x64.zip": {"tdjson.dll"},
}

MANIFEST_KEYS = {
    "schema_version",
    "release_tag",
    "tdlib_version",
    "upstream_repository",
    "upstream_sha",
    "mithka_tdjson_sha",
    "patchset_sha256",
    "build_definition_sha256",
    "assets",
}


class InstallError(Exception):
    pass


def parse_args():
    parser = argparse.ArgumentParser(
        description="Download, verify, and install a pinned tdjson release asset."
    )
    parser.add_argument("asset", choices=sorted(EXPECTED_MEMBERS))
    parser.add_argument(
        "destination",
        type=Path,
        help=(
            "output file when --member is supplied, otherwise the output "
            "directory for the archive's single top-level tree"
        ),
    )
    parser.add_argument(
        "--member",
        help="install only this archive member into the destination file",
    )
    parser.add_argument(
        "--mode",
        type=parse_mode,
        help="installed file mode in octal, for example 0644 or 0755",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help=f"checked-in schema-v2 manifest (default: {DEFAULT_MANIFEST})",
    )
    parser.add_argument(
        "--archive",
        type=Path,
        help="verify and install a local archive instead of downloading it",
    )
    args = parser.parse_args()
    if args.mode is not None and args.member is None:
        parser.error("--mode requires --member")
    return args


def parse_mode(value):
    try:
        mode = int(value, 8)
    except ValueError as error:
        raise argparse.ArgumentTypeError("mode must be an octal value") from error
    if mode < 0 or mode > 0o777:
        raise argparse.ArgumentTypeError("mode must be between 0000 and 0777")
    return mode


def unique_json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InstallError(f"manifest contains duplicate key: {key}")
        result[key] = value
    return result


def require_exact_keys(value, expected, context):
    if not isinstance(value, dict):
        raise InstallError(f"{context} must be an object")
    actual = set(value)
    if actual != expected:
        raise InstallError(
            f"{context} has unexpected keys: "
            f"expected {sorted(expected)}, got {sorted(actual)}"
        )


def require_string(value, context, pattern=None):
    if not isinstance(value, str) or not value:
        raise InstallError(f"{context} must be a non-empty string")
    if pattern is not None and pattern.fullmatch(value) is None:
        raise InstallError(f"{context} has an invalid value")


def require_positive_int(value, context):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise InstallError(f"{context} must be a positive integer")


def validate_member_path(member, context):
    require_string(member, context)
    path = PurePosixPath(member)
    if (
        path.is_absolute()
        or member.startswith("/")
        or "\\" in member
        or any(part in ("", ".", "..") for part in path.parts)
    ):
        raise InstallError(f"{context} is unsafe: {member}")


def load_manifest(path):
    if not path.is_file():
        raise InstallError(
            f"pinned tdjson manifest is missing: {path}. "
            "Add scripts/tdjson-manifest.json from the selected schema-v2 release."
        )
    try:
        manifest = json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=unique_json_object
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise InstallError(f"could not read tdjson manifest {path}: {error}") from error

    require_exact_keys(manifest, MANIFEST_KEYS, "manifest")
    if (
        isinstance(manifest["schema_version"], bool)
        or manifest["schema_version"] != SCHEMA_VERSION
    ):
        raise InstallError(
            f"unsupported tdjson manifest schema: {manifest['schema_version']!r}"
        )
    require_string(manifest["release_tag"], "release_tag", RELEASE_TAG_PATTERN)
    require_string(manifest["tdlib_version"], "tdlib_version")
    if manifest["upstream_repository"] != "tdlib/td":
        raise InstallError("upstream_repository must be tdlib/td")
    require_string(manifest["upstream_sha"], "upstream_sha", GIT_SHA_PATTERN)
    require_string(
        manifest["mithka_tdjson_sha"], "mithka_tdjson_sha", GIT_SHA_PATTERN
    )
    require_string(
        manifest["patchset_sha256"], "patchset_sha256", SHA256_PATTERN
    )
    require_string(
        manifest["build_definition_sha256"],
        "build_definition_sha256",
        SHA256_PATTERN,
    )

    assets = manifest["assets"]
    require_exact_keys(assets, set(EXPECTED_MEMBERS), "manifest assets")
    for asset_name, expected_members in EXPECTED_MEMBERS.items():
        asset = assets[asset_name]
        require_exact_keys(asset, {"sha256", "size", "members"}, asset_name)
        require_string(asset["sha256"], f"{asset_name}.sha256", SHA256_PATTERN)
        require_positive_int(asset["size"], f"{asset_name}.size")
        members = asset["members"]
        require_exact_keys(members, expected_members, f"{asset_name}.members")
        for member_name, member in members.items():
            validate_member_path(member_name, f"{asset_name} member")
            require_exact_keys(
                member,
                {"sha256", "size"},
                f"{asset_name}.members[{member_name!r}]",
            )
            require_string(
                member["sha256"],
                f"{asset_name}.members[{member_name!r}].sha256",
                SHA256_PATTERN,
            )
            require_positive_int(
                member["size"],
                f"{asset_name}.members[{member_name!r}].size",
            )
    return manifest


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def installed_file_matches(destination, metadata):
    return (
        destination.is_file()
        and not destination.is_symlink()
        and destination.stat().st_size == metadata["size"]
        and sha256_file(destination) == metadata["sha256"]
    )


def tree_member_map(asset_name):
    members = EXPECTED_MEMBERS[asset_name]
    roots = {PurePosixPath(member).parts[0] for member in members}
    if len(roots) != 1 or any(len(PurePosixPath(member).parts) < 2 for member in members):
        raise InstallError(
            f"{asset_name} cannot be installed as a tree; use --member"
        )
    root = next(iter(roots))
    return {
        str(PurePosixPath(*PurePosixPath(member).parts[1:])): member
        for member in members
    }, root


def installed_tree_matches(destination, asset_name, asset):
    if not destination.is_dir() or destination.is_symlink():
        return False
    relative_members, _ = tree_member_map(asset_name)
    actual = set()
    for path in destination.rglob("*"):
        if path.is_symlink():
            return False
        if path.is_file():
            actual.add(path.relative_to(destination).as_posix())
    if actual != set(relative_members):
        return False
    return all(
        installed_file_matches(
            destination / Path(relative_name), asset["members"][member_name]
        )
        for relative_name, member_name in relative_members.items()
    )


def normalize_tree_modes(destination):
    for path in destination.rglob("*"):
        if path.is_dir():
            path.chmod(0o755)
        elif path.is_file():
            path.chmod(0o755 if path.name == "tdjson" else 0o644)


def remove_generated_path(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def tree_backup_paths(destination):
    if not destination.parent.is_dir():
        return []
    prefix = f".{destination.name}.install-"
    suffix = "-previous"
    backups = [
        path
        for path in destination.parent.iterdir()
        if path.name.startswith(prefix) and path.name.endswith(suffix)
    ]
    return sorted(
        backups,
        key=lambda path: path.lstat().st_mtime_ns,
        reverse=True,
    )


def recover_interrupted_tree_swap(destination):
    backups = tree_backup_paths(destination)
    if backups and not (destination.exists() or destination.is_symlink()):
        os.replace(backups[0], destination)


def cleanup_tree_backups(destination):
    for backup in tree_backup_paths(destination):
        remove_generated_path(backup)


def safe_zip_path(name):
    path = PurePosixPath(name.rstrip("/"))
    return bool(path.parts) and not (
        path.is_absolute()
        or name.startswith("/")
        or "\\" in name
        or any(part in ("", ".", "..") for part in path.parts)
    )


def validate_archive(archive_path, asset_name, asset):
    if not archive_path.is_file():
        raise InstallError(f"tdjson archive is missing: {archive_path}")
    actual_size = archive_path.stat().st_size
    if actual_size != asset["size"]:
        raise InstallError(
            f"{asset_name} size mismatch: expected {asset['size']}, got {actual_size}"
        )
    actual_sha256 = sha256_file(archive_path)
    if actual_sha256 != asset["sha256"]:
        raise InstallError(
            f"{asset_name} SHA-256 mismatch: "
            f"expected {asset['sha256']}, got {actual_sha256}"
        )

    expected = set(asset["members"])
    infos = {}
    try:
        with zipfile.ZipFile(archive_path) as archive:
            for info in archive.infolist():
                if not safe_zip_path(info.filename):
                    raise InstallError(
                        f"{asset_name} contains unsafe member: {info.filename!r}"
                    )
                if info.flag_bits & 0x1:
                    raise InstallError(
                        f"{asset_name} contains encrypted member: {info.filename}"
                    )
                file_mode = info.external_attr >> 16
                if stat.S_ISLNK(file_mode):
                    raise InstallError(
                        f"{asset_name} contains symlink member: {info.filename}"
                    )
                if info.is_dir():
                    directory = info.filename.rstrip("/") + "/"
                    if not any(member.startswith(directory) for member in expected):
                        raise InstallError(
                            f"{asset_name} contains unexpected directory: {info.filename}"
                        )
                    continue
                if info.filename in infos:
                    raise InstallError(
                        f"{asset_name} contains duplicate member: {info.filename}"
                    )
                infos[info.filename] = info

            if set(infos) != expected:
                raise InstallError(
                    f"{asset_name} member mismatch: "
                    f"expected {sorted(expected)}, got {sorted(infos)}"
                )
            for member_name, metadata in asset["members"].items():
                info = infos[member_name]
                if info.file_size != metadata["size"]:
                    raise InstallError(
                        f"{asset_name}:{member_name} size mismatch: "
                        f"expected {metadata['size']}, got {info.file_size}"
                    )
                digest = hashlib.sha256()
                with archive.open(info) as stream:
                    while True:
                        chunk = stream.read(1024 * 1024)
                        if not chunk:
                            break
                        digest.update(chunk)
                if digest.hexdigest() != metadata["sha256"]:
                    raise InstallError(
                        f"{asset_name}:{member_name} SHA-256 mismatch"
                    )
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        raise InstallError(f"could not validate {asset_name}: {error}") from error
    return infos


def release_url(release_tag, asset_name):
    return (
        f"https://github.com/{REPOSITORY}/releases/download/"
        f"{release_tag}/{asset_name}"
    )


def download(url, destination, expected_size):
    request = urllib.request.Request(
        url, headers={"User-Agent": "Mithka-tdjson-installer/2"}
    )
    for attempt in range(1, 5):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                if not response.geturl().startswith("https://"):
                    raise InstallError("tdjson download redirected away from HTTPS")
                content_length = response.headers.get("Content-Length")
                if content_length is not None and int(content_length) != expected_size:
                    raise InstallError(
                        f"tdjson download size header mismatch: "
                        f"expected {expected_size}, got {content_length}"
                    )
                with destination.open("wb") as output:
                    downloaded = 0
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        downloaded += len(chunk)
                        if downloaded > expected_size:
                            raise InstallError(
                                "tdjson download exceeded its pinned size"
                            )
                        output.write(chunk)
                    output.flush()
                    os.fsync(output.fileno())
                if downloaded != expected_size:
                    raise InstallError(
                        f"tdjson download size mismatch: "
                        f"expected {expected_size}, got {downloaded}"
                    )
            return
        except (InstallError, OSError, urllib.error.URLError, ValueError) as error:
            try:
                destination.unlink()
            except FileNotFoundError:
                pass
            if attempt == 4:
                raise InstallError(f"could not download {url}: {error}") from error
            delay = 2 ** (attempt - 1)
            print(
                f"warning: tdjson download failed; retrying in {delay}s: {error}",
                file=sys.stderr,
            )
            time.sleep(delay)


def archive_mode(info, fallback):
    mode = (info.external_attr >> 16) & 0o777
    return mode or fallback


def copy_member(archive, info, destination, metadata, mode):
    digest = hashlib.sha256()
    size = 0
    with archive.open(info) as source, destination.open("wb") as output:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            output.write(chunk)
            digest.update(chunk)
            size += len(chunk)
        output.flush()
        os.fsync(output.fileno())
    if size != metadata["size"] or digest.hexdigest() != metadata["sha256"]:
        raise InstallError(f"archive member changed while installing: {info.filename}")
    destination.chmod(mode)


def install_member(archive_path, info, destination, metadata, requested_mode):
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.install-", dir=str(destination.parent)
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(archive_path) as archive:
            copy_member(
                archive,
                info,
                temporary,
                metadata,
                requested_mode
                if requested_mode is not None
                else archive_mode(info, 0o644),
            )
        os.replace(temporary, destination)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def install_tree(archive_path, infos, destination, asset_name, asset):
    relative_members, root = tree_member_map(asset_name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{destination.name}.install-", dir=str(destination.parent)
        )
    )
    payload = staging / "payload"
    payload.mkdir()
    backup = staging.with_name(f"{staging.name}-previous")
    moved_previous = False
    installed = False
    try:
        with zipfile.ZipFile(archive_path) as archive:
            for relative_name, member_name in sorted(relative_members.items()):
                info = infos[member_name]
                output = payload / Path(relative_name)
                output.parent.mkdir(parents=True, exist_ok=True)
                fallback_mode = 0o755 if output.name == "tdjson" else 0o644
                copy_member(
                    archive,
                    info,
                    output,
                    asset["members"][member_name],
                    fallback_mode,
                )
        if not installed_tree_matches(payload, asset_name, asset):
            raise InstallError(f"staged {root} failed verification")
        if destination.exists() or destination.is_symlink():
            os.replace(destination, backup)
            moved_previous = True
        try:
            os.replace(payload, destination)
            installed = True
            if not installed_tree_matches(destination, asset_name, asset):
                raise InstallError(f"installed {root} failed verification")
        except BaseException:
            if moved_previous:
                installed = False
                if destination.exists() or destination.is_symlink():
                    remove_generated_path(destination)
                try:
                    os.replace(backup, destination)
                    moved_previous = False
                except Exception as restore_error:
                    raise InstallError(
                        "could not restore the previous tdjson tree; "
                        f"it remains at {backup}: {restore_error}"
                    ) from restore_error
            raise
    finally:
        shutil.rmtree(staging, ignore_errors=True)
        if installed and moved_previous:
            if backup.is_dir() and not backup.is_symlink():
                shutil.rmtree(backup)
            else:
                try:
                    backup.unlink()
                except FileNotFoundError:
                    pass


def run(args):
    manifest = load_manifest(args.manifest)
    asset = manifest["assets"][args.asset]

    if args.member is not None:
        if args.member not in EXPECTED_MEMBERS[args.asset]:
            raise InstallError(
                f"{args.member} is not a declared member of {args.asset}"
            )
        metadata = asset["members"][args.member]
        if installed_file_matches(args.destination, metadata):
            if args.mode is not None:
                args.destination.chmod(args.mode)
            print(f"Verified pinned tdjson: {args.destination}")
            return
    else:
        recover_interrupted_tree_swap(args.destination)
        if installed_tree_matches(args.destination, args.asset, asset):
            normalize_tree_modes(args.destination)
            cleanup_tree_backups(args.destination)
            print(f"Verified pinned tdjson tree: {args.destination}")
            return

    with tempfile.TemporaryDirectory(prefix="mithka-tdjson-") as temporary:
        if args.archive is None:
            archive_path = Path(temporary) / args.asset
            url = release_url(manifest["release_tag"], args.asset)
            print(f"Downloading {args.asset} from {manifest['release_tag']}")
            download(url, archive_path, asset["size"])
        else:
            archive_path = args.archive
        infos = validate_archive(archive_path, args.asset, asset)
        if args.member is not None:
            install_member(
                archive_path,
                infos[args.member],
                args.destination,
                asset["members"][args.member],
                args.mode,
            )
            if not installed_file_matches(args.destination, asset["members"][args.member]):
                raise InstallError(
                    f"installed tdjson member failed verification: {args.destination}"
                )
            print(f"Installed pinned tdjson: {args.destination}")
        else:
            install_tree(
                archive_path, infos, args.destination, args.asset, asset
            )
            cleanup_tree_backups(args.destination)
            print(f"Installed pinned tdjson tree: {args.destination}")


def main():
    try:
        run(parse_args())
    except InstallError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
