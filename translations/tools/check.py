#!/usr/bin/env python3
"""Validates every catalogue in ``strings/``.

    python3 translations/tools/check.py

Enforces the invariants the app depends on:

* every locale carries exactly the source locale's keys, so a lookup can never
  miss in one language and hit in another;
* a key is a plain string in every locale or a plural set in every locale;
* a plural set declares exactly the CLDR categories its locale uses, so plural
  selection can never fall through;
* every form uses the same placeholder set as the matching source form, since
  the app rejects a value with an unresolved placeholder;
* country catalogues hold only ``countryXX`` keys, and message catalogues hold
  none, because the app's lookup order relies on the two being disjoint;
* no value is empty, which would render as a blank label.
"""

from __future__ import annotations

import sys

from mithka_l10n import (
    COUNTRIES_FILE,
    COUNTRY_KEY,
    MESSAGES_FILE,
    Catalogue,
    Locale,
    load_locales,
    placeholders,
    read_catalogue,
)


def _check_form(
    label: str, key: str, value: str, source_value: str, problems: list[str]
) -> None:
    if not value.strip():
        problems.append(f"{label}: empty value for {key}")
    mine, theirs = placeholders(value), placeholders(source_value)
    if mine != theirs:
        missing = ", ".join(sorted(theirs - mine)) or "-"
        extra = ", ".join(sorted(mine - theirs)) or "-"
        problems.append(
            f"{label}: {key} placeholder mismatch "
            f"(missing: {missing}; unexpected: {extra})"
        )


def _check_catalogue(
    locale: Locale,
    filename: str,
    catalogue: Catalogue,
    source: Catalogue,
    problems: list[str],
) -> None:
    label = f"{locale.tag}/{filename}"

    for key in sorted(source.keys - catalogue.keys):
        problems.append(f"{label}: missing key {key}")
    for key in sorted(catalogue.keys - source.keys):
        problems.append(f"{label}: unknown key {key}")

    for key in sorted(source.keys & catalogue.keys):
        source_is_plural = key in source.plurals
        if source_is_plural != (key in catalogue.plurals):
            kind = "plurals" if source_is_plural else "a plain string"
            problems.append(f"{label}: {key} must be {kind}, matching the source")
            continue

        if not source_is_plural:
            _check_form(
                label, key, catalogue.strings[key], source.strings[key], problems
            )
            continue

        forms = catalogue.plurals[key]
        expected = set(locale.plural_categories)
        for quantity in sorted(expected - set(forms)):
            problems.append(f"{label}: {key} is missing the '{quantity}' form")
        for quantity in sorted(set(forms) - expected):
            problems.append(
                f"{label}: {key} declares '{quantity}', which {locale.tag} "
                f"never selects (uses: {', '.join(locale.plural_categories)})"
            )
        # Every form carries the same placeholders, because the caller supplies
        # one argument set regardless of which category is chosen.
        source_form = source.plurals[key].get("other") or next(
            iter(source.plurals[key].values())
        )
        for quantity in sorted(set(forms) & expected):
            _check_form(
                label, f"{key}[{quantity}]", forms[quantity], source_form, problems
            )


def main() -> int:
    source, locales = load_locales()
    problems: list[str] = []

    source_messages = read_catalogue(source.directory / MESSAGES_FILE)
    source_countries = read_catalogue(source.directory / COUNTRIES_FILE)

    for key in sorted(source_messages.keys):
        if COUNTRY_KEY.match(key):
            problems.append(f"{source.tag}/{MESSAGES_FILE}: country key {key}")
    for key in sorted(source_countries.keys):
        if not COUNTRY_KEY.match(key):
            problems.append(f"{source.tag}/{COUNTRIES_FILE}: non-country key {key}")
    if source_countries.plurals:
        problems.append(
            f"{source.tag}/{COUNTRIES_FILE}: country names cannot be plural"
        )

    for locale in locales:
        for filename, expected in (
            (MESSAGES_FILE, source_messages),
            (COUNTRIES_FILE, source_countries),
        ):
            try:
                catalogue = read_catalogue(locale.directory / filename)
            except (FileNotFoundError, ValueError) as error:
                problems.append(str(error))
                continue
            _check_catalogue(locale, filename, catalogue, expected, problems)

    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(f"\n{len(problems)} problem(s)", file=sys.stderr)
        return 1

    total = len(source_messages.keys) + len(source_countries.keys)
    print(
        f"{len(locales)} locales x {total} keys "
        f"({len(source_messages.plurals)} counted): OK"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
