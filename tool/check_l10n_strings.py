#!/usr/bin/env python3
"""Fail if visible Dart UI string literals live outside lib/l10n."""

from __future__ import annotations

import sys
import re
from pathlib import Path

from migrate_l10n_strings import has_han, parse_literals, strip_comments_mask


ROOT = Path(__file__).resolve().parents[1]
RANDOM_L10N_KEY = re.compile(r"^[A-Za-z][A-Za-z0-9]*Text\d{3}[A-Fa-f0-9]{5,6}$")
COUNTRY_NAME_L10N_KEY = re.compile(r"^country(?!Picker)(?![A-Z]{2}$)[A-Z][A-Za-z0-9]*$")
VISIBLE_NAMED_ARGS = {
    "cancelText",
    "confirmText",
    "helperText",
    "hintText",
    "label",
    "labelText",
    "placeholder",
    "semanticLabel",
    "submitText",
    "title",
    "tooltip",
    "value",
}
ALLOWED_VISIBLE_VALUES = {
    "",
    "A",
    "GitHub",
    "Mithka",
    "github.com/iebb/mithka",
    "ieb",
    "mithka.ieb.app",
    "t.me/mithka",
    "telegram.org/tos",
}
SUSPICIOUS_RENDER_FIELDS = {
    "action.label",
    "activeFilter.title",
    "filter.title",
    "item.$2",
    "language.label",
    "o.title",
    "provider.label",
    "row.title",
    "row.value",
    "widget.displayTitle",
    "widget.title",
    "_tabs[i].label",
}
CONTENT_RENDER_EXPRESSIONS = {
    "_initial(widget.title)",
    "item.title",
    "m.senderName ?? widget.title",
}


def has_localized_script(text: str) -> bool:
    return any(
        has_han(ch)
        or "\u00c0" <= ch <= "\u024f"
        or "\u3040" <= ch <= "\u30ff"
        or "\u0400" <= ch <= "\u04ff"
        or "\u0600" <= ch <= "\u06ff"
        or "\u0900" <= ch <= "\u097f"
        or "\uac00" <= ch <= "\ud7af"
        or "\u0e00" <= ch <= "\u0e7f"
        for ch in text
    )


