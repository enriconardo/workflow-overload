# S path

For small changes: no spec, one reviewer, one checkpoint. The journal's *Intent* stands in for the spec and goes in the commit's body.

## 1. Implement — phase `s/implement`

Write the change, following the project's rules. A bug fix starts with a test that reproduces the bug and fails with its symptom; run it red before the fix. A task that works an item of the backlog removes the item in a commit of its own; the backlog file stays, even empty.

## 2. Verify

`bash <scripts>/verify.sh`. Red: fix and run it again. The script counts the reds in a row; at the third it says to stop, and you go to `phases/escalate.md` (no *skip* on a red verify).

## 3. Commit

Write the message to a file outside the repository: a subject as *Names and messages* in the skill's rules says, then a body with the intent (why the change, what it decides). `bash <scripts>/commit.sh <message-file>`. It refuses a tree that is not the verified one: verify again after any change.

## 4. Close

Go on with `phases/close.md`. On the S path you are the one who fixes what the review finds.
