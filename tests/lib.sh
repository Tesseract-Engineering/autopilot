# shellcheck shell=bash
# Tiny test harness for autopilot's scripts. No bats needed.
#   expect CODE "description" cmd args...   run cmd, compare exit code; output in $OUT
#   has "needle"                            assert $OUT contains needle
#   lacks "needle"                          assert $OUT does not contain needle
#   new_repo                                fresh fixture repo; cd into it
# Fixture: a shell "project" whose tests are tests/test_*.sh, run by .claude/checks.sh.

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/autopilot/scripts" && pwd)"
PASS=0; FAILS=0; OUT=""; LAST=""

expect() {
  local want="$1" desc="$2"; shift 2
  LAST="$desc"
  OUT="$("$@" 2>&1)"; local got=$?
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$desc"
  else FAILS=$((FAILS+1)); printf '  FAIL %s (exit %s, want %s)\n' "$desc" "$got" "$want"; printf '%s\n' "$OUT" | sed 's/^/       | /'; fi
}
has() {
  case "$OUT" in *"$1"*) PASS=$((PASS+1)) ;;
  *) FAILS=$((FAILS+1)); printf '  FAIL %s: output lacks "%s"\n' "$LAST" "$1"; printf '%s\n' "$OUT" | sed 's/^/       | /' ;; esac
}
lacks() {
  case "$OUT" in *"$1"*) FAILS=$((FAILS+1)); printf '  FAIL %s: output has "%s"\n' "$LAST" "$1" ;;
  *) PASS=$((PASS+1)) ;; esac
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/autopilot-test.XXXXXX")"
cleanup() { [ -n "${TMP_ROOT:-}" ] && rm -rf "${TMP_ROOT:?}"; }
trap cleanup EXIT

new_repo() {
  REPO="$(mktemp -d "$TMP_ROOT/repo.XXXXXX")"
  cd "$REPO" || exit 1
  git init -q -b main .
  git config user.email t@example.com; git config user.name test
  mkdir -p src tests migrations .claude .autopilot
  printf 'add() { echo $(( $1 + $2 )); }\nmul() { echo $(( $1 * $2 )); }\n' > src/math.sh
  printf 'greet() { echo "hi $1"; }\n' > src/greet.sh
  printf '. src/math.sh\n[ "$(add 1 2)" = 3 ] || { echo "add 1 2 != 3"; exit 1; }\n' > tests/test_add.sh
  echo 'CREATE TABLE t (id int);' > migrations/001.sql
  cat > .claude/checks.sh <<'EOF'
#!/usr/bin/env bash
for t in tests/test_*.sh; do sh "$t" || { rc=$?; echo "FAILED: $t"; exit $rc; }; done
echo "all tests passed"
EOF
  chmod +x .claude/checks.sh
  cat > .autopilot/config.json <<'EOF'
{ "test_globs": ["tests/**"], "protected_paths": ["migrations/**"], "max_attempts": 3,
  "require_plan_approval": true, "test_cmd": "./.claude/checks.sh",
  "repro_cmd": "sh {test}", "repro_fail_codes": [1] }
EOF
  printf '.autopilot/runs/\n.autopilot/worktrees/\n' > .gitignore
  git add -A && git commit -q -m init
}

# start_run PATTERN SLICES_JSON -> sets RUN
start_run() {
  RUN="$("$SCRIPTS/run.sh" start "$1" "test task")" || { echo "start_run failed: $RUN"; exit 1; }
  printf '%s\n' "$2" > ".autopilot/runs/$RUN/slices.json"
}

finish() {
  echo "  -- $PASS passed, $FAILS failed"
  [ "$FAILS" -eq 0 ]
}
