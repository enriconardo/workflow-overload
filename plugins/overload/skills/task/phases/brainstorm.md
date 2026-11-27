# Brainstorming

Turns the request into an understood problem and a tier the human confirms, without touching a file. It runs on the main branch; the task's branch opens at its end.

1. **Understand.** Restate the request: the problem, the goal, the constraints. Note what is ambiguous, for the questions. The **inputs** are the documents the human gives with it: files they name (a brief, a mockup, a sample of a format) and text they paste. Save a pasted input to a file outside the repository, as the intent.
2. **Explore**, unless the request is plainly S: step 4's criteria hold on its face, as for a docs-only change or a small change in files the request names. In doubt, explore. Run the `overload:code-explorer` agent with the restated request, the inputs' paths and the config's `rules`. It returns a short map with `file:line` (the code to change, who uses it, the rules it touches) and the path of the file it saved it to. Do not read the code it read: its map is what you need.

   On a plainly S request, read the files to change yourself, since you will read them to change them anyway, and find their callers with `git grep`. When what you read makes the request no longer plainly S, run the explorer before you ask.
3. **Ask.** Targeted questions on requirements, edge cases, errors and trade-offs, from the map or from what you read. One message, the most important first. No code.
4. **Triage.** Propose S, L or a plan with one line of reasons; the human confirms or changes it.
   - **S** when all of these hold:
     - nothing a consumer sees changes (public API, observable behavior even if undocumented, such as defaults and error types, dependency ranges), or the change is docs, config or tooling only. A bug fix that brings the behavior back to what the docs or the evident intent say counts as no change; one that has to decide what the behavior should be is L;
     - one package or area, within one chunk: about 6–7 files touched or 10–15 test cases;
     - no data migration, nothing on security (authentication, permissions, secrets);
     - no high uncertainty: clear requirements, known code and dependencies. A dependency upgrade that changes behavior is L.
   - **L**: everything else. This task writes its spec, up to the human's approval and its merge; `/overload:build` builds it.
   - **A plan** when the change is too large for one spec: several groups of decisions independent of one another, or several areas a consumer sees. Never from a count of chunks: the splitter counts them from a spec. This task writes the plan; each of its items is then a task of its own. One plan is open at a time: with one open (the status's *open plan*), propose none; tell the human, with its next item, and the request goes as S or L, or waits.

   A task that turns out bigger changes tier later, on the human's go: *Turning L* in `phases/s-path.md` says how.
5. **Open the branch.** Write the intent to a file outside the repository (your scratchpad, or a temporary file): the problem, the goal, the constraints, the decisions the human took, with their words where they matter, and the item of the config's `backlog` the task works, if any, as the file writes it. On S, the intent cites by name the inputs to see as they are (the screenshot of a bug): the code reviewer reads those. Then:

   ```
   bash <scripts>/branch.sh <S|L|P> <name> <intent-file> [--item <plan> <n>] [--map <file>] [--inputs <slug> <file>...]
   ```

   `P` opens a plan. On L or a plan, when the explorer ran, `--map` takes the path of its map: the script keeps it for the spec reviewer and the splitter, and logs it as `map`. The name is short, and follows *Names and messages* in the rules of every task. If the script refuses, change the name, not the script.

   With inputs, choose `<slug>` with the name: on L the spec's name, `<YYYY-MM-DD>-<description>`; on a plan the plan's, the same way; on S the task's. The script copies them into `.workflow/inputs/<slug>/`, and they reach main with the task. Before it runs, tell the human in one line which files will: one they leave out (a private brief on a public repository, a heavy file a link stands for) is not passed, and its content goes in the intent on S, in the spec on L, in the plan on a plan.

6. **Go on** with `phases/s-path.md` on S, `phases/l-plan.md` on L, `phases/plan.md` on a plan.

## An item of the plan

`/overload:task <plan> <n>`, once `plan.sh item` said it can open: the item's intent, in the plan, stands for the request, and the steps above run with these differences.

1. Read the plan in full: the item, the requirements it covers and closes, the unknowns it is to find out, the cross-cutting decisions, the documents it cites. Its inputs are the plan's (its `inputs`, in the plan's folder); the human may give new ones.
2. Explore with the item's intent restated as the request, and the inputs.
3. Ask only what the plan does not say.
4. The tier the plan estimates is the proposal; the human confirms or changes it. Never a plan: an item too large for an L becomes items of its own through a revision of the plan.
5. The intent names the plan, the item and the requirements it covers by ID. Open the branch with `--item <plan> <n>`, which records that this branch works the item: one item at a time. New inputs go in a folder of the item's own name, the spec's on L.
