"""Shared helpers for reading and writing Mithka's localization catalogues.

The canonical form of every string is an Android-style ``strings.xml``. That
format was chosen because it is what every mainstream translation tool ingests
without a custom parser, and because ``<plurals>`` gives us CLDR plural forms
without inventing a convention.

Placeholders use Mithka's ``{value1}`` form. Counted templates additionally get
``{count}``, which is the number the plural category was chosen from.
"""

from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STRINGS_DIR = ROOT / "strings"
LOCALES_FILE = ROOT / "locales.json"

MESSAGES_FILE = "strings.xml"
COUNTRIES_FILE = "countries.xml"

PLACEHOLDER = re.compile(r"\{(value\d+|count)\}")
COUNTRY_KEY = re.compile(r"^country[A-Z]{2}$")

# Ordered as CLDR lists them, so generated files and error messages are stable.
CLDR_CATEGORIES = ("zero", "one", "two", "few", "many", "other")


@dataclass(frozen=True)
class Locale:
    tag: str
    app_key: str
    name: str
    native_name: str
    plural_categories: tuple[str, ...]
    telegram_code: str

    @property
    def directory(self) -> Path:
        return STRINGS_DIR / self.tag


@dataclass
class Catalogue:
    """One locale's messages: flat strings plus counted plural sets."""

    strings: dict[str, str]
    plurals: dict[str, dict[str, str]]

    @property
    def keys(self) -> set[str]:
        return set(self.strings) | set(self.plurals)


def load_locales() -> tuple[Locale, list[Locale]]:
    """Returns the source locale and every locale, source first."""
    data = json.loads(LOCALES_FILE.read_text(encoding="utf-8"))
    locales = [
        Locale(
            tag=entry["tag"],
            app_key=entry["appKey"],
            name=entry["name"],
            native_name=entry["nativeName"],
            plural_categories=tuple(entry["pluralCategories"]),
            telegram_code=entry["telegramCode"],
        )
        for entry in data["locales"]
    ]
    by_tag = {locale.tag: locale for locale in locales}
    source = by_tag[data["source"]]
    ordered = [source] + [locale for locale in locales if locale.tag != source.tag]
    return source, ordered


def read_catalogue(path: Path) -> Catalogue:
    """Reads one ``strings.xml``."""
    if not path.exists():
        raise FileNotFoundError(path)
    root = ET.parse(path).getroot()
    if root.tag != "resources":
        raise ValueError(f"{path}: root element is <{root.tag}>, expected <resources>")

    strings: dict[str, str] = {}
    plurals: dict[str, dict[str, str]] = {}

    for element in root:
        if element.tag not in ("string", "plurals"):
            raise ValueError(f"{path}: unexpected element <{element.tag}>")
        name = element.get("name")
        if not name:
            raise ValueError(f"{path}: <{element.tag}> without a name attribute")
        if name in strings or name in plurals:
            raise ValueError(f"{path}: duplicate key {name}")

        if element.tag == "string":
            # ElementTree resolves &amp; &lt; &gt; and the &#10; used for
            # newlines, so the parsed text is already the exact runtime value.
            strings[name] = element.text or ""
            continue

        forms: dict[str, str] = {}
        for item in element:
            if item.tag != "item":
                raise ValueError(f"{path}: <plurals name={name}> holds <{item.tag}>")
            quantity = item.get("quantity")
            if quantity not in CLDR_CATEGORIES:
                raise ValueError(
                    f"{path}: <plurals name={name}> has quantity {quantity!r}"
                )
            if quantity in forms:
                raise ValueError(f"{path}: {name} repeats quantity {quantity}")
            forms[quantity] = item.text or ""
        if not forms:
            raise ValueError(f"{path}: <plurals name={name}> is empty")
        plurals[name] = forms

    return Catalogue(strings=strings, plurals=plurals)


def _escape(value: str) -> str:
    # Newlines become numeric references so every entry stays on one line and
    # diffs stay readable; ElementTree decodes them back on read.
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\n", "&#10;")
    )


def _space_attr(value: str) -> str:
    # Significant leading or trailing whitespace would be invisible in the file
    # and is silently trimmed by some editors and translation tools.
    return ' xml:space="preserve"' if value != value.strip() else ""


def write_catalogue(path: Path, catalogue: Catalogue, *, header: str) -> None:
    """Writes a catalogue back out, sorted by key, one entry per line."""
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        f"<!-- {header} -->",
        "<resources>",
    ]
    for key in sorted(catalogue.keys):
        if key in catalogue.strings:
            value = catalogue.strings[key]
            lines.append(
                f'    <string name="{key}"{_space_attr(value)}>'
                f"{_escape(value)}</string>"
            )
            continue
        forms = catalogue.plurals[key]
        lines.append(f'    <plurals name="{key}">')
        for quantity in CLDR_CATEGORIES:
            if quantity not in forms:
                continue
            value = forms[quantity]
            lines.append(
                f'        <item quantity="{quantity}"{_space_attr(value)}>'
                f"{_escape(value)}</item>"
            )
        lines.append("    </plurals>")
    lines.append("</resources>")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_locale(locale: Locale) -> tuple[Catalogue, Catalogue]:
    """Returns ``(messages, countries)`` for one locale."""
    return (
        read_catalogue(locale.directory / MESSAGES_FILE),
        read_catalogue(locale.directory / COUNTRIES_FILE),
    )


def placeholders(value: str) -> set[str]:
    return set(PLACEHOLDER.findall(value))
