#!/usr/bin/env bash
# plan-check.sh RUN: validate slices.json.
#   - parses; .slices non-empty; ids unique and [a-z0-9-]+ (not "tests"/"integration")
#   - every slice has non-empty allowed_files and a goal
#   - no allowed file is a test path or a protected path
#   - pattern fan-out / best-of-n: allowed_files are literal paths (no globs);
#     fan-out slices are pairwise file-disjoint
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -eq 1 ] || ap_die "usage: plan-check.sh RUN"
run="$1"; need_run "$run"
f="$(run_dir "$run")/slices.json"
pattern="$(state_get "$run" pattern)"
errs=""
err() { errs="$errs  - $*"$'\n'; }

[ -f "$f" ] || { echo "plan-check: $f missing" >&2; exit 1; }
jq -e . "$f" >/dev/null 2>&1 || { echo "plan-check: slices.json is not valid JSON" >&2; exit 1; }
jq -e '.slices | type=="array" and length>0' "$f" >/dev/null || err "slices must be a non-empty array"

while IFS= read -r msg; do [ -n "$msg" ] && err "$msg"; done < <(jq -r '
  .slices[]? |
  (if (.id|type)!="string" or (.id|test("^[a-z0-9-]+$")|not) then "slice id \(.id|tojson) must match [a-z0-9-]+" else empty end),
  (if .id=="tests" or .id=="integration" then "slice id \(.id) is reserved" else empty end),
  (if (.goal // "")=="" then "slice \(.id): missing goal" else empty end),
  (if ((.allowed_files // [])|length)==0 then "slice \(.id): allowed_files is empty" else empty end)' "$f")

dups="$(jq -r '.slices[]?.id' "$f" | sort | uniq -d)"
[ -z "$dups" ] || err "duplicate slice ids: $dups"

all="$(jq -r '.slices[]?.allowed_files[]?' "$f")"
bad="$(printf '%s\n' "$all" | ap_match in "$(cfg_list test_globs)")"
[ -z "$bad" ] || err "allowed_files include test paths (tests belong to the test-writer): $(printf "%s\n" "$bad" | oneline)"
bad="$(printf '%s\n' "$all" | ap_match in "$(protected_patterns)")"
[ -z "$bad" ] || err "allowed_files include protected paths: $(printf "%s\n" "$bad" | oneline)"

case "$pattern" in fan-out|best-of-n)
  globs="$(printf '%s\n' "$all" | grep -E '[*?]' || true)"
  [ -z "$globs" ] || err "$pattern slices must list literal file paths, not globs: $(printf "%s\n" "$globs" | oneline)"
esac
if [ "$pattern" = fan-out ]; then
  shared="$(printf '%s\n' "$all" | sed 's#^\./##' | sort | uniq -d)"
  [ -z "$shared" ] || err "fan-out slices are not file-disjoint; shared: $(printf "%s\n" "$shared" | oneline). Use the default pattern."
fi

if [ -n "$errs" ]; then printf 'plan-check FAILED:\n%s' "$errs" >&2; exit 1; fi
echo "plan-check ok: $(jq '.slices|length' "$f") slice(s), pattern $pattern"
