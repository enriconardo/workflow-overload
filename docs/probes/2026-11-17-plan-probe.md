# Probe: a plan run item by item with today's task

Opened 2026-11-17. Step 2 of the 0.6.0 design: before `build` and the plan are written, a plan written by hand for a real large task, its items run one at a time by the current `/overload:task`. It measures three things, each feeding a decision of 0.6.0:

| Question | Feeds |
| --- | --- |
| **Size of the items**: does an item fit one L, and does the plan's tier estimate hold at triage? | the triage criteria for a plan; the "more than about 5 chunks" threshold; plan-reviewer's "an item larger than an L" |
| **Cost per item**: what each item pays in tokens, wall time and human turns, and how much of it is the fixed part (brainstorming, final review, checkpoint, merge) | the design's weak point 3: is the cost worth it on a ten-item plan, and what to lighten for an item of a plan |
| **Use of the acceptance**: which defects the human's checklist finds that `check` and `check_integrate` missed, and what it costs to run | the acceptance in `build <plan>`, and the optional "how to try it" at each item's checkpoint |

On the way it also sees: whether each item leaves main green and coherent, whether a requirement spanning items gets its test from the item that closes it, how often discoveries call for a plan revision, and setup on an empty repository followed by the task that brings the stack (step 1, first real use).

## Setup

- A new public repository, `lists`: a small web app of shared lists. Its plan is `2026-11-17-lists-plan.md`, beside this file: three areas a user sees, a schema migration after data exists, two requirements closed only by a later item.
- The plugin from this repository's `main` at `00f1129` (0.5.1 and step 1, not yet on the marketplace): installed from the local checkout, `/plugin marketplace add <path to this checkout>` then `/plugin install overload@workflow-overload`, after removing the marketplace's own copy.
- Claude Code, Node 24, pnpm, git 2.43, python 3.12, WSL2.

## How it runs

Today's task knows no plan, so the human plays the parts 0.6.0 would automate. Each one is marked *(stands for …)*.

1. `git init` the new repository, then `/overload:setup`: the skeleton, `check` empty, the conventions, `docs/adr/` if proposed.
2. **Item 0, the plan lands** *(stands for a task that brings a plan)*: `/overload:task` with the plan file as input, asking to add it as `.workflow/plans/lists.md` with `status: approved` and its decisions as records. Before it, an agent with a clean context reviews the plan with plan-reviewer's questions from the design *(stands for plan-reviewer)*, and the human settles the findings; see *Plan review*.
3. **Items 1 to 7**, one at a time, each in a fresh session:
   - note the start time, then `/overload:task item <n> of .workflow/plans/lists.md; tick it in the task's diff`;
   - on L, take the `/clear` recommended after the spec's commit and note its time: before it is what 0.6.0's `task` would do, after it what `build` would do *(stands for the split into two merges)*;
   - at the final checkpoint, before the go, fill the item's row below from the journal and the diff, and answer: does what this item found change a later item? Yes: a plan revision, as its own S task, recorded as a row too *(stands for a revision through task)*;
   - after the merge, note the end time and run `check` and `check_integrate` on main.
4. **Acceptance** *(stands for `build <plan>`)*: the human runs the plan's *Acceptance* on main, in order, timing it. A failure the triage would call S is fixed by an S task, starting from a test that reproduces it; a larger one becomes a new item. Each step's result goes in the second table.
5. **Reading**: tokens per item come from the session transcripts, the main session's and its agents', summed between the noted times; no counter in the plugin.

## Plan review

2026-11-17, one round, before item 0. A general-purpose agent got the plan, spec-reviewer's criterion on decisions, the tier rules and the design's seven questions for plan-reviewer, and nothing of the discussion. About 48,000 tokens, 4 tool calls, under two minutes.

- **1 blocking, accepted.** D1 promised one language "for the browser script too" with no build: a browser runs no TypeScript. The browser script is now JavaScript under `// @ts-check`. The plan's author had missed it, and item 3 would have hit it.
- **11 minor, all accepted, two of them in part.** The tsconfig flags that keep vitest and `node` in agreement. The rendering path: server fragments, one renderer. Dependencies: item 6 on 4, which also closes F4 with notes; item 7 on 6. Notes kept out of the export. Access from other devices out of scope. N2 as a Playwright test. A seed script for N4 in item 3. N1's old database built at acceptance from the commit before item 6, not saved ahead of time. Acceptance run at the plan's end. The database path in `LISTS_DB`, opened by item 1. SSE's six-connection limit noted.
- **The parts rejected**: weighing htmx and polling again, since the human ruled the decisions irrelevant to a throwaway project; and a rule for a database newer than the code, which went to *Out of scope*.
- **Its size estimate**: no item above about 3 chunks (items 2 and 3); item 5 is one chunk, L only for its new URL. To compare with what the splitter counts.

