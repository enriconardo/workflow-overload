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

To be written as the items run.