def line_for(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def is_visible_ui_literal(text: str, offset: int) -> bool:
    prefix = text[max(0, offset - 80) : offset]
    if re.search(r"\bText\s*\(\s*$", prefix):
        return True
    named_arg = re.search(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$", prefix)
    return named_arg is not None and named_arg.group(1) in VISIBLE_NAMED_ARGS


def is_nonlocalized_token(value: str) -> bool:
    if value in ALLOWED_VISIBLE_VALUES:
        return True
    if "$" in value:
        return True
    if value.startswith(("http://", "https://", "@", "/", "#")):
        return True
    return not any(ch.isalpha() for ch in value)


def matching_paren(text: str, open_index: int) -> int:
    depth = 0
    quote: str | None = None
    triple = False
    escaped = False
    i = open_index
    while i < len(text):
        ch = text[i]
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif triple and text.startswith(quote * 3, i):
                i += 2
                quote = None
                triple = False
            elif not triple and ch == quote:
                quote = None
        else:
            if text.startswith("'''", i) or text.startswith('"""', i):
                quote = text[i]
                triple = True
                i += 2
            elif ch in "'\"":
                quote = ch
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def first_arg(text: str, open_index: int, close_index: int) -> tuple[int, int]:
    depth = 0
    quote: str | None = None
    triple = False
    escaped = False
    start = open_index + 1
    i = start
    while i < close_index:
        ch = text[i]
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif triple and text.startswith(quote * 3, i):
                i += 2
                quote = None
                triple = False
            elif not triple and ch == quote:
                quote = None
        else:
            if text.startswith("'''", i) or text.startswith('"""', i):
                quote = text[i]
                triple = True
                i += 2
            elif ch in "'\"":
                quote = ch
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "," and depth == 0:
                return start, i
        i += 1
    return start, close_index


def direct_text_key_renders(text: str) -> list[int]:
    offsets: list[int] = []
    index = 0
    while True:
        index = text.find("Text(", index)
        if index < 0:
            return offsets
        if index > 0 and (text[index - 1].isalnum() or text[index - 1] == "_"):
            index += 5
            continue
        close_index = matching_paren(text, index + 4)
        if close_index < 0:
            return offsets
        arg_start, arg_end = first_arg(text, index + 4, close_index)
        expression = text[arg_start:arg_end]
        if (
            "AppStringKeys." in expression
            and ".l10n(" not in expression
            and "AppStrings.t(" not in expression
            and "AppLocalizations.of(" not in expression
            and "telegramText(" not in expression
        ):
            offsets.append(index)
        index = close_index + 1


def text_expressions(text: str) -> list[tuple[int, str]]:
    expressions: list[tuple[int, str]] = []
    index = 0
    while True:
        index = text.find("Text(", index)
        if index < 0:
            return expressions
        if index > 0 and (text[index - 1].isalnum() or text[index - 1] == "_"):
            index += 5
            continue
        close_index = matching_paren(text, index + 4)
        if close_index < 0:
            return expressions
        arg_start, arg_end = first_arg(text, index + 4, close_index)
        expressions.append((index, text[arg_start:arg_end].strip()))
        index = close_index + 1


def indirect_key_render_failures(text: str) -> list[tuple[int, str]]:
    failures: list[tuple[int, str]] = []
    fields = set(
        re.findall(
            r"this\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*AppStringKeys\.[A-Za-z0-9_]+",
            text,
        )
    )
    for field in sorted(fields):
        for offset, expression in text_expressions(text):
            if (
                f"widget.{field}" not in expression
                or ".l10n(" in expression
                or "telegramText(" in expression
            ):
                continue
            if expression in CONTENT_RENDER_EXPRESSIONS:
                continue
            failures.append((offset, f"default AppStringKeys field: {expression}"))
    for offset, expression in text_expressions(text):
        if (
            ".l10n(" in expression
            or "AppStrings.t(" in expression
            or "telegramText(" in expression
        ):
            continue
        if expression in CONTENT_RENDER_EXPRESSIONS:
            continue
        if any(field in expression for field in SUSPICIOUS_RENDER_FIELDS):
            failures.append((offset, f"suspicious unlocalized field: {expression}"))
    return failures


def main() -> int:
    failures: list[str] = []
    l10n_file = ROOT / "lib" / "l10n" / "app_localizations.dart"
    if l10n_file.exists():
        l10n_text = l10n_file.read_text()
        for match in re.finditer(
            r"static const ([A-Za-z_][A-Za-z0-9_]*) = '([^']+)';",
            l10n_text,
        ):
            identifier, value = match.groups()
            line = line_for(l10n_text, match.start())
            if RANDOM_L10N_KEY.match(identifier) or RANDOM_L10N_KEY.match(value):
                failures.append(
                    f"lib/l10n/app_localizations.dart:"
                    f"{line}: "
                    f"random l10n key: {identifier}"
                )
            if COUNTRY_NAME_L10N_KEY.match(identifier) or COUNTRY_NAME_L10N_KEY.match(
                value
            ):
                failures.append(
                    f"lib/l10n/app_localizations.dart:"
                    f"{line}: "
                    f"country l10n key must use ISO 3166-1 alpha-2: {identifier}"
                )
    for base in [ROOT / "lib"]:
        for path in sorted(base.rglob("*.dart")):
            rel = path.relative_to(ROOT)
            if rel.parts[:2] == ("lib", "l10n"):
                continue
            text = path.read_text()
            comments = strip_comments_mask(text)
            raw_localized_lines = {
                line_for(text, i)
                for i, ch in enumerate(text)
                if not comments[i] and has_localized_script(ch)
            }
            for line in sorted(raw_localized_lines):
                failures.append(f"{rel}:{line}: raw localized script outside lib/l10n")
            for offset in direct_text_key_renders(text):
                failures.append(
                    f"{rel}:{line_for(text, offset)}: "
                    "AppStringKeys rendered directly in Text"
                )
            for offset, reason in indirect_key_render_failures(text):
                failures.append(f"{rel}:{line_for(text, offset)}: {reason}")
            for literal in parse_literals(text):
                if has_localized_script(literal.value):
                    failures.append(
                        f"{rel}:{line_for(text, literal.start)}: localized literal: {literal.raw}"
                    )
                    continue
                if is_visible_ui_literal(text, literal.start) and not is_nonlocalized_token(
                    literal.value
                ):
                    failures.append(
                        f"{rel}:{line_for(text, literal.start)}: UI literal: {literal.raw}"
                    )
    if failures:
        print("\n".join(failures))
        return 1
    print("No visible UI string literals outside lib/l10n.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
