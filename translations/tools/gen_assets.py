#!/usr/bin/env python3
"""Generates the app's runtime locale assets from ``strings/``.

Mithka loads its catalogue as data, not code, so a translation change is an
asset change rather than a Dart recompile. This writes one compact JSON
document per locale plus a manifest:

    assets/l10n/manifest.json
    assets/l10n/<tag>.json

Usage:

    python3 translations/tools/gen_assets.py            # write
    python3 translations/tools/gen_assets.py --check    # fail if stale
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from mithka_l10n import ROOT, load_locales, read_locale

ASSETS_DIR = ROOT.parent / "assets" / "l10n"
MANIFEST = "manifest.json"


def _document(locale, messages, countries) -> str:
    payload = {
        "locale": locale.tag,
        "appKey": locale.app_key,
        "pluralCategories": list(locale.plural_categories),
        "strings": dict(sorted(messages.strings.items())),
        "plurals": {
            key: dict(sorted(forms.items()))
            for key, forms in sorted(messages.plurals.items())
        },
        "countries": dict(sorted(countries.strings.items())),
    }
    # separators drop the spaces json.dumps adds by default; the file is
    # generated and read by machines, and it ships in every build.
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the generated assets differ instead of writing them",
    )
    args = parser.parse_args()

    source, locales = load_locales()
    outputs: dict[Path, str] = {}

    for locale in locales:
        messages, countries = read_locale(locale)
        outputs[ASSETS_DIR / f"{locale.tag}.json"] = _document(
            locale, messages, countries
        )

    manifest = {
        "source": source.tag,
        "locales": [
            {
                "tag": locale.tag,
                "appKey": locale.app_key,
                "name": locale.name,
                "nativeName": locale.native_name,
            }
            for locale in locales
        ],
    }
    outputs[ASSETS_DIR / MANIFEST] = (
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    )

    stale = sorted(
        path
        for path, document in outputs.items()
        if not path.exists() or path.read_text(encoding="utf-8") != document
    )

    if args.check:
        if stale:
            for path in stale:
                print(f"out of date: {path}", file=sys.stderr)
            print(
                "\nRun `python3 translations/tools/gen_assets.py` and commit the "
                "result.",
                file=sys.stderr,
            )
            return 1
        print(f"{len(outputs)} locale assets are up to date")
        return 0

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    for path, document in outputs.items():
        path.write_text(document, encoding="utf-8")
    total = sum(len(document.encode("utf-8")) for document in outputs.values())
    print(f"wrote {len(outputs)} files to {ASSETS_DIR} ({total // 1024} KiB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
