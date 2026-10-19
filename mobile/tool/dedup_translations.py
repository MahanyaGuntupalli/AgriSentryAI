#!/usr/bin/env python3
"""One-shot dedup for translations.dart constant maps.

Keeps the FIRST occurrence of each key inside _hi and _te (later occurrences
are the audit additions); removes later duplicate keys.
"""
import re
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib" / "services" / "translations.dart"
src = p.read_text(encoding="utf-8").replace("\r\n", "\n")
lines = src.split("\n")

KEY = re.compile(r"\s*'((?:[^'\\]|\\.)*)'\s*:")


def map_bounds(name: str) -> tuple[int, int]:
    m = re.search(r"Map<String, String>\s+" + name + r"\s*=\s*\{", src)
    i, depth, j = m.end(), 1, m.end()
    while depth and j < len(src):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
        j += 1
    return src[: m.end()].count("\n"), src[: j - 1].count("\n")


def dup_keys(name: str) -> dict[str, list[int]]:
    s, e = map_bounds(name)
    keys: dict[str, list[int]] = {}
    for idx in range(s, e + 1):
        m = KEY.match(lines[idx])
        if m:
            keys.setdefault(m.group(1), []).append(idx)
    return {k: v for k, v in keys.items() if len(v) > 1}


to_drop: set[int] = set()
for name in ("_hi", "_te"):
    for k, ln in dup_keys(name).items():
        for l in ln[1:]:  # keep first occurrence
            to_drop.add(l)
            print(f"{name} dup @ line {l + 1}: {k[:60]}")

out = [l for i, l in enumerate(lines) if i not in to_drop]
p.write_text("\n".join(out), encoding="utf-8")
print(f"removed {len(to_drop)} duplicate lines")
