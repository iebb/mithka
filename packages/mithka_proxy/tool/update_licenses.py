#!/usr/bin/env python3
"""Collect vendored Leaf and resolved Cargo license notices for Flutter."""

import argparse
import json
import pathlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    packages = {}
    for target in (
        "aarch64-linux-android", "armv7-linux-androideabi", "x86_64-linux-android",
        "aarch64-apple-ios", "aarch64-apple-ios-sim", "x86_64-apple-ios",
        "aarch64-apple-darwin", "x86_64-apple-darwin",
    ):
        metadata = json.loads(subprocess.check_output([
            "cargo", "metadata", "--locked", "--format-version", "1",
            "--manifest-path", str(root / "native/Cargo.toml"),
            "--filter-platform", target,
        ]))
        resolved = {node["id"] for node in metadata["resolve"]["nodes"]}
        for package in metadata["packages"]:
            if package["id"] in resolved:
                packages[package["id"]] = package
    own_license = (root.parents[1] / "LICENSE").read_text().strip()
    leaf_license = (root / "native/vendor/LEAF-LICENSE").read_text().strip()
    groups = {own_license: ["mithka_proxy"], leaf_license: ["Leaf"]}
    for package in sorted(packages.values(), key=lambda p: (p["name"], p["version"])):
        if package["source"] is None:
            continue
        directory = pathlib.Path(package["manifest_path"]).parent
        # This workspace subcrate omits its shared repository license files
        # from the crate archive. jni-sys ships those files from the same repo.
        if package["name"] == "jni-sys-macros":
            parent = next(p for p in packages.values() if p["name"] == "jni-sys")
            assert parent["repository"] == package["repository"]
            assert parent["license"] == package["license"]
            directory = pathlib.Path(parent["manifest_path"]).parent
        notices = [
            file for file in sorted(directory.iterdir())
            if file.is_file() and file.name.upper().startswith(
                ("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT")
            )
        ]
        if package.get("license_file"):
            file = directory / package["license_file"]
            if file not in notices:
                notices.append(file)
        if not notices:
            raise RuntimeError(f"No license notice for {package['name']} {package['version']}")
        for file in notices:
            text = file.read_text().strip()
            label = f"{package['name']} {package['version']} ({file.name})"
            groups.setdefault(text, []).append(label)
    # Flutter's license collector understands package names followed by their
    # text, with 80 hyphens separating independently licensed groups.
    generated = ("\n" + "-" * 80 + "\n").join(
        "\n".join(names) + "\n\n" + text + "\n"
        for text, names in groups.items()
    )
    destination = root / "LICENSE"
    if args.check:
        if not destination.exists() or destination.read_text() != generated:
            raise SystemExit("Run python3 packages/mithka_proxy/tool/update_licenses.py")
        print("Rust dependency license notices are up to date")
    else:
        destination.write_text(generated)
        print(f"Wrote {len(groups)} license groups to {destination}")


if __name__ == "__main__":
    main()
