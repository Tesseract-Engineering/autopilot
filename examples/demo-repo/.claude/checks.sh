#!/usr/bin/env bash
# Repo checks for autopilot's gate. Exit 0 = pass. Keep it fast and deterministic.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
python3 -m pytest -q -p no:cacheprovider
