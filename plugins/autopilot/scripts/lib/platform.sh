# shellcheck shell=bash
# Sourced first by common.sh, the hook shims and the tests. Keeps the scripts' text
# output LF-only on Windows (Git Bash, MSYS2, Cygwin), where native jq.exe and
# python.exe write CRLF to pipes. A "\r" left on a value breaks every comparison
# and path the scripts build from it ("plan\r" is not "plan").
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    jq() { command jq -b "$@"; }          # -b: binary output, no LF -> CRLF
    export PYTHONIOENCODING=utf-8         # transcripts and file names aren't cp1252
    ;;
esac

# The checkout autopilot works in: the one holding .autopilot/config.json and the run dirs.
# That is the current work tree, which may itself be a linked worktree of another clone, except
# inside one of autopilot's own slice worktrees (.autopilot/worktrees/<run>/<slice>), where it is
# the checkout that made them. (Git's common dir would name the clone's main checkout instead,
# which can be on another branch, with another config, or none.)
ap_checkout_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  case "$top" in */.autopilot/worktrees/*) top="${top%%/.autopilot/worktrees/*}" ;; esac
  printf '%s\n' "$top"
}
