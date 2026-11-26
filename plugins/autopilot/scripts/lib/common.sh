# shellcheck shell=bash
# Shared helpers for autopilot core scripts. Source it; don't run it.
# Exit-code convention for verdict scripts: 0 pass, 1 fail, 3 escalated, 64 usage.

AP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_SCRIPTS="$(dirname "$AP_LIB")"
. "$AP_LIB/platform.sh"

ap_die() { echo "autopilot: $*" >&2; exit 64; }

for _t in git jq python3; do
  command -v "$_t" >/dev/null 2>&1 || ap_die "missing required tool: $_t"
done

# The main checkout, even when called from inside a linked worktree.
# (.autopilot/runs is gitignored, so it only exists in the main checkout.)
ap_main_root() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || ap_die "not inside a git repository"
  dirname "$common"
}

AP_MAIN="${AP_MAIN:-$(ap_main_root)}"
AP_CONFIG="$AP_MAIN/.autopilot/config.json"
AP_RUNS="$AP_MAIN/.autopilot/runs"

# cfg KEY DEFAULT: scalar from config.json
cfg() {
  local v=""
  [ -f "$AP_CONFIG" ] && v="$(jq -r --arg k "$1" '.[$k] // empty | if type=="array" then join(" ") else tostring end' "$AP_CONFIG")"
  printf '%s\n' "${v:-$2}"
}
# cfg_list KEY: one array element per line
cfg_list() { [ -f "$AP_CONFIG" ] && jq -r --arg k "$1" '.[$k] // [] | .[]' "$AP_CONFIG"; return 0; }

# Paths no agent may change, whatever config.json says: the gate's own inputs.
AP_BUILTIN_PROTECTED='.claude/checks.sh
.claude/settings.json
.claude/settings.local.json
.autopilot/config.json'
protected_patterns() { printf '%s\n' "$AP_BUILTIN_PROTECTED"; cfg_list protected_paths; }

# Drop autopilot's own gitignored bookkeeping (run dirs, worktrees) from path lists.
ap_drop_bookkeeping() { sed -E '/^\.autopilot\/(runs|worktrees)\//d'; }

# ap_match in|out "PATTERNS" < paths   (PATTERNS: newline-separated, always quoted)
ap_match() { python3 "$AP_LIB/ap.py" match "$@"; }

run_dir() { printf '%s/%s\n' "$AP_RUNS" "$1"; }
slice_dir() { printf '%s/%s/slices/%s\n' "$AP_RUNS" "$1" "$2"; }
state_get() { jq -r --arg k "$2" '.[$k] // empty' "$(run_dir "$1")/state.json"; }
state_set() { # state_set RUN KEY VALUE
  local f tmp
  f="$(run_dir "$1")/state.json"; tmp="$f.tmp"
  jq --arg k "$2" --arg v "$3" '.[$k]=$v' "$f" > "$tmp" && mv "$tmp" "$f"
}
current_run() { [ -f "$AP_RUNS/current" ] && cat "$AP_RUNS/current"; }

# need_run RUN: the run must exist. From here on, config is read from the copy frozen
# at run start, so an agent editing .autopilot/config.json can't loosen its own gate.
need_run() {
  [ -f "$(run_dir "$1")/state.json" ] || ap_die "no such run: $1"
  [ -f "$(run_dir "$1")/config.json" ] && AP_CONFIG="$(run_dir "$1")/config.json"
  return 0
}

# The tree a slice is worked on: its worktree if it has one, else the main checkout.
slice_tree() {
  local wt
  wt="$(slice_dir "$1" "$2")/worktree"
  if [ -f "$wt" ]; then cat "$wt"; else printf '%s\n' "$AP_MAIN"; fi
}

# Allowed-file globs for a slice. "integration" = union of all slices.
slice_allowed() {
  local slices
  slices="$(run_dir "$1")/slices.json"
  [ -f "$slices" ] || ap_die "run $1 has no slices.json"
  if [ "$2" = "integration" ]; then
    jq -r '.slices[].allowed_files[]' "$slices"
  else
    jq -r --arg s "$2" '.slices[] | select(.id==$s) | .allowed_files[]' "$slices"
  fi
}

# Files changed in TREE relative to BASE (committed + staged + unstaged + untracked),
# ignoring autopilot's own bookkeeping.
changed_files() { # changed_files TREE BASE
  {
    git -C "$1" diff --name-only "$2"
    git -C "$1" ls-files --others --exclude-standard
  } | ap_drop_bookkeeping | sort -u
}

# "<git blob hash>  <path>" for every present file matching test_globs.
hash_tests() { # hash_tests TREE
  local tree="$1" f
  git -C "$tree" ls-files -co --exclude-standard | ap_drop_bookkeeping | sort -u \
    | ap_match in "$(cfg_list test_globs)" \
    | while IFS= read -r f; do
        [ -f "$tree/$f" ] && printf '%s  %s\n' "$(git -C "$tree" hash-object -- "$f")" "$f"
      done
  return 0
}

# Print a command's output trimmed for a hook message: first 30 + last 10 lines.
trim_output() {
  awk '{ l[NR]=$0 } END {
    if (NR <= 40) { for (i=1;i<=NR;i++) print l[i]; exit }
    for (i=1;i<=30;i++) print l[i]
    print "    ... (" NR-40 " lines omitted) ..."
    for (i=NR-9;i<=NR;i++) print l[i] }'
}
oneline() { paste -sd" " -; }
