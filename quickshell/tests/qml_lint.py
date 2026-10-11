#!/usr/bin/env python3
"""Structural lint for every QML file: after stripping comments and string
literals, braces/parens/brackets must balance and files must be non-empty.
"""
import sys
import pathlib

EXPECTED = (0, 0, 0)


def strip(src: str) -> str:
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            i = src.find("*/", i + 2)
            i = n if i == -1 else i + 2
        elif c in "\"'":
            quote = c
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            out.append("''")
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main(root: str) -> int:
    root = pathlib.Path(root)
    failed = False
    for qml in sorted(root.rglob("*.qml")):
        rel = str(qml.relative_to(root))
        src = qml.read_text(encoding="utf-8")
        if not src.strip():
            print(f"FAIL {rel}: empty file")
            failed = True
            continue
        code = strip(src)
        deltas = (code.count("{") - code.count("}"),
                  code.count("(") - code.count(")"),
                  code.count("[") - code.count("]"))
        if deltas != EXPECTED:
            print(f"FAIL {rel}: unbalanced {deltas}")
            failed = True
        else:
            print(f"ok   {rel}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
