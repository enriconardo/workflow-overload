#!/usr/bin/env bash
set -euo pipefail

# The rules every task command shares, printed into a skill as it loads:
# Claude Code lets a skill run a plugin's script, not read its files.

cat "$(dirname "${BASH_SOURCE[0]}")/../shared/rules.md"
