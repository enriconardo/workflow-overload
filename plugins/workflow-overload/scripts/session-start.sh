#!/usr/bin/env bash
# SessionStart hook: on a branch with an /overload task, a new or cleared
# session learns that the task waits for /overload, and a compacted one that
# it must reread the journal. Silent everywhere else, and on a resumed
# session, which already holds the task.
journal="${CLAUDE_PROJECT_DIR:-$PWD}/.workflow/journal.md"
[[ -f "$journal" ]] || exit 0
source="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("source", ""))
except Exception: print("")' 2>/dev/null)"
phase="$(sed -n 's/^phase: *//p' "$journal" | head -n 1)"
branch="$(sed -n 's/^branch: *//p' "$journal" | head -n 1)"
case "$source" in
  resume) ;;
  compact)
    echo "This session runs the Workflow Overload task $branch, phase ${phase:-unknown}. The summary above may have lost its rules: reread .workflow/journal.md and the phase's file before the next step."
    ;;
  *)
    echo "This branch holds an open Workflow Overload task ($branch, phase ${phase:-unknown}). It continues only when the user types /overload; until then, work as asked and do not commit or merge on this branch."
    ;;
esac
exit 0
