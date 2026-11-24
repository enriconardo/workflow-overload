# A change of a decision on main

A plan approved on main, or a spec approved and not built, is a decision: it changes only through a task of its own, which the human approves at its checkpoint as they approved the decision. The open plan is revised or dropped; a spec is dropped. A spec changes otherwise in its build, as a correction that its reviewer judges, or is dropped and written anew; a spec built (`status: done`) is code on main, which a new request changes.

## 1. Understand

Read the document in full; on a plan, also its items' state, as the status gives the next one, and the specs on main that name its items. Restate what the human asks and why. Whether a plan is revised or dropped is theirs: ask when their words leave it open. Ask only what the document and the request leave open; explore with the `overload:code-explorer` agent, as `phases/brainstorm.md` step 2 says, only when a revision adds or changes items whose code you do not know. No file changes yet.

## 2. Open the branch

Write the intent to a file outside the repository: what changes and why, with the human's words where they matter. Then:

```
bash <scripts>/branch.sh <P|D> <name> <intent-file> --change <doc> [--map <file>] [--inputs <slug> <file>...]
```

`P` revises the open plan; `D` drops the open plan or the spec. The script refuses a document main does not hold approved, a spec with `P`, and a drop while an item of the plan is open on a branch: that task stops or ends first. New inputs of a revision go in a folder of the plan's name.

## A revision — tier P

`phases/plan.md`, from 1, on the plan as main holds it, with these differences:

- **What it may change.** Items not ticked and not open on a branch, whose number they keep; a new item, a split item's new part included, takes the next free number, one after the other; requirements, acceptance steps and cross-cutting decisions, the items that cover them changed with them. A ticked item stays as it is, and so does a requirement it closed, unless an item added proves it again. The status stays `approved`, and no item is ticked.
- **An item whose spec main holds approved** (the status's *next* names it): a removed item takes its spec to `dropped`, as *A drop* below says, in this task. A changed one keeps its spec, which its build reviews against the revised plan before any chunk (its expiry), or drops it: the human chooses at the checkpoint, and the plan's line says nothing of it.
- **The plan reviewer** gets also the revision, `git diff <base> -- <plan>` with `base` from the journal, and the paths of the specs on main of the items it changes.
- **The checkpoint** shows the revision first: each item added, removed or changed, with what changes and why; the specs dropped, and those kept for their build's review.
- **After the merge**, the status names the next item, which may have changed.

`integrate.sh` refuses a revision that changes a ticked item or one open on a branch, ticks an item, leaves approved the spec of an item it removes, or changes another spec or plan.

## A drop — tier D

### 1. Drop — phase `d/drop`

1. Set `status: dropped`, and add a last section `## Dropped` with the reason, in the human's words: why the decision no longer holds. Change nothing else of it.
2. **A plan dropped** drops with it each spec main holds approved for one of its items, the same way, its reason naming the plan's drop. A ticked item stays as built; a spec `done` stays done.
3. **Decision records** the document cites, or that cite it: mark each withdrawn or superseded, as the project's convention for them says, in its own words. The plugin imposes no state on them; with no convention in the record or the rules, ask the human.
4. Its inputs stay where they are: `git log` finds them.

### 2. Lessons — phase `d/lessons`

As `shared/close.md` step 3 says, only with lesson candidates: the drop's checkpoint is the task's only one.

### 3. Summary and checkpoint — phase `d/checkpoint`

One message to the human: the document and the reason; on a plan, the items already built, which stay, and the specs dropped with it; the decision records marked, and how; then, as `shared/close.md` step 4 says, the backlog candidates, the lessons the critic kept, and the defects of the workflow. Then stop and wait. The human approves the drop, or changes it (back to 1), or keeps the decision: then the task ends without a merge, and on their go you switch to main and delete its branch. Log their words.

### 4. Commit the drop

`bash <scripts>/verify.sh`, then commit the drop and what it marks. The commit moves the phase to `close/check` once the document is dropped with its reason: go on with `shared/close.md` from 1. A drop of docs only goes from its verify to the writing of the lessons and backlog items the human picked.

`integrate.sh` refuses a drop without its reason, a plan's drop that changes its items or leaves the spec of one of them approved, and one that changes another spec or plan.
