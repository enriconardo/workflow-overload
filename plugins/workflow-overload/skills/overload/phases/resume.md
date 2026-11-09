# Resume

A session interrupted, or restarted with `/clear`, resumes from the journal.

1. Read `.workflow/journal.md` in full: the intent, the open findings and the candidates are what the previous session knew.
2. Look at the branch: `git log --oneline <base>..HEAD` and `git status --short`.
3. Go to the phase the journal gives:
   - `s/implement`: `phases/s-path.md`; with uncommitted changes, read them, finish the change and verify again.
   - `l/spec`, `l/probe`, `l/spec-review`, `l/split`, `l/checkpoint`: that step of `phases/l-plan.md`; the spec on disk is where the last session left it.
   - `l/chunk-<n>/<step>`: `phases/l-chunk.md`, from the first chunk the spec does not tick. A chunk interrupted with uncommitted work: put that work in a stash named after the chunk (`git stash push -u -m "chunk <n>"`, the journal stays out of it if you stash paths), log it, and restart the chunk from its tests, or from its implementation when it is not test-first. Its earlier suite records stay; the test-author records again.
   - `close/review`: `phases/close.md`, a new round on `<sha>..HEAD`, `sha` being the HEAD the last logged round reviewed, or the whole range if none was logged.
   - `close/lessons`, `close/checkpoint`, `close/write`, `close/integrate`: that step of `phases/close.md`, from its start. A checkpoint is shown again: the human's previous answer is in the log if they gave one.
4. Tell the human in one line where the task stands and what you do next.
