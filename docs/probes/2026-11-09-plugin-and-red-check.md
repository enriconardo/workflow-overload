# Probe: plugin scripts and the red check

2026-11-09. Claude Code 2.1.319, vitest 4.1.11, Node 22, Chromium from Playwright. All in throwaway folders.

## Plugin

A probe plugin named `overload` (since renamed `workflow-overload`: `/overload` then resolves to `/workflow-overload:overload`, checked the same day) in a local marketplace, installed with `claude plugin marketplace add` and `claude plugin install` in a separate config, used from another git repository.

| Question | Result |
| --- | --- |
| Does the skill reach the plugin's scripts from another repository? | Yes. `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_SKILL_DIR}` are substituted with absolute paths in the skill's text; the script runs with the project as its working directory. |
| Inside a script? | `CLAUDE_PLUGIN_ROOT` is **not** set in the model's Bash. A script finds its files from `BASH_SOURCE`. Hooks do get the variable. |
| `` !`command` `` in a skill | Works: its output lands in the skill's text before the model reads it. |
| Permissions | The `` !`command` `` of a skill needs Bash permission like any command: without it the skill fails to load ("requires approval"). The skill's `allowed-tools` grants it, with `${CLAUDE_PLUGIN_ROOT}` substituted, for the command written unquoted: `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh)`. The same holds for the model's own runs of a script, `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh:*)`; a script left out of the list still asks. |
| Phase files | `${CLAUDE_SKILL_DIR}/phases/<phase>.md` reads with Read. |
| `/overload <request>` | Works, resolved to `/overload:overload`; the full form works too. `$ARGUMENTS` arrives whole. |
| Does the skill trigger on its own? | No. With `disable-model-invocation: true` the model does not even see it: asked in words to "use the overload workflow", it answered that no such skill exists. |
| Agents | Named `overload:<name>` and **visible** to the model; with a description saying "internal to /overload" it did not use one on its own. The agent's `model:` is honored. |
| Hooks | A plugin's `UserPromptSubmit` hook runs in every session; `[[ -f .workflow/journal.md ]] \|\| exit 0` keeps it silent without a journal. |

So the scripts ship in the plugin, with no npm package.

## Red check on vitest

Vitest's JUnit XML does **not** separate assertion from error: it never writes `<error>`, every case is a `<failure>`, and `errors="0"` always. The distinction is elsewhere:

- **Load error** (missing module, exception at load, syntax error, exception in `describe` or `beforeAll`): a `<testcase>` whose `name` is the file's path, equal to its `classname`. With a failing hook the real tests show as `<skipped/>`.
- **Failure inside a test**: the `type` attribute of `<failure>` is the error's class: `AssertionError` (`node:assert` too), `NotImplemented` for a stub, `TypeError` or `Error` for a runtime error.

| Case | Node | Browser (Chromium) |
| --- | --- | --- |
| `expect(2).toBe(3)` | `AssertionError` | same |
| stub throwing `NotImplemented` | `NotImplemented` | same |
| missing module | file-level testcase | file-level, "Failed to import" |
| missing export | **`TypeError`** (`x is not a function`) | file-level, "Failed to import" |
| exception at load, syntax error | file-level testcase | file-level |
| `describe` or `beforeAll` throwing | file-level testcase, tests skipped | — |
| `expect(() => stub()).toThrow()` | **passes** | **passes** |
| unhandled rejection | test passes in the XML, exit 1, error **absent** from the XML | — |

The rule for each file of a recorded suite:

1. the file appears in the XML, and none of its testcases is named after the file;
2. every recorded testcase fails: a green or skipped one is not a valid red (this also catches `toThrow()` with no argument, which passes on a stub);
3. the failure's `type` is in an allowed list, `AssertionError, NotImplemented` by default, configurable per runner. A `TypeError` is refused: in Node it means a missing export, a stub not written.

Green stays the exit code's call, not the XML's: an unhandled error exits 1 without appearing in it. Other runners (jest, pytest, go) need the same probe when a project adopts them.
