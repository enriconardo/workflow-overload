# Brainstorming

Turns the request into an understood problem and a tier the human confirms, without touching a file. It runs on the main branch; the task's branch opens at its end.

1. **Understand.** Restate the request: the problem, the goal, the constraints. Note what is ambiguous, for the questions.
2. **Explore**, unless the request is plainly S: step 4's criteria hold on its face, as for a docs-only change or a small change in files the request names. In doubt, explore. Run the `workflow-overload:code-explorer` agent with the restated request and the config's `rules`. It returns a short map with `file:line`: the code to change, who uses it, the rules it touches. Do not read the code it read: its map is what you need.

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
5. **Open the branch.** Write the intent to a file outside the repository (your scratchpad, or a temporary file): the problem, the goal, the constraints, the decisions the human took, with their words where they matter. Then:

   ```
   bash <scripts>/branch.sh <S|L> <name> <intent-file>
   ```

   The name is short, and follows *Names and messages* in the skill's rules. If the script refuses, change the name, not the script.

6. **Go on** with `phases/s-path.md` on S, `phases/l-plan.md` on L. On L, write the explorer's map, when it ran, to a file outside the repository and log its path (`journal.sh log "map: <path>"`): the spec reviewer and the splitter read it.
