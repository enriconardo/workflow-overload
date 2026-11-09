# Brainstorming

Turns the request into an understood problem and a tier the human confirms, without touching a file. It runs on the main branch; the task's branch opens at its end.

1. **Understand.** Restate the request: the problem, the goal, the constraints. Note what is ambiguous, for the questions.
2. **Explore**, always when the task may be L. Skip it only for a request that is plainly S and whose files you already know and have read. Run the `workflow-overload:code-explorer` agent with the restated request and the config's `rules`. It returns a short map with `file:line`: the code to change, who uses it, the rules it touches. Do not read the code it read: its map is what you need.
3. **Ask.** Targeted questions on requirements, edge cases, errors and trade-offs, from the map. One message, the most important first. No code.
4. **Triage.** Propose S or L with one line of reasons; the human confirms or changes it.
   - **S** when all of these hold:
     - nothing a consumer sees changes (public API, observable behavior even if undocumented, such as defaults and error types, dependency ranges), or the change is docs, config or tooling only. A bug fix that brings the behavior back to what the docs or the evident intent say counts as no change; one that has to decide what the behavior should be is L;
     - one package or area, within one chunk: about 6–7 files touched or 10–15 test cases;
     - no data migration, nothing on security (authentication, permissions, secrets);
     - no high uncertainty: clear requirements, known code and dependencies. A dependency upgrade that changes behavior is L.
   - **L**: everything else.

   A task that turns out bigger changes tier later, and the human is told.
5. **Open the branch.** Write the intent to a file outside the repository (your scratchpad, or a temporary file): the problem, the goal, the constraints, the decisions the human took, with their words where they matter. Then:

   ```
   bash <scripts>/branch.sh <S|L> <type> <scope> <description> <intent-file>
   ```

   The type is one of the config's `types`; scope and description are kebab-case, short. If the script refuses, fix the name, not the script.

6. **Go on** with `phases/s-path.md` on S, `phases/l-plan.md` on L. On L, write the explorer's map to a file outside the repository and log its path (`journal.sh log "map: <path>"`): the spec reviewer and the splitter read it.
