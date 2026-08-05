#!/usr/bin/env python3
"""Fills untranslated strings from Telegram's official language packs.

    python3 translations/tools/import_telegram.py --dry-run
    python3 translations/tools/import_telegram.py

Mithka writes its own copy. This only closes gaps, under a deliberately strict
rule — a string is adopted when *all* of these hold:

* our value for the locale is byte-identical to the English source, i.e. the
  key was never translated;
* our English text matches exactly one phrase in Telegram's English Android
  pack, so the meaning is unambiguous — not merely similar;
* the placeholder sets agree after converting Telegram's `%1$s` style to
  `{value1}`;
* Telegram's translation is non-empty and actually differs from the English.

Anything looser was measured and rejected. Adopting Telegram's wording for the
753 keys the app used to map at runtime would rewrite 3382 already-reviewed
strings, and many would be worse: several distinct Mithka errors collapse onto
one generic "An error occurred", and "Find Groups" becomes "Search Chats".
A correct local translation beats a nearby upstream one.

Counted (plural) keys are never touched.
"""

from __future__ import annotations

import argparse
import collections
import html
import re
import sys
import urllib.request
from pathlib import Path

from mithka_l10n import (
    MESSAGES_FILE,
    load_locales,
    placeholders,
    read_catalogue,
    write_catalogue,
)

EXPORT_URL = "https://translations.telegram.org/{code}/android/export"
CACHE = Path(__file__).resolve().parent / ".telegram-cache"
STRING_RE = re.compile(r'<string name="([^"]+)">(.*?)</string>', re.S)

HEADER = (
    "Mithka's string catalogue. Edit translations here; "
    "run tools/gen_assets.py to push them into the app."
)

# Keys whose English is identical to a Telegram phrase but whose UI context is
# not. An exact text match cannot see the difference, so they are named here.
SKIP = {
    # Telegram's "Info" is the profile section — zh-hans renders it
    # "个人信息" (personal information). Mithka's is a message action.
    "messageActionInfo",
    # Telegram's Spanish drops the noun ("Todas"), which reads as a bare
    # "All" in Mithka's reactions picker.
    "groupAdminAllReactions",
}

ANDROID_ESCAPE = re.compile(r"\\([\\'\"@?nt])")
ANDROID_UNESCAPE = {"n": "\n", "t": "\t"}


def fetch(code: str, *, refresh: bool) -> dict[str, str]:
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{code}.xml"
    if refresh or not path.exists():
        print(f"fetching {code}…", file=sys.stderr)
        with urllib.request.urlopen(EXPORT_URL.format(code=code)) as response:
            path.write_bytes(response.read())
    source = path.read_text(encoding="utf-8")
    return {
        match.group(1): html.unescape(match.group(2))
        for match in STRING_RE.finditer(source)
    }


def normalize(value: str) -> str:
    """Turns one Telegram Android string into Mithka's conventions."""
    # Telegram exports Android resource syntax, where an apostrophe is \' and a
    # line break is \n. Left alone, the backslash renders on screen.
    value = ANDROID_ESCAPE.sub(
        lambda m: ANDROID_UNESCAPE.get(m.group(1), m.group(1)), value
    )
    # Some CJK packs use fullwidth ％ and ＄ inside format specifiers.
    value = value.replace("％", "%").replace("＄", "$")
    value = re.sub(r"%(\d+)\$[@sd]", lambda m: "{value%s}" % m.group(1), value)
    return re.sub(r"%[@sd]", "{value1}", value)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would change without writing",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download the Telegram packs instead of using the cache",
    )
    args = parser.parse_args()

    source, locales = load_locales()
    english = read_catalogue(source.directory / MESSAGES_FILE)

    telegram_english = fetch(source.telegram_code, refresh=args.refresh)
    by_text: dict[str, list[str]] = collections.defaultdict(list)
    for key, value in telegram_english.items():
        by_text[normalize(value).strip()].append(key)

    # Only phrases Telegram states exactly once: two keys sharing wording in
    # English may well diverge in another language.
    unambiguous = {
        key: by_text[value.strip()][0]
        for key, value in english.strings.items()
        if key not in SKIP and len(by_text.get(value.strip(), ())) == 1
    }

    total = 0
    for locale in locales:
        if locale.app_key == source.app_key:
            continue
        path = locale.directory / MESSAGES_FILE
        catalogue = read_catalogue(path)
        pack = fetch(locale.telegram_code, refresh=args.refresh)

        adopted: list[tuple[str, str, str]] = []
        for app_key, telegram_key in unambiguous.items():
            ours = catalogue.strings.get(app_key)
            if ours is None or english.strings.get(app_key) != ours:
                continue  # missing, counted, or already translated
            raw = pack.get(telegram_key)
            if raw is None or not raw.strip():
                continue
            value = normalize(raw)
            if value == ours or placeholders(value) != placeholders(ours):
                continue
            adopted.append((app_key, ours, value))

        print(f"\n{locale.tag}: {len(adopted)} string(s)")
        for app_key, ours, value in adopted:
            print(f"  {app_key}: {ours!r} -> {value!r}")
        total += len(adopted)

        if adopted and not args.dry_run:
            for app_key, _, value in adopted:
                catalogue.strings[app_key] = value
            write_catalogue(path, catalogue, header=HEADER)

    verb = "would adopt" if args.dry_run else "adopted"
    print(f"\n{verb} {total} string(s)")
    if not args.dry_run and total:
        print("Run tools/gen_assets.py to rebuild the app assets.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
