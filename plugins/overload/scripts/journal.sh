#!/usr/bin/env bash
set -euo pipefail

# The task's journal, .workflow/journal.md on the task's branch: the phase,
# the intent and what the checkpoints need. The main agent changes its header
# through this script, its sections with Edit.
#
#   journal.sh get <key>            a header value (phase, tier, ...)
#   journal.sh set <key> <value>    sets a header value
#   journal.sh inc <key>            adds 1 to a counter of the header
#   journal.sh log <text>           appends a timestamped line to *Log*
#   journal.sh keep <name> <file>   copies a file a later session reads (the
#                                   explorer's map) to the state folder,
#                                   which outlives the session, unlike a
#                                   scratchpad, and logs its path
#   journal.sh show                 the whole journal

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project

usage() {
  echo "Usage: journal.sh get <key> | set <key> <value> | inc <key> | log <text> | keep <name> <file> | show" >&2
  exit 2
}

[[ -f "$JOURNAL_FILE" ]] || die "no $JOURNAL_FILE on '$(current_branch)'."

valid_key() {
  [[ "$1" =~ ^[a-z_]+$ ]] || die "'$1' is not a header key (lowercase letters and _)."
}

set_value() {
  local key="$1" value="$2" tmp
  valid_key "$key"
  [[ "$value" != *$'\n'* ]] || die "a header value is one line."
  tmp="$(mktemp)"
  if grep -q "^$key:" "$JOURNAL_FILE"; then
    KEY="$key" VALUE="$value" awk '
      !done && index($0, ENVIRON["KEY"] ":") == 1 { print ENVIRON["KEY"] ": " ENVIRON["VALUE"]; done = 1; next }
      { print }' "$JOURNAL_FILE" >"$tmp"
  else
    # A new key goes at the end of the header, before the first section.
    KEY="$key" VALUE="$value" awk '
      !done && /^## / { print ENVIRON["KEY"] ": " ENVIRON["VALUE"]; print ""; done = 1 }
      { print }
      END { if (!done) print ENVIRON["KEY"] ": " ENVIRON["VALUE"] }' "$JOURNAL_FILE" >"$tmp"
  fi
  mv "$tmp" "$JOURNAL_FILE"
}

case "${1:-}" in
  get)
    (($# == 2)) || usage
    journal_get "$2"
    ;;
  set)
    (($# == 3)) || usage
    set_value "$2" "$3"
    ;;
  inc)
    (($# == 2)) || usage
    current="$(journal_get "$2")"
    [[ -z "$current" || "$current" =~ ^[0-9]+$ ]] || die "'$2' is '$current', not a counter."
    set_value "$2" "$((${current:-0} + 1))"
    journal_get "$2"
    ;;
  log)
    (($# >= 2)) || usage
    shift
    grep -q '^## Log' "$JOURNAL_FILE" || printf '\n## Log\n\n' >>"$JOURNAL_FILE"
    printf -- '- %s %s\n' "$(now)" "$*" >>"$JOURNAL_FILE"
    ;;
  keep)
    (($# == 3)) || usage
    [[ "$2" =~ ^[a-z][a-z0-9-]*$ ]] || die "'$2' is not a name for a kept file (lowercase letters, digits and -)."
    [[ -f "$3" ]] || die "'$3' is not a file."
    kept="$(state_dir)/kept"
    mkdir -p "$kept"
    cp -- "$3" "$kept/$2.md"
    printf -- '- %s %s: %s\n' "$(now)" "$2" "$kept/$2.md" >>"$JOURNAL_FILE"
    echo "kept as $kept/$2.md, logged in the journal as '$2'"
    ;;
  show)
    cat "$JOURNAL_FILE"
    ;;
  *) usage ;;
esac