So, at plan level, the reviewer found a defect in a cross-cutting decision before any code, and four of its minor findings were about the cut between items (dependencies, which item closes what, what an item changes in an earlier one): the parts no spec-reviewer of a single item would see.

## Items

| # | Tier: plan → triage | Chunks | Files | Test cases | Spec rounds | Review rounds | Escalations | Red verifies | Human turns | Wall time (before / after `/clear`) | Tokens (before / after) | Main green and coherent | Plan change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | S → |  |  |  |  |  |  |  |  |  |  |  |  |
| 1 | L → |  |  |  |  |  |  |  |  |  |  |  |  |
| 2 | L → |  |  |  |  |  |  |  |  |  |  |  |  |
| 3 | L → |  |  |  |  |  |  |  |  |  |  |  |  |
| 4 | L → |  |  |  |  |  |  |  |  |  |  |  |  |
| 5 | L → |  |  |  |  |  |  |  |  |  |  |  |  |
| 6 | L → |  |  |  |  |  |  |  |  |  |  |  |  |
| 7 | L → |  |  |  |  |  |  |  |  |  |  |  |  |

*Human turns*: the messages the human had to write, go's included. Also count, per item, the brainstorming's questions the plan already answered: they measure what "it asks only what the plan does not say" would save.

## Acceptance

| Step | Result | Defect found | Would a test have caught it? | Minutes |
| --- | --- | --- | --- | --- |
| N3 |  |  |  |  |
| F1, F2 |  |  |  |  |
| F3 |  |  |  |  |
| F4 |  |  |  |  |
| F5 |  |  |  |  |
| F6, N1 |  |  |  |  |
| F7 |  |  |  |  |
| N2 |  |  |  |  |
| N4 |  |  |  |  |

## What would change 0.6.0

Read before the results, so that the results do not pick the reading.

- **Items too large**: an L item past about 5 chunks, or a triage that disagrees with the plan on more than one item. The plan's criteria, or plan-reviewer's size check, need a measure the plan can give.
- **Items too costly**: on a small item, the fixed part outweighs the code. Lighten what an item of an approved plan repeats (the brainstorming, the explorer) before adding anything.
- **Nearly every item L**: in an app a user sees, the triage makes almost every item L, so almost every item pays two merges in 0.6.0. Then the split's cost is the plan's cost, and weighs on decision 5.
- **Acceptance that finds nothing**: every step passes, or each defect it finds a test could have caught. Then it shrinks to the steps only a human can judge (N2, the feel of F4), and the "how to try it" at each checkpoint becomes the main tool.
- **Coherence broken**: main red, or a user seeing half a behavior, after an item. The plan-reviewer's "each item leaves main green and coherent" needs teeth.

## Results

To be written as the items run. Observations as they come:

