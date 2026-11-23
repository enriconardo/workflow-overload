# L path: the spec

Produces a reviewed spec, split into chunks, that the human approves before any production code. The task ends there, with the spec on main; `/overload:build` builds it, from main, in a session of its own. The spec is all that session gets: the journal stays on this branch, and goes with its merge.

## 1. Spec — phase `l/spec`

You write it, because you hold the discussion with the human: an agent given a summary would lose the intent. Start from the explorer's map, which the spec reviewer and the splitter read too: if the brainstorming logged none, run the `overload:code-explorer` agent now, as `phases/brainstorm.md` says, and keep the file it saved: `journal.sh keep map <path>`. Write it at `.workflow/specs/<YYYY-MM-DD>-<description>.md`, or, with inputs (the journal's *Inputs*), at `.workflow/specs/<slug>.md`, named as their folder, and record its path: `journal.sh set spec <path>`. The inputs stay the source and the spec translates them: each point of an input becomes a behavior of *What* or a case of *Test cases*, or is named out of scope in *What*.

```
---
status: draft
branch: <branch>
inputs: <the inputs' paths, or none>
depends_on: <the files the spec rests on, comma-separated>
---

# <What changes, in a line>

## Why
The problem, and how it was seen: a commit, a finding, a failing test, a measured cost. An assertion is not a sighting.

## What
The behavior after the change, for a caller: signatures, errors, defaults, what is out of scope.

## Decisions
Each decision, the alternatives weighed (doing nothing included) and why this one. A decision of the human is marked as theirs, with their words.

## Test cases
The cases that prove the behavior, each one line: input, expected result.

## Docs
The files that describe this behavior and change with it (a README, API docs, a guide), or none.

## Chunks
- [ ] 1. <title> (test-first | no test-first | tests only): the files, the test cases it covers[; signatures: the existing declarations whose signature changes][; dependencies: the packages it adds][; inputs: those its code must match as they are]
```

**What the build needs from the journal** goes in the spec before each spec review round, so that the reviewer judges it too: the human's decisions and rulings that bear on the code, in *Decisions*, marked as theirs with their words; a ruling on one chunk, in that chunk's line.

`depends_on` names the files the chunks name and those of the explorer's map, so that a build can tell whether main changed them since the approval. Write it with the chunks (4, 5).

A decision that outlives the task also gets a decision record, in a folder of the config's `rules` that already holds decision records. With no such folder, write none and create none: the human hears it at the checkpoint (7), with `/overload:setup`, which proposes one.

**Chunk types.** Test-first: a new or changed behavior of the public API, domain logic, a bug, whose tests fail at runtime against its stubs. Tests only: tests with their fixtures and helpers, no other file, for behavior already there. No test-first: a refactor (the existing tests stay green unchanged), wiring (tested afterwards by the implementer), docs, config, a chunk whose code is only declarations (types, interfaces: its stub is its code, and its tests fail only in the type checker).

## 2. Probe — phase `l/probe`, only when the spec rests on external facts not yet checked

Versions, APIs, a dependency's behavior. Run the `overload:prober` agent with the questions, one per line. It answers each with the commands it ran and their output. Update the spec, and note in *Decisions* what the probe settled.

## 3. Spec review — phase `l/spec-review`

Run the `overload:spec-reviewer` agent with the spec's path, the map's path (the journal's `map`), the inputs' paths, the decision records the spec writes, and the config's `rules`. Never a summary of the discussion. Log the round: `journal.sh log "spec review round <n>: <k> blocking"`.

For each objection: accept it and fix the spec, or reject it with a reason, which goes under *Open findings*. A new question about external facts goes back to 2; a question only the human can answer goes to them now. The loop ends when the reviewer's last round raises no blocking objection you accept. A minor one you fix, or reject, without another round; an accepted blocking one fixes the spec and calls for another round. At most three rounds, then `shared/escalate.md`; past the third, every round ends there again while a blocking objection stays open.

## 4. Threshold

A chunk stays under about 6–7 files touched or 10–15 test cases, so that its implementer works with all of it in context. Estimate from the spec and the map. One chunk: skip 5, and write its line and `depends_on` yourself.

## 5. Split — phase `l/split`

Run the `overload:spec-splitter` agent with the spec's path and the map's path (the journal's `map`). It returns the fewest chunks, each able to leave the repository green alone, each with its type. Write them in the spec's *Chunks*, and `depends_on`.

## 6. Lessons — phase `l/lessons`

As `shared/close.md` step 3 says, on this task's planning: the spec's checkpoint is the task's only one, and the lessons go to it.

## 7. Summary and checkpoint — phase `l/checkpoint`

One message to the human, the task's only checkpoint: what changes according to the spec, how it splits into chunks and their types, the decision record if any, and a decision left without one because `rules` holds no folder of them (`/overload:setup` proposes one), the facts the prober checked, the spec reviewer's objections still open and those you rejected, each with its title and reason, the risks and the questions; then, as `shared/close.md` step 4 says, the backlog candidates, the lessons the critic kept, and the defects of the workflow. Then stop and wait.

The human approves the spec and picks the lessons and backlog items to keep, or sends the spec back for corrections (to 1, then 3), or the requirements back to the brainstorming. Log their words.

## 8. Commit the spec

Set `status: approved`, then verify and commit the spec, its decision record and its inputs. The commit moves the phase to `close/check`: go on with `shared/close.md` from 1. On a task of docs only, its verify moves the phase on to the writing of the lessons and backlog items the human picked, with no final review; a task that holds more, such as the commits of an S turned L, has the whole close.
