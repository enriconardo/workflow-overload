# Resume

A session interrupted, or restarted with `/clear`, resumes from the journal.

1. Read `.workflow/journal.md` in full: the intent, the open findings and the candidates are what the previous session knew.
2. Look at the branch: `git log --oneline <base>..HEAD` and `git status --short`.
3. Go to the phase the journal gives, in `phases/s-path.md`:
   - `s/implement` with uncommitted changes: read them, finish the change, and verify again from step 2; a change with no commit yet is whatever the working tree holds.
   - `s/review`: a new review round on `<sha>..HEAD`, where `sha` is the HEAD the last logged round reviewed, or the whole range if none was logged.
   - `s/lessons`, `s/checkpoint`, `s/close`, `s/integrate`: that step, from its start. A checkpoint is shown again: the human's previous answer is in the log if they gave one.
4. Tell the human in one line where the task stands and what you do next.
