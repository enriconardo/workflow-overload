# The plan

A change too large for one spec becomes a plan: a sequence of tasks, its items, each S or L, integrated on main one at a time. This task writes the plan and the documents that fix its decisions, up to the human's approval and its merge; each item is then a task of its own, `/overload:task <plan> <n>`, with its own checkpoint. One plan is open at a time.

## 1. Plan — phase `p/plan`

You write it, for the reason you write a spec: you hold the discussion with the human. Start from the explorer's map; if the brainstorming logged none, run the `overload:code-explorer` agent now, as `phases/brainstorm.md` says, and keep its file: `journal.sh keep map <path>`. Write the plan at `.workflow/plans/<YYYY-MM-DD>-<description>.md`, or, with inputs (the journal's *Inputs*), at `.workflow/plans/<slug>.md`, named as their folder, and record its path: `journal.sh set plan <path>`. The inputs stay the source: each point of an input becomes a requirement, or is named in *Out of scope*.

```
---
status: draft
inputs: <the inputs' paths, or none>
---

# <The goal, in a line>

## Why
The problem, and how it was seen.

## Final state
How the system looks and behaves once every item is done.

## Requirements

### <Area>
- <AREA>-01. <an observable behavior> — verify: test
- <AREA>-02. <a constraint: performance, security, compatibility> — verify: measure; acceptance

## Out of scope

## Cross-cutting decisions
Each decision, the alternatives weighed (doing nothing included) and why this one; a decision record it has, by path. A decision of the human is marked as theirs, with their words.

## Unknowns
What the first items find out.

## Items
- [ ] 1. <title> (S estimated | L estimated[: why]): <intent>; covers <IDs>; closes <IDs>; depends on <n>, ... | —

## Acceptance
- [ ] <IDs>: <preconditions>; <action>; <expected result>
```

- **Requirements**, by area, the area in the ID (`AUTH-01`): each an observable behavior or a constraint, with how it is verified: `test`, `test outside check` (end-to-end, run by `check_integrate`), `acceptance` (a person tries it), `measure`. A constraint you cannot say how to verify is no requirement yet. They change only through a revision of the plan.
- **Items**, in the order they run: each a task that leaves main green and coherent by itself: `check` and `check_integrate` green, no test of a requirement already closed broken, and a user sees the old behavior or the new one, never something in between. Its tier is an estimate, which the human confirms when the item opens; never a count of chunks, which the splitter makes from its spec. A requirement that several items cover names the one that closes it, usually the last: its spec holds the test that proves it across the items, written before its code.
- **When a green cut seems impossible** (a migration, a pervasive rename, a change of format), in this order: expand/contract (the new beside the old, the callers moved, the old removed); branch by abstraction (an abstraction in front of the code to replace, then the change behind it); a feature flag (the new code lands off and is turned on last). A long-lived integration branch is the last resort, and the human's decision, recorded as theirs.
- **Acceptance**: a step for each requirement verified by `acceptance` or `measure`, written now, with the requirements, as a test is written before its code. A step that names a version names it as an item's merge. When the project has a CI, a last step of no requirement: the last item merged and pushed, the CI of main green.
- **Documents that fix decisions before code** (decision records, a glossary, a domain model) are this task's product: write them now, before the first review, and cite them in the plan rather than repeat them. A decision record goes in a folder of the config's `rules` that holds them; with none, write none and create none: the human hears it at the checkpoint (4), with `/overload:setup`, which proposes one. Documents that describe what gets built (an overview of the architecture, a user guide) are written by the item that builds it, or by a last item of docs only.
- What the items need from the discussion goes in the plan before each review round: the human's decisions that bear on several items in *Cross-cutting decisions*, marked as theirs with their words; one that bears on a single item, in its intent.

Before each review round, `bash <scripts>/plan.sh check <plan>`: it lists each way the plan is out of format (an ID, a requirement no item covers or none closes, a missing acceptance step, a dependency). Fix them all.

## 2. Plan review — phase `p/review`

Run the `overload:plan-reviewer` agent with the plan's path, the map's path (the journal's `map`), the inputs' paths, the paths of the documents that land with the plan, and the config's `rules`. Never a summary of the discussion. Log the round: `journal.sh log "plan review round <n>: <k> blocking"`.

Settle each objection as `phases/l-plan.md` step 3 settles a spec reviewer's: accept it and fix the plan, or reject it with a reason under *Open findings*; a question only the human can answer goes to them now. At most three rounds, then `shared/escalate.md`.

## 3. Lessons — phase `p/lessons`

As `shared/close.md` step 3 says, on this task's planning: the plan's checkpoint is the task's only one, and the lessons go to it.

## 4. Summary and checkpoint — phase `p/checkpoint`

One message to the human, the task's only checkpoint: the goal and the final state; the requirements, by area; the items in order, each with its tier, what it brings and what it closes; the cross-cutting decisions and the documents that land with the plan, and a decision left without a record because `rules` holds no folder of them; the acceptance steps; the reviewer's objections still open and those you rejected, each with its title and reason; the unknowns and the risks; then, as `shared/close.md` step 4 says, the backlog candidates, the lessons the critic kept, and the defects of the workflow. Then stop and wait.

The human approves the plan and picks the lessons and backlog items to keep, or sends the plan back for corrections (to 1, then 2), or the request back to the brainstorming. Log their words.

## 5. Commit the plan

Set `status: approved`, run `plan.sh check` again, then verify and commit the plan, its documents and its inputs. The commit moves the phase to `close/check`: go on with `shared/close.md` from 1. A task of docs only goes from its verify to the writing of the lessons and backlog items the human picked, with no final review; one that changes more has the whole close.
