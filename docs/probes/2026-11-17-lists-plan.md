---
status: draft
inputs: none
---

# Shared lists: a small web app built item by item

The plan the probe of `2026-11-17-plan-probe.md` runs. Written by hand in the format the 0.6.0 design gives a plan; it lands in the probe's repository as `.workflow/plans/lists.md`.

## Why

A real task too large for one spec: three areas a user sees (API, pages, live updates), a schema that changes after data exists, and requirements that only hold when several items are done. It is the case the plan is meant for.

## Final state

One command starts a web server on the local machine. Its home page lists the lists; a list's page shows its items. Every browser on the machine sees the same lists, and a change to a list shows within two seconds in the other browsers open on that list. The data lives in one SQLite file next to the app and survives restarts and upgrades. No accounts: whoever reaches the server can edit.

## Requirements

- F1. Lists: create, rename and delete a list from the home page, which shows every list with its count of unchecked items. — verify: test
- F2. Items: add, edit, check, uncheck and delete the items of a list; checked items sit below unchecked ones. — verify: test
- F3. Everything persists across a restart of the server. — verify: test outside check
- F4. Two browsers on the same list see each other's changes to it, notes included, within 2 s, without reloading. — verify: test outside check; acceptance
- F5. A list exports as Markdown at `/lists/<id>.md`: its name as a heading, one `- [ ]` or `- [x]` line per item; notes stay out. — verify: test
- F6. An item has an optional note, shown under its text and editable in place. — verify: test
- F7. When a request fails, the page says so and keeps what the user typed. — verify: test outside check; acceptance
- N1. A database written by an earlier version opens on start, migrated forward with no data lost. — verify: test; acceptance
- N2. Usable at 360 px wide: no horizontal scroll, every button and checkbox at least 44 × 44 px. — verify: test outside check; acceptance
- N3. From a fresh clone, running the app takes one install command and one start command, and no external service; the tests may need more (Playwright's browsers). — verify: acceptance
- N4. The home page answers in under 200 ms, median of ten requests, with 100 lists of 50 items each, on the machine the plan runs on. — verify: measure

## Out of scope

Accounts, permissions, sharing links per list, access from other devices, live updates of the home page, offline use, reordering by hand, opening a database newer than the code, deployment, a CI.

## Cross-cutting decisions

Proposals: the human confirms or changes them at the plan's checkpoint, and those that outlive the plan become decision records in the task that lands it.

- **D1. TypeScript on Node 24, run without a build** through Node's type stripping; `tsc --noEmit` checks the types, with `erasableSyntaxOnly`, `verbatimModuleSyntax` and `allowImportingTsExtensions`, so that what vitest accepts also runs under `node`. The browser script is JavaScript checked by `tsc` with `// @ts-check` (`allowJs`, `checkJs`): a browser runs no TypeScript. Alternatives: Python with FastAPI; Go. One language for the server, the browser script and the end-to-end tests; the red check is already probed on vitest (`2026-11-09-plugin-and-red-check.md`).
- **D2. Fastify** for the server, listening on localhost. Alternatives: Express; `node:http` with a hand-written router. `inject()` tests a route in-process, with no port, so the API tests stay in `check`.
- **D3. SQLite through `node:sqlite`**, built into Node, at the path in `LISTS_DB` (a default next to the app), so that each test opens its own database; migrations are numbered SQL files applied at start in one transaction, the version in `PRAGMA user_version`. Alternatives: `better-sqlite3` (a native build); a JSON file (no atomic write); Postgres (an external service, against N3).
- **D4. Pages rendered on the server**, with one small vanilla script for actions and live updates; it swaps in the HTML fragments the server renders, so there is one renderer. No build step. Alternatives: a React single-page app (a build, more code); htmx (a dependency for little).
- **D5. Server-sent events**, one stream per list, for F4; each event names what changed, and the page fetches its fragment. A known limit: a browser holds six connections per origin, so many tabs on lists can stall requests. Alternatives: polling every second (simpler, more load, up to a second late); WebSocket (two-way, not needed).
- **D6. Tests**: vitest for units and the API, in `check`; Playwright for the end-to-end tests, in `check_integrate`, starting the real server under `node`; `run_tests` runs vitest with its JUnit reporter. Alternatives: `node:test` (its failure types unmeasured); Cypress (heavier, slower).
- **D7. The README** says how to install, start and use the app; each item updates it in its own diff.

## Unknowns

The first items reduce them.

- `node:sqlite` on Node 24: does it still print an experimental warning, and does that warning disturb the test output or the JUnit XML? Item 1 opens the database to find out.
- Playwright on WSL: are the browser's system libraries there, and how long does `check_integrate` take?
- Server-sent events under Playwright: a deterministic test for "within 2 s", without sleeps.
- Setup on an empty repository followed by the task that brings the stack: the first real use of both.

## Items

- [ ] 1. Skeleton (L estimated): the stack of D1–D6, a server answering `GET /health` with the database's schema version (0), `check` (lint, types, vitest) and `check_integrate` (one Playwright smoke test against the real server) and `run_tests` in the config, the README's install and start; covers N3; closes N3; depends on —
- [ ] 2. Storage and API (L estimated): the migration runner and schema 1, the JSON API for lists and items; covers F1, F2, F3, N1; depends on 1
- [ ] 3. Pages (L estimated): the home page and the list page, using the API, and a script that seeds 100 lists of 50 items; covers F1, F2, F3, N2, N4; closes F1, F2, F3, N4; depends on 2
- [ ] 4. Live updates (L estimated): one event stream per list, applied by the page; covers F4; depends on 3
- [ ] 5. Markdown export (L estimated: a new public URL): covers F5; closes F5; depends on 2
- [ ] 6. Item notes (L estimated: a data migration): schema 2, the API, the page and its events; covers F4, F6, N1; closes F4, F6, N1; depends on 4
- [ ] 7. Failures and small screens (L estimated): the error message that keeps the input, the layout at 360 px; covers F7, N2; closes F7, N2; depends on 6

## Acceptance

Run on main once every item is ticked, in this order.

- [ ] N3: a fresh clone in a new folder; follow only the README; the app runs after one install command and one start command, with no other service.
- [ ] F1, F2: the server running on an empty database; create a list, rename it, add three items, edit one, check one, delete one; each change shows at once, and the checked item sits last.
- [ ] F3: the state of the previous step; stop the server and start it again, reload; everything is as before.
- [ ] F4: the same list open in two windows, one of them private; add an item in the first, check it in the second, add a note in the first; each change appears in the other window within 2 s, with no reload.
- [ ] F5: a list with checked and unchecked items, one with a note; open `/lists/<id>.md`; the Markdown matches the page, without the note.
- [ ] F6, N1: a database written by the commit before item 6's merge: check it out in a temporary worktree, start it with `LISTS_DB` on a new file, create two lists with items, stop it; start the current version on that file; every list and item is there, notes empty; add a note, reload, it stays.
- [ ] F7: the list page open; stop the server, type an item and add it; the page shows an error and keeps the text; start the server, add again; it works.
- [ ] N2: the list page at 360 px wide in the browser's device mode; no horizontal scroll, every button and checkbox at least 44 × 44 px, and easy to use with a thumb.
- [ ] N4: the seed script on a new database; time the home page ten times; the median is under 200 ms.
