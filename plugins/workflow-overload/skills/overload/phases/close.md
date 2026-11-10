# Close

Both paths end here: one final review, one round of lessons, the human's go, the merge. On the S path you fix what the review finds; on the L path the `workflow-overload:step-implementer` does, from a test that reproduces the finding.

## 1. Final review — phase `close/review`

Run the `workflow-overload:code-reviewer` agent with:

- the intent or the spec: on S, the journal's path and its section *Intent*; on L, the spec's path (the journal's `spec`);
- the range: first round `<base>..HEAD`, with `base` from the journal; a later round, the previous findings and `<sha>..HEAD`, `sha` being the HEAD the previous round reviewed;
- the config's `rules`;
- on L, the command that shows how the recorded suites changed after the test-author handed them over: `bash <scripts>/suite.sh diff`. When the spec has one chunk, also the step reviewer's mandate: the tests cover the chunk, and none is vacuous.

At every round, increment `review_rounds` in the journal and log the round with the HEAD it reviewed (`journal.sh log "review round <n> on <sha>: <k> blocking"`). For each finding:

- **blocking, one right answer**: fixed (by you on S, by the step-implementer on L), starting from a test that reproduces it when it is a bug; verify; commit the fixes on their own; then a new round on the new range;
- **blocking, needs judgment**: under *Open findings*, for the checkpoint;
- **not blocking**: under *Backlog candidates*, with its source (`code-reviewer`).

A round that still finds blocking issues after the third goes to `phases/escalate.md`. You may reject a finding: write why under *Open findings*, and the human sees it.

## 2. Lessons — phase `close/lessons`

Only for a problem of this task, planning included, that got past the step meant to catch it (the review or check of its own step did not) and could recur beyond this task's area. A defect of the workflow itself goes to the checkpoint as such, not as a lesson. The candidates are in the journal's *Lesson candidates*. Prefer a check, a script or a lint rule to written text; propose also to retire a rule of the area that proved useless or superseded. No proposal: skip to 3.

Write the proposals to a file outside the repository, one per lesson: its text as it would land, where it lands (file and section, or the check and what it refuses), the evidence (a commit, a finding quoted as it came, a check's output, a `file:line`), and the step that found the problem and the one meant to catch it. Run the `workflow-overload:lesson-critic` agent with that path only. Apply the verdicts you accept; a `revise` or `drop` you reject keeps its reason.

## 3. Summary and checkpoint — phase `close/checkpoint`

One message to the human:

- what changes and why, in a few lines, and the diff's stat (`git diff --stat <base>..HEAD`); on L, the chunks as the spec ticks them;
- the last verify's result;
- the findings that need their judgment, and those you rejected, with the reason;
- the backlog candidates, each with its source;
- the lessons the critic kept, each with its verdict; a dropped one as a single line, so they can take it back.
- the defects of the workflow itself that the task met, each in one line.

Then stop and wait. The human gives the go and picks the lessons and backlog items to keep, or asks for changes: on S you are back in `s/implement`; on L you add the changes to the spec as one more chunk, and it goes through `phases/l-chunk.md`, then this file again from 1. Log their words.

## 4. Lessons and backlog — phase `close/write`

Write the approved lessons where they land, apply the approved retirements, and add the approved backlog items at the end of the config's `backlog` file (create it if missing), one item per entry: what, why, source. The rule, not its story: `git blame` gives the task and the date. Verify and commit the lessons on their own, then the backlog items on their own. A lesson that stays red goes to the human: retry, or skip, and the lesson leaves the task as a backlog item.

On L, set the spec's `status: done` in the last of these commits, or in a commit of its own when nothing was approved.

## 5. Integrate — phase `close/integrate`

`bash <scripts>/integrate.sh`. It asks the human's permission; it merges with `--no-ff`, drops the journal, records the measures and deletes the branch and its suite. On a conflict or a red verify on the merge's result it leaves main as it was: go to `phases/escalate.md`. Then tell the human it is merged, in one line, with the merge's subject.
