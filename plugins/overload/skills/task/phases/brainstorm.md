# Brainstorming

Turns the request into an understood problem and a tier the human confirms, without touching a file. It runs on the main branch; the task's branch opens at its end.

1. **Understand.** Restate the request: the problem, the goal, the constraints. Note what is ambiguous, for the questions. The **inputs** are the documents the human gives with it: files they name (a brief, a mockup, a sample of a format) and text they paste. Save a pasted input to a file outside the repository, as the intent.
2. **Explore**, unless the request is plainly S: step 4's criteria hold on its face, as for a docs-only change or a small change in files the request names. In doubt, explore. Run the `overload:code-explorer` agent with the restated request, the inputs' paths and the config's `rules`. It returns a short map with `file:line` (the code to change, who uses it, the rules it touches) and the path of the file it saved it to. Do not read the code it read: its map is what you need.

   On a plainly S request, read the files to change yourself, since you will read them to change them anyway, and find their callers with `git grep`. When what you read makes the request no longer plainly S, run the explorer before you ask.
3. **Ask.** Targeted questions on requirements, edge cases, errors and trade-offs, from the map or from what you read. One message, the most important first. No code.
4. **Triage.** Propose S or L with one line of reasons; the human confirms or changes it.
   - **S** when all of these hold:
     - nothing a consumer sees changes (public API, observable behavior even if undocumented, such as defaults and error types, dependency ranges), or the change is docs, config or tooling only. A bug fix that brings the behavior back to what the docs or the evident intent say counts as no change; one that has to decide what the behavior should be is L;
     - one package or area, within one chunk: about 6–7 files touched or 10–15 test cases;
     - no data migration, nothing on security (authentication, permissions, secrets);
     - no high uncertainty: clear requirements, known code and dependencies. A dependency upgrade that changes behavior is L.
   - **L**: everything else.

   A task that turns out bigger changes tier later, on the human's go: *Turning L* in `phases/s-path.md` says how.
5. **Open the branch.** Write the intent to a file outside the repository (your scratchpad, or a temporary file): the problem, the goal, the constraints, the decisions the human took, with their words where they matter, and the item of the config's `backlog` the task works, if any, as the file writes it. On S, the intent cites by name the inputs to see as they are (the screenshot of a bug): the code reviewer reads those. Then:

   ```
   bash <scripts>/branch.sh <S|L> <name> <intent-file> [--map <file>] [--inputs <slug> <file>...]
   ```

   On L, when the explorer ran, `--map` takes the path of its map: the script keeps it for the spec reviewer and the splitter, and logs it as `map`. The name is short, and follows *Names and messages* in the rules of every task. If the script refuses, change the name, not the script.

   With inputs, choose `<slug>` with the name: on L the spec's name, `<YYYY-MM-DD>-<description>`; on S the task's. The script copies them into `.workflow/inputs/<slug>/`, and they reach main with the task. Before it runs, tell the human in one line which files will: one they leave out (a private brief on a public repository, a heavy file a link stands for) is not passed, and its content goes in the intent on S, in the spec on L.

6. **Go on** with `phases/s-path.md` on S, `phases/l-plan.md` on L.
