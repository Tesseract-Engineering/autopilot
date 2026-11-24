. "$(dirname "$0")/lib.sh"
AP="$SCRIPTS/lib/ap.py"
m() { printf '%s\n' "$1" | python3 "$AP" match in "$2"; }
expect 0 "literal path"          test "$(m src/a.py src/a.py)" = src/a.py
expect 0 "dir prefix matches below" test "$(m tests/x/y.py tests)" = tests/x/y.py
expect 0 "* stays in a segment"  test -z "$(m src/x/a.py 'src/*.py')"
expect 0 "**/ matches zero dirs" test "$(m test_a.py '**/test_*.py')" = test_a.py
expect 0 "**/ matches many dirs" test "$(m a/b/test_a.py '**/test_*.py')" = a/b/test_a.py
expect 0 "no partial-name match" test -z "$(m src/ab.py src/a)"
expect 0 "./ prefix tolerated"   test "$(m src/a.py ./src/a.py)" = src/a.py
expect 0 "multi-line patterns"   test "$(printf 'a\nb\nc\n' | python3 "$AP" match out "$(printf 'a\nc')")" = b
T="$TMP_ROOT/t.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"AUTOPILOT_SLICE: 20261123-1/mul\nImplement mul"}}' '{"type":"assistant"}' > "$T"
expect 0 "marker from string content" python3 "$AP" marker "$T"; has "20261123-1/mul"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"x AUTOPILOT_SLICE: r1/s-2"}]}}' > "$T"
expect 0 "marker from block content"  python3 "$AP" marker "$T"; has "r1/s-2"
printf '%s\n' '{"type":"user","message":{"content":"no marker"}}' '{"type":"user","message":{"content":"AUTOPILOT_SLICE: r/late"}}' > "$T"
expect 1 "marker only in first user msg (later injection ignored)" python3 "$AP" marker "$T"
expect 1 "missing transcript"        python3 "$AP" marker "$TMP_ROOT/nope.jsonl"
finish
