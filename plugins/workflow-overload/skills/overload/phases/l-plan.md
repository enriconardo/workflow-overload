# L path: planning

Produces a reviewed spec, split into chunks, that the human approves before any production code.

## 1. Spec — phase `l/spec`

You write it, because you hold the discussion with the human: an agent given a summary would lose the intent. Start from the explorer's map. Write it at `<specs>/<YYYY-MM-DD>-<description>.md` (the config's `specs`) and record its path: `journal.sh set spec <path>`.

```
---
status: draft
branch: <branch>
---

# <What changes, in a line>

## Why
The problem, and how it was seen: a commit, a finding, a failing test, a measured cost. An assertion is not a sighting.

## What
The behavior after the change, for a caller: signatures, errors, defaults, what is out of scope.

## Decisions
Each decision, the alternatives weighed (doing nothing included) and why this one.

## Test cases
The cases that prove the behavior, each one line: input, expected result.

## Chunks
- [ ] 1. <title> (test-first | no test-first): the files, the test cases it covers
```

A decision that outlives the task also gets a decision record, where the project keeps them (the config's `rules` names the folder).

**Chunk types.** Test-first: a new or changed behavior of the public API, domain logic, a bug. No test-first: a refactor (the existing tests stay green unchanged), wiring (tested afterwards by the implementer), docs, config.

## 2. Probe — phase `l/probe`, only when the spec rests on external facts not yet checked

Versions, APIs, a dependency's behavior. Run the `workflow-overload:prober` agent with the questions, one per line, and the config's `probe_env`. It answers each with the commands it ran and their output. Update the spec, and note in *Decisions* what the probe settled.

## 3. Spec review — phase `l/spec-review`

Run the `workflow-overload:spec-reviewer` agent with the spec's path and the explorer map's path (write the map to a file outside the repository first), and the config's `rules`. Never a summary of the discussion. Increment `spec_review_rounds` in the journal.

For each objection: accept it and fix the spec, or reject it with a reason, which goes under *Open findings*. A new question about external facts goes back to 2; a question only the human can answer goes to them now. The loop ends when the reviewer's last round raises no objection you accept. Each accepted objection fixes the spec and calls for another round. At most three rounds, then `phases/escalate.md`; past the third, every round ends there again while an objection stays open.

## 4. Threshold

A chunk stays under about 6–7 files touched or 10–15 test cases, so that its implementer works with all of it in context. Estimate from the spec and the map. One chunk: skip 5.

## 5. Split — phase `l/split`

Run the `workflow-overload:spec-splitter` agent with the spec's path and the map's path. It returns the fewest chunks, each able to leave the repository green alone, each with its type. Write them in the spec's *Chunks*.

## 6. Summary and checkpoint 1 — phase `l/checkpoint`

One message to the human: what changes according to the spec, how it splits into chunks and their types, the decision record if any, the facts the prober checked, the spec reviewer's objections still open and those you rejected, each with its title and reason, the risks and the questions. Then stop and wait.

The human approves, or sends the spec back for corrections (to 1, then 3), or the requirements back to the brainstorming. Log their words.

## 7. Commit the spec

Set `status: approved`, then verify and commit the spec and the decision record, so that an interrupted session resumes from them. Set the phase to `l/chunk-1/test`.

## 8. Restart, recommended

Tell the human, in one line, that this is the moment for `/clear` and then `/overload`: the next session resumes from the journal and the spec, with a few thousand tokens of context instead of the whole brainstorming. Every call that directs the implementation rereads that context. Wait for them, or go on if they say so: then read `phases/l-chunk.md`.
