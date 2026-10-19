#!/usr/bin/env python3
"""AgriSentry AI — translation completeness validator (audit Phase 22).

Scans lib/ for user-visible strings:
  1. Every literal passed through tr('...') / trLevel('...') / trDisease('...').
  2. Every English sentence in the generated-text layer (lib/ai, lib/utils,
     lib/services/mock_data.dart) — these are rendered via tr() at runtime.
and verifies each has an exact key in BOTH the Hindi (_hi) and Telugu (_te)
dictionaries in lib/services/translations.dart.

Usage:
  python tool/check_translations.py            # report
Exit code 1 when keys are missing (CI-friendly).
"""
import re
import sys
from pathlib import Path

MOBILE = Path(__file__).resolve().parents[1]
LIB = MOBILE / "lib"
TRANS = LIB / "services" / "translations.dart"

# Text layer files whose string literals are rendered through tr() at runtime.
TEXT_LAYER_DIRS = [LIB / "ai", LIB / "utils"]
TEXT_LAYER_FILES = [LIB / "services" / "mock_data.dart"]


def extract_dict_keys(src: str, name: str) -> set[str]:
    """Keys of `const Map<String, String> <name> = { ... }` (single-line keys)."""
    m = re.search(r"Map<String, String>\s+" + name + r"\s*=\s*\{", src)
    if not m:
        return set()
    i, depth, j = m.end(), 1, m.end()
    while depth and j < len(src):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
        j += 1
    body = src[i : j - 1]
    return set(re.findall(r"'((?:[^'\\]|\\.)*)'\s*:", body))


ADJACENT = re.compile(
    r"'((?:[^'\\\n]|\\.)*)'(?:\s*'((?:[^'\\\n]|\\.)*)')*"
)


def dart_strings(text: str) -> list[str]:
    """All single-quoted Dart string literals, joining adjacent literals that
    Dart concatenates across lines (a common style for long sentences)."""
    text = text.replace("\r\n", "\n")
    out: list[str] = []
    for m in ADJACENT.finditer(text):
        parts = re.findall(r"'((?:[^'\\\n]|\\.)*)'", m.group(0))
        out.append("".join(parts))
    return out


def is_identifier(s: str) -> bool:
    """Route/asset/technical tokens that are never user-visible prose."""
    return bool(re.fullmatch(r"[a-z0-9_./\-]+", s)) or " " not in s


def main() -> int:
    src = TRANS.read_text(encoding="utf-8")
    hi = extract_dict_keys(src, "_hi")
    te = extract_dict_keys(src, "_te")
    hi_dis = extract_dict_keys(src, "_hiDiseases")
    te_dis = extract_dict_keys(src, "_teDiseases")
    hi_lvl = extract_dict_keys(src, "_hiLevels")
    te_lvl = extract_dict_keys(src, "_teLevels")

    missing_hi: set[str] = set()
    missing_te: set[str] = set()

    def check(key: str) -> None:
        if key in hi and key in te:
            return
        if key in hi_dis and key in te_dis:  # disease names use trDisease maps
            return
        if key in hi_lvl and key in te_lvl:  # levels use trLevel maps
            return
        if key not in hi:
            missing_hi.add(key)
        if key not in te:
            missing_te.add(key)

    dynamic_templates: list[str] = []

    # 1. Direct tr()/trLevel()/trDisease() call sites across all screens/widgets.
    for f in LIB.rglob("*.dart"):
        if f == TRANS:
            continue
        body = f.read_text(encoding="utf-8").replace("\r\n", "\n")
        for m in re.finditer(
                r"\b(?:tr|trLevel|trDisease)\(\s*'((?:[^'\\\n]|\\.)*)'", body):
            joined = "".join(
                re.findall(r"'((?:[^'\\\n]|\\.)*)'",
                           body[m.start():m.end() + 400].split(")")[0]))
            s = joined or m.group(1)
            if "$" in s:  # interpolated at runtime -> exact-match dict cannot hit
                dynamic_templates.append(s.strip())
                continue
            check(s)

    # 2. Generated-text layer: every prose string is rendered via tr() somewhere.
    prose_files = list(TEXT_LAYER_DIRS and [p for d in TEXT_LAYER_DIRS for p in d.rglob("*.dart")]) + list(TEXT_LAYER_FILES)
    for f in prose_files:
        for s in dart_strings(f.read_text(encoding="utf-8")):
            if len(s) < 3 or is_identifier(s):
                continue
            if not re.search(r"[a-zA-Z]", s):
                continue
            if "$" in s:  # interpolated template string, not a static key
                continue
            check(s)

    # 3. Disease/level map coverage must be symmetric across languages.
    for label, a, b in (
        ("_hiDiseases/_teDiseases", hi_dis, te_dis),
        ("_hiLevels/_teLevels", hi_lvl, te_lvl),
    ):
        only_a, only_b = a - b, b - a
        for k in only_a:
            print(f"MISSING (Telugu)  {label}: {k}")
        for k in only_b:
            print(f"MISSING (Hindi)   {label}: {k}")

    if dynamic_templates and "--templates" in sys.argv:
        print(f"\nDynamic tr() templates (runtime interpolation; rely on "
              f"sentence templates, not exact keys) - {len(dynamic_templates)}:")
        for t in sorted(set(dynamic_templates)):
            print(f"  TEMPLATE: {t}")

    for k in sorted(missing_hi):
        print(f"MISSING (Hindi)   tr key: {k}")
    for k in sorted(missing_te):
        print(f"MISSING (Telugu)  tr key: {k}")

    total = len(missing_hi) + len(missing_te)
    print(f"\n{total} missing entr{'y' if total == 1 else 'ies'} "
          f"(Hindi: {len(missing_hi)}, Telugu: {len(missing_te)})")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
