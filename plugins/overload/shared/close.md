# Close

Every task ends here: an S task, the spec task of an L, a build: the slow tests, one final review, one round of lessons, the human's go, the merge. On S, and on a spec task, you fix what the review finds; in a build the `overload:step-implementer` does, from a test that reproduces the finding. A spec task of docs only has neither the slow tests nor the final review: its spec reviewer judged the spec and its decision records, and its checkpoint was the spec's.

## 1. Sync and integration check — phase `close/check`

1. `bash <scripts>/sync.sh`: when main moved since the branch started or last took it in, it merges main into the branch without committing, and the journal's `base` becomes main's commit. A conflict goes to `shared/escalate.md`; on the human's go, resolve it on the branch. A merge already under way (an interrupted session): finish it, from 2.
2. `bash <scripts>/verify.sh --integrate`: `check`, then the config's `check_integrate`, the tests too slow for every commit. With no `check_integrate` it runs `check` alone. Red: fix it (you, or the step-implementer in a build, from a test that reproduces it when the failing test does not already) and verify with `--integrate` again; the script stops you at the third red in a row (`shared/escalate.md`). After a sync, a red may come from main rather than the branch: run the same command on main alone, in a worktree under a folder made with `mktemp -d` (`git worktree add --detach <dir> <main>`, removed afterwards). Red there too, it is another task's regression: `shared/escalate.md`, and the human decides.
3. Commit: the merge, with its fixes, as one commit (`Merge branch '<main>' into <branch>`, unless the project's rules say otherwise); otherwise each fix on its own. A green `verify.sh --integrate` on a committed tree, or the commit of the tree it checked, moves the phase to `close/review`; on a spec task of docs only, which the script tells from the branch's diff and says so, to `close/write` (5).

## 2. Final review — phase `close/review`

Run the `overload:code-reviewer` agent with:

- the intent or the spec: with a spec (the journal's `spec`), its path; otherwise the journal's path and its section *Intent*;
- the range: first round `<base>..HEAD`, with `base` from the journal; a later round, the previous findings and `<sha>..HEAD`, `sha` being the HEAD the previous round reviewed;
- the config's `rules`;
- in a build, the command that shows how the recorded suites changed after the test-author handed them over: `bash <scripts>/suite.sh diff`. When the spec has one chunk, also the step reviewer's mandate: the tests cover the chunk, and none is vacuous.

At every round, log the round with the HEAD it reviewed (`journal.sh log "review round <n> on <sha>: <k> blocking"`). For each finding:

- **blocking, one right answer**: fixed (by you, or by the step-implementer in a build), starting from a test that reproduces it when it is a bug; verify; commit the fixes on their own; then a new round on the new range;
- **blocking, needs judgment**: under *Open findings*, for the checkpoint;
- **not blocking**: under *Backlog candidates*, with its source (`code-reviewer`).

A round that still finds blocking issues after the third goes to `shared/escalate.md`. You may reject a finding: write why under *Open findings*, and the human sees it.

## 3. Lessons — phase `close/lessons`

Only for a problem of this task, planning included, that got past the step meant to catch it (the review or check of its own step did not) and could recur beyond this task's area. A defect of the workflow itself goes to the checkpoint as such, not as a lesson. The candidates are in the journal's *Lesson candidates*. Prefer a check, a script or a lint rule to written text; propose also to retire a rule of the area that proved useless or superseded. No proposal: skip to 4.

Write the proposals to a file outside the repository, one per lesson: its text as it would land, where it lands (file and section, or the check and what it refuses), the evidence (a commit, a finding quoted as it came, a check's output, a `file:line`), and the step that found the problem and the one meant to catch it. Run the `overload:lesson-critic` agent with that path only. Apply the verdicts you accept; a `revise` or `drop` you reject keeps its reason. A spec task that reaches this step from the review took its lessons to the spec's checkpoint already: here, only the candidates noted since.

## 4. Summary and checkpoint — phase `close/checkpoint`

One message to the human:

- what changes and why, in a few lines, and the diff's stat (`git diff --stat <base>..HEAD`); in a build, the chunks as the spec ticks them;
- the last verify's result, and `check_integrate`'s;
- the findings that need their judgment, and those you rejected, with the reason;
- the backlog candidates, each with its source, after you compared them with the config's `backlog` file (an empty one has no items): a candidate that matches an item says so, already there or already dropped, with the item's date and reason;
- the lessons the critic kept, each with its verdict; a dropped one as a single line, so they can take it back.
- the defects of the workflow itself that the task met, each in one line.

Then stop and wait. The human gives the go and picks the lessons and backlog items to keep, or asks for changes: on S you are back in `s/implement`; on a spec task the spec goes back to `phases/l-plan.md` from 1; in a build the changes are one more chunk, a correction of the spec (`phases/l-chunk.md`, *A spec correction*), which goes through that file from its first step, then this file again from 1. Set the phase accordingly. Log their words.

## 5. Lessons and backlog — phase `close/write`

Write the approved lessons where they land, apply the approved retirements, and add the approved backlog items to the config's `backlog` file (if missing, create it with its heading, `# Backlog`) where its own rules put a new item, its header or its sections, else at its end; one item per entry: what, why, source. The rule, not its story: `git blame` gives the task and the date. Verify and commit the lessons on their own, then the backlog items on their own. A task that works an item of the backlog, as its intent names it, removes the item in a commit of its own; the file stays, its heading at least. A lesson that stays red goes to the human: retry, or skip, and the lesson leaves the task as a backlog item.

In a build, set the spec's `status: done` in the last of these commits, or in a commit of its own when nothing was approved.

## 6. Integrate — phase `close/integrate`

`bash <scripts>/integrate.sh`. It asks the human's permission; it merges with `--no-ff`, drops the journal and deletes the branch and its suite. It refuses a branch that does not hold main, after bringing main up to its upstream, and one where `check_integrate` has not run green since main last moved: run step 1 again, then integrate. Any other refusal leaves main as it was: go to `shared/escalate.md`. Then tell the human it is merged, in one line, with the merge's subject. After a spec task, add that `/overload:build <spec>` builds it, best in a new session (`/clear` first): the build starts from the spec, and needs none of this session's context.
