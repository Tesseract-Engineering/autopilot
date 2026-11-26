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
