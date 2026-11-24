# Resume

A session interrupted, or restarted with `/clear`, resumes from the journal, under the command its `command` names: each skill's *Where to start* sends here only its own tasks.

1. Read `.workflow/journal.md` in full: the intent, the open findings and the candidates are what the previous session knew.
2. Look at the branch: `git log --oneline <base>..HEAD` and `git status --short`.
3. Go to the phase the journal gives:
   - `s/implement`: `phases/s-path.md`; with uncommitted changes, read them, finish the change and verify again.
   - `l/spec`, `l/probe`, `l/spec-review`, `l/split`, `l/lessons`, `l/checkpoint`: that step of `phases/l-plan.md`; the spec on disk is where the last session left it.
   - `p/plan`, `p/review`, `p/lessons`, `p/checkpoint`: that step of `phases/plan.md`, with the differences of *A revision* in `phases/change.md` when the journal names a `change`; the plan on disk is where the last session left it.
   - `d/drop`, `d/lessons`, `d/checkpoint`: that step of *A drop* in `phases/change.md`.
   - `a/run`: `phases/acceptance.md`; the log's `acceptance step` lines hold the outcomes so far, and an uncommitted change is a fix under way: finish it and verify. Ask the human whether to run the remaining steps, or every step again when the code changed since.
   - `l/expiry`: *Expiry* in `phases/l-chunk.md`, from the first step the log does not show done.
   - `l/chunk-<n>/<step>`: `phases/l-chunk.md`, from the first chunk the spec does not tick. A change to the spec left uncommitted is a correction under way (`git diff HEAD -- <spec>`): take it up first, from its step in *A spec correction*. A chunk interrupted with uncommitted work: put that work in a stash named after the chunk (`git stash push -u -m "chunk <n>" -- <paths>`: stash paths, so that the journal and the spec stay out of it), log it, and restart the chunk from its first step, which the status lists: set the phase to it. Its earlier suite records stay; the test-author records again.
   - `close/check`: `shared/close.md` from 1.
   - `close/review`: `shared/close.md`, a new round on `<sha>..HEAD`, `sha` being the HEAD the last logged round reviewed, or the whole range if none was logged.
   - `close/lessons`, `close/checkpoint`, `close/write`, `close/integrate`: that step of `shared/close.md`, from its start. A checkpoint is shown again: the human's previous answer is in the log if they gave one.
4. Tell the human in one line where the task stands and what you do next.
