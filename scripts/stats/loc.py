#!/usr/bin/env python3
# Claude Code
#
# Copyright (C) 2026 Yoann Padioleau
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public License
# (LGPL) as published by the Free Software Foundation; either version
# 2 of the License, or (at your option) any later version.
#
# Lines of OCaml across the project (.ml and .mli), and how much of
# the budget they are: the browser is to stay under 30,000 lines,
# comments and blank lines included, .mli files too, so that it stays
# small enough to read. The budget is what the browser is made of --
# languages/, libs/ and src/ -- and not its tests (every tests/
# directory), nor scripts/ (the tools round it), nor tools/ (the
# programs beside it: mini-node): a cap must never be a reason to
# write fewer tests.
#
# The opening comment of an .mli is the module's documentation, and
# where its history and references are told: counted in the budget,
# and said apart at the end, for the day the budget is of the code
# alone. In it, a paragraph that is around the module rather than the
# module's own (its history, how browsers do it today) has a tag
# before it (docs/tags.md: cs-history:, modern:, ...): counted by tag.
#
# Each line is counted once, as code (it has some code, maybe a
# comment too), comment (only a comment, or inside one) or blank.
# After elm-playground's scripts/stats/loc.py, whose counting it is.
#
# The files are git's (tracked, and new ones not ignored), so _build/
# and what dune generates (Site_pages.ml, Ua_sheet.ml) are not counted.
#
# Usage: scripts/stats/loc.py [-v]      (make loc, make loc-v)
#   -v: every library (languages/css/, src/layout/, ...) and its ten
#       largest files, rather than a line a top directory
#
# The lines come first, next to the name they count; files, .ml,
# .mli, code, comment and blank lines after the name.

import re
import subprocess
import sys
from collections import defaultdict

# ---------------------------------------------------------------------
# Counting the lines of a file
# ---------------------------------------------------------------------

CHAR = re.compile(r"'(\\[\\'\"ntbr ]|\\[0-9]{3}|\\x[0-9a-fA-F]{2}|[^\\'\n])'")
QUOTED = re.compile(r"\{([a-z_]*)\|")


def count(text):
    """(code, comment, blank) lines of an OCaml source: a small lexer
    for comments (nested, and with strings inside them), strings,
    quoted strings {id|...|id} and character literals ('"')."""
    code = comment = blank = 0
    has_code = has_comment = False
    depth = 0  # comments nesting
    close = None  # inside a string: what ends it
    i, n = 0, len(text)
    while i <= n:
        if i == n or text[i] == "\n":
            if has_code:
                code += 1
            elif has_comment or depth > 0:
                comment += 1
            elif i < n or (n > 0 and text[-1] != "\n"):
                blank += 1
            has_code = False
            has_comment = depth > 0
            i += 1
            continue
        c = text[i]
        if close is not None:
            if depth > 0:
                has_comment = True
            elif not c.isspace():
                has_code = True
            if close == '"' and c == "\\":
                # an escape, but not over the newline of a "...\
                # continued" string: the line must still be counted
                i += 1 if text.startswith("\\\n", i) else 2
                continue
            if text.startswith(close, i):
                i += len(close)
                close = None
                continue
            i += 1
            continue
        if text.startswith("(*", i):
            depth += 1
            has_comment = True
            i += 2
            continue
        if depth > 0 and text.startswith("*)", i):
            depth -= 1
            i += 2
            continue
        if depth > 0:
            if not c.isspace():
                has_comment = True
            if c == '"':
                close = '"'
            i += 1
            continue
        if not c.isspace():
            has_code = True
        if c == '"':
            close = '"'
            i += 1
            continue
        if c == "{":
            m = QUOTED.match(text, i)
            if m:
                close = "|" + m.group(1) + "}"
                i = m.end()
                continue
        if c == "'":
            m = CHAR.match(text, i)
            if m:
                i = m.end()
                continue
        i += 1
    return code, comment, blank


# ---------------------------------------------------------------------
# Grouping the files
# ---------------------------------------------------------------------

# what the budget counts, in the order printed; the rest is "tests"
# (wherever a tests/ directory is) or "other" (scripts/, tools/)
BUDGET = 30000
BROWSER = ["languages", "libs", "src"]


def classify(path):
    """(group, subgroup) of a file: tests wherever they are, the
    browser by its top directory, the subgroup the library under it
    (languages/css/, src/layout/)."""
    parts = path.split("/")
    if "tests" in parts[:-1]:
        return "tests", "/".join(parts[:2]) + "/"
    group = "browser" if parts[0] in BROWSER else "other"
    if len(parts) > 2:
        return group, parts[0] + "/" + parts[1] + "/"
    return group, parts[0] + "/" if len(parts) > 1 else "./"


