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

When the change proves to be L by step 4 of `phases/brainstorm.md`, at any step of this path or of the close, stop and tell the human why: the tier is theirs. On their go, the attempt's code goes and the task starts again from main, as L: its code did not go through the L path's tests first, and the spec must come from the problem, not from a sketched solution.

1. Log what the attempt found that the spec needs, a fact per line (`journal.sh log "found: <fact>"`): facts about the code and the problem, not the attempt's code.
2. `bash <scripts>/restart.sh "<reason>"`. It recreates the branch from main and keeps the journal, as tier L in phase `l/spec`, without its open findings, and the inputs; the uncommitted work goes to a stash. It prints what it discarded, for the human: do not read the attempt's commits or stash.
3. Go on with `phases/l-plan.md` from 1; it runs the explorer when the brainstorming logged no map.
