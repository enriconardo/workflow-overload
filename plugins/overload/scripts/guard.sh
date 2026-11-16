#!/usr/bin/env bash
# PreToolUse hook on Bash: inside an /overload task, refuses a `git commit`
# or `git merge` typed directly, since commits go through commit.sh, on the
# tree verify checked, and merges through integrate.sh. Silent without a
# journal, and cheap: Python only runs when one exists.
journal="${CLAUDE_PROJECT_DIR:-$PWD}/.workflow/journal.md"
[[ -f "$journal" ]] || exit 0
input="$(cat)"
GUARD_INPUT="$input" python3 - <<'PY'
import json, os, re, sys
try:
    data = json.loads(os.environ.get("GUARD_INPUT") or "{}")
except json.JSONDecodeError:
    sys.exit(0)
command = str((data.get("tool_input") or {}).get("command", ""))
if re.search(r"\bgit\s+(-C\s+\S+\s+)?(commit|merge)(?![-\w])", command):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "An /overload task is open on this branch: commit with the plugin's commit.sh after a green verify.sh, and merge with integrate.sh after the human's go.",
    }}))
PY
exit 0