- **Setup on an empty repository** (2026-11-17): it chose `master` from git's default, wrote the config with `check`, `check_integrate` and `run_tests` empty, the rules in `CLAUDE.md` and `docs/adr/` with a template, and committed. The first run stopped before any change, because Claude Code's auto-mode permission check did not answer; not the plugin's doing. A stale cache had also installed the set-aside roadmap build in place of the checkout: removing `~/.claude/plugins/cache/workflow-overload` before the install fixed it.
- **The backlog setup writes is empty, 0 bytes**, and item 0's main agent reported "no backlog file": Claude Code's Read refuses an empty file, which reads as a missing one. A candidate fix in the plugin: setup writes the backlog with a heading.
- **Item 0**, the plan and seven decision records, docs only, triaged S: code-reviewer ran two rounds and found one blocking defect, an alternative in a decision record that the plan never weighed. The 0.6.0 design closes a docs-only task without code-reviewer and has plan-reviewer judge the documents that land with the plan; this says that judgment is not a formality: plan-reviewer must read each record against the plan.
- **The empty backlog, confirmed**: items 1, 2, 3 and 4 each reported "`.workflow/backlog.md` does not exist yet". Five items out of five.
- **Item 1**, the skeleton, L: 5 chunks, at the threshold, where the plan review had estimated 2; 25 files, about 700 lines besides the lockfile, many of them small config files. 2 spec rounds (2 blocking), 6 step rounds, 1 final round. Chromium runs in Docker, since it cannot start on the WSL host, so `check_integrate` needs Docker and the internet. `/overload:setup` again afterwards measured `red_types = AssertionError, NotImplemented` and kept every other value.
- **Item 2**, storage and API, L: 4 chunks, about 320 lines of code and 1,050 of tests. The first escalation: chunk 1's step review reached three rounds, each with a different real defect (a rollback of the caller's transaction, an error naming the wrong number, a missing test). The limit stopped a loop that was converging; the human allowed a fourth round, which was clean.
- **Item 3**, pages, L: 5 chunks, at the threshold again; 3 spec rounds (1 blocking in each of the first two). N4 measured 5.0 ms against 200 ms. It closed F1, F2 and F3 with end-to-end tests.
- **Item 4**, live updates, L: 3 chunks; 17 files, +1,194 −19; one session, 53 minutes from the command to the merge checkpoint. 3 spec rounds (3, 1 and 0 blocking): the round 1 findings were real (a change lost between the render and the stream's subscription, a put-off rename dropped on save, a test that passed without the feature). 4 step rounds, 2 of them on chunk 1 for a test that could not tell a failing rename from a valid one. The two unknowns the spec left for the first end-to-end run, events through the Docker tunnel and a reconnect within 2 s, both held. The final review found a narrow race during an inline edit, an F4 defect that the spec's own rule allows. Merged at the human's go, with no backlog item and the race left to item 6 (below).
- **Item 5**, Markdown export, L: 2 chunks, the smallest L so far, 9 files, +334 −5, of which 26 lines of code; the plan's "L estimated: a new public URL" holds, barely. 38 minutes from the command to the merge checkpoint, 21 of them waiting at the spec checkpoint; the human cleared the context there and resumed with `/overload:task`, which picked up at chunk 1 from the journal. 1 spec round (holds, six minors fixed without a round), 1 step round per chunk, 1 final round. A probe settled the routing (`/lists/:id.md` takes every path ending in `.md`, in either order), which the map had flagged with the test that pinned `/lists/5.md` as a 404. The final reviewer rendered 30 hostile texts with a real GFM renderer: each stayed one heading and plain items. Its tests run in `check`, and all got a red, except one that passed before the code (the 404 of an invalid id), sent to the step review's mutation check.
- **Item 6**, item notes, L: 5 chunks, at the threshold, as expected for the biggest item; 21 files, +907 −55. 1 spec round (8 minors), split at once. The work stopped in chunk 4 on the account's usage limit, with the implementer's edits half done, and resumed the next morning in the same session: the journal and the tree were enough, but the checksums kept in the scratchpad were gone (below). Brainstorming to merge: about 10 minutes to the spec checkpoint, 20 for chunks 1 to 3, 20 for chunks 4 and 5 and the close. 7 step rounds, 2 of them on real defects: `updateItem` writing a field passed as `undefined` (chunk 2), and no test telling the spec's `refresh()` rule from the alternative it rejected (chunk 4: the reviewer swapped that alternative in and every test stayed green). The test added for it, 16a, failed 30 times out of 30 under both mutants; it counts fetches with the stream open, against ADR 0012, which the human allowed and ADR 0015 records. Both revisions of the plan carried into item 6 were covered by the spec. F4, F6 and N1 closed.
- **The tests of requirements that span items get no red check.** They are end-to-end tests, in `e2e/*.e2e.ts`, outside `tests_glob` and `run_tests`: in item 3 the implementer wrote them in a no-test-first chunk, with no separate author and no red check, and only the step review caught a weak one. The design's "the closing item's test is written before the code and fails" holds for a test in `check`, not for the "test outside check" these requirements mostly need. Step 3 must say how such a test gets an author and a red.
- **The same gap in item 4, where the test-author wrote the end-to-end tests**: it found that `tests_glob` misses `e2e/*.e2e.ts`, so `suite.sh` recorded none of them and nothing kept the implementer from editing them; the main agent guarded them by hand with checksums. Both proposed adding `**/*.e2e.*` to `tests_glob`, which would break verify: it passes the recorded files to `run_tests`, here vitest. Step 3 needs, for a test outside `check`, both the guard and the red, through its own command.
- **Item 6 ran a chunk of end-to-end tests only, test-first**, at the human's word at the spec checkpoint: the main agent had retyped it no test-first against the splitter, citing item 3. The test-author wrote cases 14 to 17 and showed them failing through `npm run test:e2e`, case 16 at the very step of the bug; `suite.sh` had nothing to record, the journal said so, and the main agent guarded the two files with checksums. It worked, but every guard was by hand, and the checksums, kept in the scratchpad, were lost overnight: the main agent rebuilt them from an agent's report and moved them to `.git/overload/`, which the human then had it delete after the merge. Step 3's command for tests outside `check` needs its record and its guard where the scripts keep their state.
- **The brainstorming asks what the plan says**: item 2 asked whether to refuse a database newer than the code (out of scope in the plan) and how to verify F3 (the plan says); item 3 asked whether the pages work without JavaScript (D4 says) and half of its question on errors (F7 is item 7's). About one question in four across items 2 and 3. Item 4 asked five, none of them answered by the plan; item 5 five, one of them (the order) answered by the acceptance step, which the main agent cited. Item 6 asked three and the tier in Claude Code's question dialog, not in a message, none answered by the plan; one rightly caught ADR 0013 announcing a new event name that the answer replaced with the existing one.
- **The first plan revision**, after item 3: a backlog candidate of item 3's review (a fragment request failing partway) is F7's, so an S task added it to item 7's line instead of the backlog. One docs-only S task.
- **The second plan revision**, after item 4: the race of item 4's final review is F4's, which item 6 closes, so an S task added it to item 6's line, with where it lies (`refresh()`) and the rule of the fix. One docs-only S task again: 8 minutes from the command to the merge, one review round with no finding. Each revision so far is a line the next items carry, not a backlog item.
- **A third revision, inside an item's own diff**: item 5's spec-reviewer saw that nothing made item 6 test that the export keeps notes out, so item 5's docs chunk added it to item 6's line. Cheaper than a separate S task; it works when the revision is known before the code, at the spec review, and not at the final review.
- **Defects of the plugin the main agents reported**, none of them the plan's:
  - processes left running: a server started by step-implementer in item 1 (the main agent was not allowed to stop it), one started by the main agent's own measure in item 3. step-implementer, and the main agent, should stop what they start;
  - `phases/l-chunk.md` sends a chunk that "changes no source file" to the test step: meant for a chunk of tests only, it catches a docs-only chunk too (item 1); in item 5 the main agent skipped the test step for a docs-only chunk, logged it, and asked the human, since the rule reads the other way;
  - `agents/step-test-author.md` does not say that a new test already passing is a valid red (listed for the step review), so in item 2 the test-author left two tests out;
  - `agents/spec-reviewer.md` does not forbid reading `.workflow/journal.md`, which holds the human's decisions: in item 4 the round 1 reviewer kept out of it on its own, the round 2 one read it;
  - code-explorer's map gave wrong line numbers in item 4 (`refresh()` at lines 416–440 of a 200-line `app.js`), so the main agent read the files itself and warned every later agent in its prompt; in item 5 its ADR line numbers were off again, flagged by the spec-reviewer;
  - in item 5 the main agent saved the human's answer on the docs-only chunk in Claude Code's own memory for the project, not in the journal or the rules: a rule the plugin does not see, which every later session of the probe now loads.
  - the red check cannot tell a stub's failure from a real one when it reaches the test through the server: in item 6 chunk 2, existing PATCH tests failed with a 500 because the stub threw `NotImplemented` inside a route, and the check accepted them;
  - a test added after the code, at a step review's finding (item 6, case 16a), can never be shown red: the test-author may not read the code to put the old behavior back, so only the reviewer's mutants back it. The phase gives no way for the reviewer to run that red;
  - the scratchpad is not a place for a task's state across sessions: it was cleared overnight (item 6). Anything a later session needs goes in the journal or under `.git/overload/`;
  - item 5's memory was applied in item 6: its docs chunk skipped the test step, citing the human's answer on the export.
