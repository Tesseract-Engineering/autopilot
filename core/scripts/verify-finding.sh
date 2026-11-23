#!/usr/bin/env bash
# verify-finding.sh RUN FINDING.json [TREE]
# A reviewer finding counts only if its repro test fails. FINDING.json:
#   {"id":"f1","title":"...","test_path":"tests/test_x.py","test_code":"..."}
# The repro is written to test_path (must match test_globs and not exist yet) and
# run with repro_cmd ("{test}" = test_path). KEPT (exit 0) iff the exit code is in
# repro_fail_codes: the test stays and joins the suite. Otherwise DISCARDED
# (exit 1) and the file is removed. The reviewer supplies test code only, never a
# command. Result: runs/<run>/findings/<id>.result (+ <id>.log)
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
[ $# -ge 2 ] || ap_die "usage: verify-finding.sh RUN FINDING.json [TREE]"
run="$1"; f="$2"; need_run "$run"
tree="${3:-$AP_MAIN}"
out_dir="$(run_dir "$run")/findings"; mkdir -p "$out_dir"
id="$(jq -r '.id // empty' "$f" 2>/dev/null)"
[ -n "$id" ] || ap_die "finding has no id (or is not JSON): $f"
res="$out_dir/$id.result"
verdict() { # verdict KEPT|DISCARDED REASON
  printf '%s: %s\n' "$1" "$2" | tee "$res"
  [ "$1" = KEPT ] && exit 0
  exit 1
}
path="$(jq -r '.test_path // empty' "$f")"
code_txt="$(jq -r '.test_code // empty' "$f")"
{ [ -n "$path" ] && [ -n "$code_txt" ]; } || verdict DISCARDED "$id has no repro test (test_path + test_code required)"
case "$path" in /*|*..*) verdict DISCARDED "$id test_path must be relative inside the repo" ;; esac
[ -n "$(printf '%s\n' "$path" | ap_match in "$(cfg_list test_globs)")" ] \
  || verdict DISCARDED "$id test_path $path does not match test_globs"
[ -e "$tree/$path" ] && verdict DISCARDED "$id test_path $path already exists; repro must be a new file"

mkdir -p "$tree/$(dirname "$path")"
printf '%s\n' "$code_txt" > "$tree/$path"
repro_cmd="$(cfg repro_cmd 'python -m pytest -q {test}')"
cmd="${repro_cmd//\{test\}/$path}"
out="$(cd "$tree" && bash -c "$cmd" 2>&1)"; rc=$?
printf '$ %s\n%s\n' "$cmd" "$out" > "$out_dir/$id.log"
case " $(cfg repro_fail_codes 1) " in
  *" $rc "*) verdict KEPT "$id repro fails as claimed (exit $rc); $path added to the suite" ;;
esac
rm -f "${tree:?}/${path:?}"
if [ "$rc" -eq 0 ]; then verdict DISCARDED "$id repro passes (exit 0); no bug demonstrated"; fi
verdict DISCARDED "$id repro errored (exit $rc), not an assertion failure; see $out_dir/$id.log"
