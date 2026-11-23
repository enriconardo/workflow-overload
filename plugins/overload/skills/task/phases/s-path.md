# S path

For small changes: no spec, one reviewer, one checkpoint. The journal's *Intent* stands in for the spec and goes in the commit's body.

## 1. Implement — phase `s/implement`

Write the change, following the project's rules. A change of behavior updates the docs that describe it in the same commit. A bug fix starts with a test that reproduces the bug and fails with its symptom; run it red before the fix.

## 2. Verify

`bash <scripts>/verify.sh`. Red: fix and run it again. The script counts the reds in a row; at the third it says to stop, and you go to `shared/escalate.md` (no *skip* on a red verify).

## 3. Commit

Write the message to a file outside the repository: a subject as *Names and messages* in the rules of every task says, then a body with the intent (why the change, what it decides). `bash <scripts>/commit.sh <message-file>`. It refuses a tree that is not the verified one: verify again after any change. It moves the phase to `close/check`, unless the commit changes only the config.

## 4. Close

Go on with `shared/close.md`. On the S path you are the one who fixes what the review finds.

## Turning L

When the change proves to be L by step 4 of `phases/brainstorm.md`, at any step of this path or of the close, stop and tell the human why: the tier is theirs. On their go:

1. Put the uncommitted work in a stash (`git stash push -u -m "S work" -- <paths>`: stash paths, so the journal stays out of it) and log it. The commits stay.
2. `journal.sh set tier L`, `journal.sh log "tier L: <reason>"`, `journal.sh set phase l/spec`.
3. Go on with `phases/l-plan.md` from 1; it runs the explorer when the brainstorming logged no map. The spec describes the whole change and names the commits already made; its chunks cover only what is left, for the build. You may read the stash while you write it. The commits reach main with the spec, after the whole close.