def teaching(path, text):
    """The lines of an .mli's opening comment: the module's
    documentation, where the idea, its history and its references are
    told (0 for another file, or an .mli that starts otherwise). No
    tag marks them: the first comment of an interface is that."""
    if not path.endswith(".mli") or not text.lstrip().startswith("(*"):
        return 0
    depth, i = 0, text.index("(*")
    start = i
    while i < len(text):
        if text.startswith("(*", i):
            depth, i = depth + 1, i + 2
        elif text.startswith("*)", i):
            depth, i = depth - 1, i + 2
            if depth == 0:
                break
        else:
            i += 1
    return text.count("\n", start, i) + 1


# the theme tags of docs/tags.md: on a line of its own in a comment,
# before the paragraph it is about
TAGS = ["cs-history", "modern", "others", "evolution", "design",
        "terminology", "why-win", "comeback", "road-not-taken", "reframe",
        "wib", "why-study"]


def tagged(text):
    """{tag: lines} of the paragraphs under a tag: the tag's line and
    those after it, to the next blank line."""
    counts = defaultdict(int)
    current = None
    for line in text.splitlines():
        # a comment's lines may each start with " * "
        word = line.strip().lstrip("*").strip()
        if word.endswith(":") and word[:-1] in TAGS:
            current = word[:-1]
        elif not word or word == ")":
            current = None
        if current:
            counts[current] += 1
    return counts


def files():
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard",
         "--", "*.ml", "*.mli", "*.mll", "*.mly"],
        check=True, capture_output=True, text=True).stdout
    return [f for f in out.splitlines() if f]


# ---------------------------------------------------------------------
# Printing
# ---------------------------------------------------------------------

FIELDS = ["files", "ml", "mli", "code", "comment", "blank", "lines"]
# the lines first, right beside the name they count, the rest after it
REST = [f for f in FIELDS if f != "lines"]
WIDTH = 23  # of the name column


def row(name, s, indent=0):
    cells = "".join(f"{s[f]:>8,}" for f in REST)
    print(f"{s['lines']:>7,}  {' ' * indent}{name:<{WIDTH - indent}}{cells}")


def main():
    verbose = "-v" in sys.argv[1:]
    stats = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
    largest = []  # (lines, path), the browser's
    taught = 0  # the browser's .mli files' opening comments, in lines
    themes = defaultdict(int)  # of which under each tag of docs/tags.md
    for path in files():
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except FileNotFoundError:  # deleted, not yet staged
            continue
        code, comment, blank = count(text)
        group, sub = classify(path)
        s = stats[group][sub]
        s["files"] += 1
        s["mli" if path.endswith(".mli") else "ml"] += 1
        s["code"] += code
        s["comment"] += comment
        s["blank"] += blank
        s["lines"] += code + comment + blank
        if group == "browser":
            largest.append((code + comment + blank, path))
            taught += teaching(path, text)
            for t, n in tagged(text).items():
                themes[t] += n

    def total(subs):
        t = defaultdict(int)
        for s in subs:
            for f in FIELDS:
                t[f] += s[f]
        return t

    print(f"{'lines':>7}  {'':<{WIDTH}}" + "".join(f"{f:>8}" for f in REST))
    for group in ["browser", "tests", "other"]:
        subs = stats.get(group, {})
        if not subs:
            continue
        if group != "browser":
            print()
        row(group, total(subs.values()))
        if group == "browser":
            # its three parts, and with -v each library under them
            for top in BROWSER:
                mine = {k: s for k, s in subs.items()
                        if k.split("/")[0] == top}
                row(top + "/", total(mine.values()), 2)
                if verbose:
                    for sub in sorted(mine):
                        row(sub, mine[sub], 4)
        elif verbose:
            for sub in sorted(subs):
                row(sub, subs[sub], 2)

    if verbose:
        print("\nthe browser's largest files (700 lines is where to look"
              " for a split):")
        for lines, path in sorted(largest, reverse=True)[:10]:
            print(f"{lines:>7,}  {path}")

    used = total(stats.get("browser", {}).values())["lines"]
    print(f"\nbudget: {used:,} of {BUDGET:,} lines"
          f" ({100 * used / BUDGET:.0f}%), {BUDGET - used:,} left")
    print(f"  of which {taught:,} are the interfaces' opening comments"
          f" (the idea, the history, the references);"
          f" {used - taught:,} without them")
    if themes:
        print(f"  tagged (docs/tags.md): {sum(themes.values()):,} lines -- "
              + ", ".join(f"{t} {themes[t]:,}" for t in TAGS if themes[t]))


if __name__ == "__main__":
    main()
