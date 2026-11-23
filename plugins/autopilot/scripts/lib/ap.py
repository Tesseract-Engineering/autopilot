#!/usr/bin/env python3
"""Small stdlib helpers for autopilot's bash scripts.

  ap.py match in|out PATTERN...   read paths on stdin; print those that match any
                                  pattern (in) or match none (out)
  ap.py marker TRANSCRIPT         print "<run>/<slice>" from the AUTOPILOT_SLICE
                                  line in the first user message of a JSONL transcript
  ap.py relpath ABS_PATH          print ABS_PATH relative to its git work tree root

Glob rules: '*' and '?' don't cross '/'; '**' crosses any number of directories;
a pattern also matches everything under it ('tests' matches 'tests/a.py').
"""
import json
import os
import re
import sys


def glob_rx(pattern):
    p = pattern.strip()
    if p.startswith("./"):
        p = p[2:]
    p = p.rstrip("/")
    out, i = "", 0
    while i < len(p):
        if p.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif p.startswith("**", i):
            out += ".*"
            i += 2
        elif p[i] == "*":
            out += "[^/]*"
            i += 1
        elif p[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(p[i])
            i += 1
    return re.compile(out + r"(?:/.*)?\Z")


def cmd_match(mode, patterns):
    # each argument may hold several newline-separated patterns
    rxs = [glob_rx(p) for a in patterns for p in a.splitlines() if p.strip()]
    for line in sys.stdin:
        path = line.rstrip("\n")
        if not path:
            continue
        hit = any(r.match(path) for r in rxs)
        if hit == (mode == "in"):
            print(path)
    return 0


MARKER = re.compile(r"AUTOPILOT_SLICE:\s*([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)")


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            c.get("text", "") for c in content if isinstance(c, dict)
        )
    return ""


def cmd_marker(path):
    try:
        with open(path) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if entry.get("type") != "user":
                    continue
                m = MARKER.search(text_of((entry.get("message") or {}).get("content")))
                if m:
                    print(f"{m.group(1)}/{m.group(2)}")
                    return 0
                return 1  # first user message has no marker
    except OSError as e:
        print(f"cannot read transcript: {e}", file=sys.stderr)
    return 1


def cmd_relpath(path):
    path = os.path.abspath(path)
    d = os.path.dirname(path)
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            print(os.path.relpath(path, d))
            return 0
        parent = os.path.dirname(d)
        if parent == d:
            print(path)
            return 1
        d = parent


def main(argv):
    if len(argv) >= 2 and argv[0] == "match" and argv[1] in ("in", "out"):
        return cmd_match(argv[1], argv[2:])
    if len(argv) == 2 and argv[0] == "marker":
        return cmd_marker(argv[1])
    if len(argv) == 2 and argv[0] == "relpath":
        return cmd_relpath(argv[1])
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
