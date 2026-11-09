#!/usr/bin/env bash
set -uo pipefail

# What the /overload skill reads before it decides what to do: the config,
# the branch, the journal's header and whether the tree is verified. Never
# fails, so that the skill always loads.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "- repository: none (not inside a git work tree)"
  exit 0
}
cd "$root" || exit 0

echo "- scripts: $OVERLOAD_SCRIPTS"
echo "- branch: $(current_branch || echo '(detached)')"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "- config: none ($CONFIG_FILE is missing)"
else
  version="$(cfg version)"
  if [[ "$version" != "$CONFIG_VERSION" ]]; then
    echo "- config: version '$version', this plugin reads $CONFIG_VERSION"
  else
    echo "- config:"
    for key in main exec verify test_files branch types commit commit_types subject_max integrate rules backlog specs tests_glob red_types reference probe_env; do
      printf '  - %s = %s\n' "$key" "$(cfg "$key")"
    done
    for key in exec verify; do
      var="OVERLOAD_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
      [[ -n "${!var+x}" ]] && echo "  - ($key comes from \$$var)"
    done
  fi
fi
if [[ -f "$JOURNAL_FILE" ]]; then
  echo "- journal: $JOURNAL_FILE"
  sed -n '/^## /q; /^[a-z_]*: /s/^/  - /p' "$JOURNAL_FILE"
  if is_verified 2>/dev/null; then
    echo "- working tree: verified"
  else
    echo "- working tree: not verified since its last change"
  fi
else
  echo "- journal: none on this branch"
fi
dirty="$(git status --porcelain | head -n 10)"
if [[ -n "$dirty" ]]; then
  echo "- uncommitted changes:"
  printf '%s\n' "$dirty" | sed 's/^/  /'
fi
exit 0
