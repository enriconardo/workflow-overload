"""Tests of spec.py, the reader of a spec's frontmatter and chunk lines and of
a plan: `python3 -m unittest discover -s tests`."""

import contextlib
import importlib.util
import io
import os
import re
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "plugins", "overload", "scripts", "spec.py")
SPEC = importlib.util.spec_from_file_location("spec", SCRIPT)
spec = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(spec)

TEXT = """---
status: approved
branch: feature/greet/default-name
inputs: none
---

# Greet with a default name

## Why
- [ ] 9. not a chunk: outside *Chunks*

## Chunks
- [x] 1. Name type (no test-first): src/name.ts; cases: none
- [ ] 2. Default name (test-first): src/greet.ts; cases: 1, 2; signatures: greet(name?)
- [ ] 3. Store (test-first): src/store.ts; cases: 3; dependencies: better-sqlite3
- [ ] 4. Greeting (in full) (test-first): src/greet.ts; cases: 4
- [ ] 5. More cases (tests only): tests/greet.test.ts; cases: 5, 6
- [ ] 6. README (no test-first): README.md
- [ ] 7. Mockup (test-first): src/page.ts; cases: 7; inputs: .workflow/inputs/x/mock.png; signatures: none

## Notes
- [ ] 8. not a chunk either
"""


def run(*args):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = spec.main(list(args))
    return code, out.getvalue(), err.getvalue()


class ChunksTest(unittest.TestCase):
    def test_each_chunk_with_its_state_type_and_first_step(self):
        chunks = spec.chunks(TEXT)
        self.assertEqual(
            [(c.number, c.done, c.type, c.first_step) for c in chunks],
            [
                (1, True, "no-test-first", "implement"),
                (2, False, "test-first", "stub"),
                (3, False, "test-first", "stub"),
                (4, False, "test-first", "test"),
                (5, False, "tests-only", "test"),
                (6, False, "no-test-first", "implement"),
                (7, False, "test-first", "test"),
            ],
        )

    def test_a_line_without_a_type_is_refused(self):
        with self.assertRaisesRegex(spec.SpecError, "chunk 1 has no type"):
            spec.chunks("## Chunks\n- [ ] 1. Something: a.ts\n")

    def test_a_number_given_twice_is_refused(self):
        with self.assertRaisesRegex(spec.SpecError, "chunk 1 is numbered twice"):
            spec.chunks("## Chunks\n- [ ] 1. A (test-first): a\n- [x] 1. B (test-first): b\n")

    def test_a_spec_without_chunks_has_none(self):
        self.assertEqual(spec.chunks("---\nstatus: draft\n---\n\n# x\n"), [])

    def test_the_status_comes_from_the_frontmatter_only(self):
        self.assertEqual(spec.status(TEXT), "approved")
        self.assertEqual(spec.status("# x\n\nstatus: done\n"), "")

    def test_depends_on_lists_the_files_of_the_frontmatter(self):
        self.assertEqual(
            spec.depends_on("---\nstatus: approved\ndepends_on: src/a.ts,  src/b.ts ,docs/\n---\n# x\n"),
            ["src/a.ts", "src/b.ts", "docs/"],
        )
        self.assertEqual(spec.depends_on("---\ndepends_on: none\n---\n"), [])
        self.assertEqual(spec.depends_on("---\nstatus: approved\n---\n"), [])
        self.assertEqual(spec.depends_on("# x\n\ndepends_on: a.ts\n"), [])


def approved(chunks, status="approved"):
    return "---\nstatus: %s\n---\n\n# x\n\n## Chunks\n%s" % (status, "".join(line + "\n" for line in chunks))


class ReadyTest(unittest.TestCase):
    def test_only_approved_specs_with_a_chunk_left_are_ready(self):
        specs = {
            "a.md": approved(["- [x] 1. A (test-first): a", "- [ ] 2. B (test-first): b"]),
            "b.md": approved(["- [x] 1. A (test-first): a"]),
            "c.md": approved(["- [x] 1. A (test-first): a"], "done"),
            "d.md": approved(["- [ ] 1. A (test-first): a"], "dropped"),
            "e.md": approved(["- [ ] 1. A (test-first): a"], "draft"),
            "f.md": approved(["- [ ] 1. A: a"]),
        }
        with tempfile.TemporaryDirectory() as work:
            paths = []
            for name, text in sorted(specs.items()):
                paths.append(os.path.join(work, name))
                with open(paths[-1], "w", encoding="utf-8") as handle:
                    handle.write(text)
            code, out, _ = run("ready", *paths)
        self.assertEqual(code, 0)
        self.assertEqual(
            out.splitlines(),
            [
                "%s\t1 of 2 chunks open" % paths[0],
                "%s\tunreadable: chunk 1 has no type: (test-first), (no test-first) or (tests only)" % paths[5],
            ],
        )

    def test_none_ready_prints_nothing(self):
        code, out, _ = run("ready")
        self.assertEqual((code, out), (0, ""))


class MainTest(unittest.TestCase):
    def test_chunks_prints_a_line_per_chunk(self):
        with tempfile.TemporaryDirectory() as work:
            path = os.path.join(work, "s.md")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(TEXT)
            code, out, _ = run("chunks", path)
            self.assertEqual(code, 0)
            self.assertEqual(out.splitlines()[:2], ["1\tdone\tno-test-first\timplement", "2\topen\ttest-first\tstub"])
            code, out, _ = run("status", path)
            self.assertEqual((code, out), (0, "approved\n"))
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("---\ndepends_on: a.ts, b.ts\n---\n")
            code, out, _ = run("depends", path)
            self.assertEqual((code, out), (0, "a.ts\nb.ts\n"))

    def test_a_refusal_names_the_file(self):
        with tempfile.TemporaryDirectory() as work:
            path = os.path.join(work, "s.md")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("## Chunks\n- [ ] 1. A: a\n")
            code, out, err = run("chunks", path)
            self.assertEqual((code, out), (1, ""))
            self.assertIn("s.md: chunk 1 has no type", err)


# The plan of the 2026-11-17 probe, in the format 0.6.0 gives a plan: the
# requirements by area, an S item, a step of no requirement.
PLAN = """---
status: approved
inputs: none
---

# Shared lists: a small web app built item by item

## Why
A real task too large for one spec.

## Final state
One command starts a web server; every browser on the machine sees the same lists.

## Requirements

Each verified as it says.

### Lists
- LIST-01. Create, rename and delete a list from the home page. — verify: test
- LIST-02. Add, edit, check and delete the items of a list. — verify: test
- LIST-03. Everything persists across a restart. — verify: test outside check

### Live updates
- LIVE-01. Two browsers on a list see each other's changes within 2 s. — verify: test outside check; acceptance

### Export
- EXP-01. A list exports as Markdown at `/lists/<id>.md`. — verify: test

### Operations
- OPS-01. A database of an earlier version opens, migrated forward. — verify: test, acceptance
- OPS-02. A fresh clone runs with one install and one start command. — verify: acceptance
- OPS-03. The home page answers in under 200 ms with 100 lists. — verify: measure

## Out of scope
Accounts; deployment.

## Cross-cutting decisions
- **D1. TypeScript on Node 24.** Alternatives: Python; Go.

## Unknowns
- Playwright on WSL (covers nothing; depends on nothing).

## Items
- [x] 1. Skeleton (L estimated): the stack, `GET /health` (schema 0); covers OPS-02; closes OPS-02; depends on —
- [x] 2. Storage and API (L estimated): schema 1, the JSON API; covers LIST-01, LIST-02, LIST-03, OPS-01; depends on 1
- [ ] 3. Pages (home and list) (L estimated): covers LIST-01, LIST-02, LIST-03, OPS-03; closes LIST-01, LIST-02, LIST-03; depends on 2
- [ ] 4. Live updates (L estimated): one event stream per list; covers LIVE-01; depends on 3
- [ ] 5. Markdown export (S estimated: one route on the renderer): covers EXP-01; depends on 2
- [ ] 6. Item notes (L estimated: a data migration): schema 2; covers LIVE-01, OPS-01; closes LIVE-01, OPS-01; depends on 4, 5

## Acceptance

Run on main once every item is ticked, in this order.

- [x] OPS-02: a fresh clone in a new folder; follow only the README; the app runs after one install and one start command.
- [ ] LIVE-01: the same list open in two windows; add an item in the first; it shows in the second within 2 s. — failed: it showed after a reload only
- [ ] OPS-01, LIST-03: a database written by the commit before item 6's merge; start the current version on it; every list is there.
- [ ] OPS-03: the seed script on a new database; time the home page ten times; the median is under 200 ms.
- [ ] the last item merged and pushed; open the CI run of main; it is green.
"""


def plan_with(old, new, text=PLAN):
    """The plan with a line of it replaced; refuses a line it lacks."""
    assert old in text, old
    return text.replace(old, new, 1)


def problems(text):
    try:
        spec.plan(text)
    except spec.SpecError as error:
        return error.problems
    return []


class PlanTest(unittest.TestCase):
    def test_the_requirements_by_area_with_their_ways(self):
        found = spec.plan(PLAN)
        self.assertEqual(found.status, "approved")
        self.assertEqual(
            [(r.id, r.area, r.verify) for r in found.requirements][3:6],
            [
                ("LIVE-01", "Live updates", ["test outside check", "acceptance"]),
                ("EXP-01", "Export", ["test"]),
                ("OPS-01", "Operations", ["test", "acceptance"]),
            ],
        )

    def test_the_items_with_tier_coverage_and_dependencies(self):
        found = spec.plan(PLAN)
        self.assertEqual(
            [(i.number, i.done, i.tier, i.title, i.covers, i.closes, i.depends) for i in found.items][2:],
            [
                (3, False, "L", "Pages (home and list)", ["LIST-01", "LIST-02", "LIST-03", "OPS-03"],
                 ["LIST-01", "LIST-02", "LIST-03"], [2]),
                (4, False, "L", "Live updates", ["LIVE-01"], [], [3]),
                (5, False, "S", "Markdown export", ["EXP-01"], [], [2]),
                (6, False, "L", "Item notes", ["LIVE-01", "OPS-01"], ["LIVE-01", "OPS-01"], [4, 5]),
            ],
        )
        self.assertEqual(found.items[0].depends, [])

    def test_the_steps_with_their_outcome(self):
        found = spec.plan(PLAN)
        self.assertEqual(
            [(s.number, s.done, s.failed, s.ids) for s in found.steps],
            [
                (1, True, False, ["OPS-02"]),
                (2, False, True, ["LIVE-01"]),
                (3, False, False, ["OPS-01", "LIST-03"]),
                (4, False, False, ["OPS-03"]),
                (5, False, False, []),
            ],
        )

    def test_a_line_out_of_format_is_refused(self):
        cases = [
            ("- LIST-01. Create, rename and delete a list from the home page. — verify: test",
             "- LIST-1. Create a list. — verify: test", "requirement out of format"),
            ("- EXP-01. A list exports as Markdown at `/lists/<id>.md`. — verify: test",
             "- EXP-01. A list exports as Markdown. — verify: by hand", "EXP-01: verify 'by hand' is none of"),
            ("- [ ] 4. Live updates (L estimated)", "- [ ] 4. Live updates (L)", "item 4 has no tier"),
            ("- [ ] 4. Live updates", "- [ ] Live updates", "item out of format"),
            ("- [ ] 4. Live updates", "- [ ] 3. Live updates", "item 3 is numbered twice"),
            ("covers LIVE-01; depends on 3", "covers LIVE-01; depends on three", "item 4 depends on 'three'"),
            ("covers EXP-01; depends on 2", "covers EXP-1; depends on 2", "item 5 covers: 'EXP-1' is not a list"),
            ("- [ ] OPS-03: the seed", "- [ ] OPS-3: the seed", "acceptance step 4: its requirements are not"),
            ("- [ ] OPS-03: the seed script on a new database; time the home page ten times; the median",
             "- [ ] OPS-03: the seed script; the median", "acceptance step 4 has no preconditions"),
            ("- [ ] the last item", "- the last item", "acceptance step out of format"),
            ("- [ ] LIVE-01: the same", "- [x] LIVE-01: the same", "acceptance step 2 is ticked and failed"),
            ("status: approved", "status: open", "status 'open' is none of draft, approved, done, dropped"),
        ]
        for old, new, problem in cases:
            with self.subTest(new):
                found = problems(plan_with(old, new))
                self.assertTrue(any(problem in one for one in found), found)

    def test_an_area_holds_one_prefix_of_its_own(self):
        text = plan_with("- EXP-01. A list", "- LIST-04. A list")
        self.assertIn("area Export holds IDs of EXP, LIST", "\n".join(problems(plan_with("### Export\n", "### Export\n- EXP-02. x — verify: test\n", text))))
        self.assertIn("prefix LIST is in areas Export, Lists", "\n".join(problems(text)))
        text = plan_with("### Lists\n", "")
        self.assertIn("LIST-01 is under no area", "\n".join(problems(text)))

    def test_ids_coverage_and_dependencies_are_checked(self):
        cases = [
            ("covers EXP-01;", "covers EXP-01, EXP-02;", "item 5 names EXP-02, no requirement of the plan"),
            ("covers LIVE-01; depends on 3", "closes LIVE-01; depends on 3", "item 4 closes LIVE-01 without covering it"),
            ("covers LIVE-01; depends on 3", "covers LIVE-01; closes LIVE-01; depends on 3", "LIVE-01 is closed by items 4, 6"),
            ("closes LIVE-01, OPS-01;", "closes OPS-01;", "LIVE-01 is covered by items 4, 6 and closed by none"),
            ("covers EXP-01; depends on 2", "depends on 2", "EXP-01 is covered by no item"),
            ("depends on 4, 5", "depends on 4, 9", "item 6 depends on item 9, which the plan lacks"),
            ("depends on 4, 5", "depends on 6", "item 6 depends on itself"),
            ("one event stream per list; covers LIVE-01; depends on 3", "covers LIVE-01; depends on 6",
             "depends on itself through other items"),
            ("- [ ] OPS-03: the seed", "- [ ] OPS-04: the seed", "acceptance step 4 names OPS-04"),
            ("- [ ] OPS-03: the seed", "- [ ] OPS-02: the seed", "OPS-03 is verified by measure and has no acceptance step"),
        ]
        for old, new, problem in cases:
            with self.subTest(new):
                found = problems(plan_with(old, new))
                self.assertTrue(any(problem in one for one in found), found)

    def test_a_draft_has_nothing_ticked_and_a_done_plan_everything(self):
        self.assertIn("a draft plan has no item ticked and no step run", problems(plan_with("status: approved", "status: draft")))
        self.assertIn("a done plan has every item ticked and every step passed", problems(plan_with("status: approved", "status: done")))
        done = re.sub(r"- \[ \]", "- [x]", plan_with(" — failed: it showed after a reload only", "", plan_with("status: approved", "status: done")))
        self.assertEqual(problems(done), [])

    def test_every_problem_is_reported_at_once(self):
        found = problems(plan_with("depends on 4, 5", "depends on 9", plan_with("verify: measure", "verify: guess")))
        self.assertEqual(len(found), 2, found)

    def test_a_plan_without_requirements_or_items_is_refused(self):
        self.assertEqual(
            problems("---\nstatus: draft\n---\n\n# x\n"),
            ["no requirement under ## Requirements", "no item under ## Items"],
        )

    def test_the_probe_plan_is_refused_for_its_ids(self):
        # The probe's plan stays as it ran, with the F and N IDs 0.6.0 dropped.
        with open(os.path.join(HERE, "..", "docs", "probes", "2026-11-17-lists-plan.md"), encoding="utf-8") as handle:
            found = problems(handle.read())
        self.assertIn("requirement out of format", found[0])


def item_spec(status, item, plan=".workflow/plans/lists.md"):
    return "---\nstatus: %s\nplan: %s\nitem: %s\n---\n# x\n" % (status, plan, item)


class LinkTest(unittest.TestCase):
    def test_a_spec_names_its_plan_and_item(self):
        self.assertEqual(spec.link(item_spec("approved", 3)), (".workflow/plans/lists.md", 3))
        self.assertIsNone(spec.link("---\nstatus: approved\n---\n"))

    def test_a_link_out_of_format_is_refused(self):
        for text, problem in [
            ("---\nplan: .workflow/plans/lists.md\n---\n", "names both"),
            ("---\nitem: 3\n---\n", "names both"),
            (item_spec("approved", 3, "plans/lists.md"), "is not .workflow/plans/<name>.md"),
            (item_spec("approved", "three"), "item: three is not an item's number"),
            (item_spec("approved", 0), "item: 0 is not an item's number"),
        ]:
            with self.subTest(text):
                with self.assertRaisesRegex(spec.SpecError, re.escape(problem)):
                    spec.link(text)

    def test_an_item_is_started_by_an_approved_or_done_spec_of_its_plan(self):
        specs = [
            item_spec("approved", 3),
            item_spec("done", 4, "./.workflow/plans/lists.md"),
            item_spec("dropped", 5),
            item_spec("draft", 6),
            item_spec("approved", 6, ".workflow/plans/other.md"),
            item_spec("approved", 1),
            "---\nstatus: approved\n---\n",
        ]
        self.assertEqual(
            spec.item_states(spec.plan(PLAN), ".workflow/plans/lists.md", [("s%d.md" % n, text) for n, text in enumerate(specs)]),
            {1: "done", 2: "done", 3: "started", 4: "started", 5: "open", 6: "open"},
        )


class RevisionTest(unittest.TestCase):
    def revise(self, new):
        return spec.revision(spec.plan(PLAN), spec.plan(new))

    def test_a_revision_lists_the_items_it_adds_removes_or_changes(self):
        new = plan_with("depends on 4, 5", "depends on 4, 5, 7", PLAN)
        new = plan_with("- [ ] 5. Markdown export", "- [ ] 7. CSV export (S estimated): depends on 2\n- [ ] 5. Markdown export", new)
        new = plan_with("one event stream per list", "one event stream per list, notes included", new)
        self.assertEqual(self.revise(new), [(4, "changed"), (6, "changed"), (7, "added")])
        removed = plan_with("- [ ] 5. Markdown export (S estimated: one route on the renderer): covers EXP-01; depends on 2\n", "", PLAN)
        removed = plan_with("covers LIVE-01; depends on 3", "covers LIVE-01, EXP-01; depends on 3", removed)
        removed = plan_with("depends on 4, 5", "depends on 4", removed)
        self.assertEqual(self.revise(removed), [(4, "changed"), (5, "removed"), (6, "changed")])

    def test_a_new_item_takes_the_next_free_number(self):
        split = plan_with("- [ ] 6. Item notes", "- [ ] 8. Notes in the page (S estimated): depends on 7\n- [ ] 7. Notes in the API (S estimated): depends on 2\n- [ ] 6. Item notes")
        self.assertEqual(self.revise(split), [(7, "added"), (8, "added")])
        with self.assertRaisesRegex(spec.SpecError, "item 8 is new: the new items take 7 and on, one after the other"):
            self.revise(plan_with("- [ ] 7. Notes in the API (S estimated): depends on 2\n", "", plan_with("depends on 7", "depends on 2", split)))
        without_5 = plan_with("- [ ] 5. Markdown export (S estimated: one route on the renderer): covers EXP-01; depends on 2\n", "")
        without_5 = plan_with("covers LIVE-01; depends on 3", "covers LIVE-01, EXP-01; depends on 3", plan_with("depends on 4, 5", "depends on 4", without_5))
        with self.assertRaisesRegex(spec.SpecError, "item 5 is new: the new items take 7 and on, one after the other"):
            spec.revision(spec.plan(without_5), spec.plan(PLAN))

    def test_a_ticked_item_stays_as_it_is(self):
        with self.assertRaisesRegex(spec.SpecError, "item 2 is ticked and the revision changes it"):
            self.revise(plan_with("- [x] 2. Storage", "- [ ] 2. Storage"))
        with self.assertRaisesRegex(spec.SpecError, "item 1 is ticked and the revision changes it"):
            self.revise(plan_with("`GET /health` (schema 0)", "`GET /health`"))


def write(work, name, text):
    path = os.path.join(work, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return path


class PlanMainTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(self.work))
        self.cwd = os.getcwd()
        os.chdir(self.work)
        self.addCleanup(os.chdir, self.cwd)
        write(self.work, ".workflow/plans/lists.md", PLAN)

    def test_check_prints_the_plans_counts(self):
        self.assertEqual(
            run("check", ".workflow/plans/lists.md"),
            (0, "8 requirements, 6 items (2 ticked), 5 acceptance steps (1 passed)\n", ""),
        )

    def test_a_plan_out_of_format_prints_each_problem_with_its_path(self):
        write(self.work, "bad.md", plan_with("depends on 4, 5", "depends on 9", plan_with("verify: measure", "verify: guess")))
        for command in ("check", "items", "steps"):
            code, out, err = run(command, "bad.md")
            self.assertEqual((code, out), (1, ""))
            self.assertEqual(
                err.splitlines(),
                [
                    "spec.py: bad.md: OPS-03: verify 'guess' is none of test, test outside check, acceptance, measure",
                    "spec.py: bad.md: item 6 depends on item 9, which the plan lacks",
                ],
            )

    def test_items_prints_each_item_with_its_state(self):
        write(self.work, ".workflow/specs/pages.md", item_spec("approved", 3))
        code, out, _ = run("items", ".workflow/plans/lists.md", ".workflow/specs/pages.md")
        self.assertEqual(code, 0)
        self.assertEqual(
            out.splitlines(),
            [
                "1\tdone\tL\t-\tSkeleton",
                "2\tdone\tL\t1\tStorage and API",
                "3\tstarted\tL\t2\tPages (home and list)",
                "4\topen\tL\t3\tLive updates",
                "5\topen\tS\t2\tMarkdown export",
                "6\topen\tL\t4,5\tItem notes",
            ],
        )

    def test_items_refuses_a_spec_whose_link_is_out_of_format(self):
        write(self.work, "s.md", "---\nitem: 3\n---\n")
        code, out, err = run("items", ".workflow/plans/lists.md", "s.md")
        self.assertEqual((code, out), (1, ""))
        self.assertIn("spec.py: s.md: a spec of a plan's item names both", err)

    def test_steps_prints_each_step_with_its_outcome(self):
        self.assertEqual(
            run("steps", ".workflow/plans/lists.md"),
            (0, "1\tpassed\tOPS-02\n2\tfailed\tLIVE-01\n3\topen\tOPS-01,LIST-03\n4\topen\tOPS-03\n5\topen\t-\n", ""),
        )

    def test_link_prints_the_plan_and_item(self):
        write(self.work, "s.md", item_spec("approved", 3))
        write(self.work, "t.md", "---\nstatus: approved\n---\n")
        self.assertEqual(run("link", "s.md"), (0, ".workflow/plans/lists.md\t3\n", ""))
        self.assertEqual(run("link", "t.md"), (0, "", ""))

    def test_revision_prints_the_changes_or_names_the_plan_it_refuses(self):
        write(self.work, "new.md", plan_with("one event stream per list", "one stream per list"))
        self.assertEqual(run("revision", ".workflow/plans/lists.md", "new.md"), (0, "4\tchanged\n", ""))
        write(self.work, "new.md", plan_with("- [x] 2. Storage", "- [ ] 2. Storage"))
        self.assertEqual(
            run("revision", ".workflow/plans/lists.md", "new.md"),
            (1, "", "spec.py: new.md: item 2 is ticked and the revision changes it\n"),
        )
        write(self.work, "new.md", plan_with("depends on 4, 5", "depends on 9"))
        code, _, err = run("revision", ".workflow/plans/lists.md", "new.md")
        self.assertEqual((code, err), (1, "spec.py: new.md: item 6 depends on item 9, which the plan lacks\n"))

    def test_items_takes_an_item_started_on_a_branch(self):
        code, out, _ = run("items", ".workflow/plans/lists.md", "--started", "5")
        self.assertEqual((code, out.splitlines()[4]), (0, "5\tstarted\tS\t2\tMarkdown export"))

    def test_next_is_the_started_item_with_its_spec(self):
        write(self.work, ".workflow/specs/pages.md", item_spec("approved", 3))
        self.assertEqual(
            run("next", ".workflow/plans/lists.md", ".workflow/specs/pages.md"),
            (0, "3\tstarted\tL\t.workflow/specs/pages.md\tPages (home and list)\n", ""),
        )
        self.assertEqual(
            run("next", ".workflow/plans/lists.md", "--started", "5"),
            (0, "5\tstarted\tS\t-\tMarkdown export\n", ""),
        )

    def test_next_is_else_the_first_open_item_whose_dependencies_are_ticked(self):
        self.assertEqual(run("next", ".workflow/plans/lists.md"), (0, "3\topen\tL\t-\tPages (home and list)\n", ""))
        write(self.work, ".workflow/plans/lists.md", plan_with("- [ ] 3. Pages", "- [x] 3. Pages"))
        self.assertEqual(run("next", ".workflow/plans/lists.md"), (0, "4\topen\tL\t-\tLive updates\n", ""))

    def test_next_says_acceptance_once_every_item_is_ticked(self):
        write(self.work, ".workflow/plans/lists.md", re.sub(r"(?m)^- \[ \] (\d)\.", r"- [x] \1.", PLAN))
        self.assertEqual(run("next", ".workflow/plans/lists.md"), (0, "acceptance\n", ""))

    def test_opens_prints_an_item_that_can_open(self):
        self.assertEqual(run("opens", ".workflow/plans/lists.md", "5"), (0, "5\tS\tMarkdown export\n", ""))
        self.assertEqual(run("opens", ".workflow/plans/lists.md", "3"), (0, "3\tL\tPages (home and list)\n", ""))

    def test_opens_refuses_an_item_that_cannot(self):
        write(self.work, ".workflow/specs/pages.md", item_spec("approved", 3))
        cases = [
            (("9",), "item 9 is not in the plan"),
            (("2",), "item 2 is ticked already"),
            (("4",), "item 4 depends on item 3, not ticked yet"),
            (("6",), "item 6 depends on items 4, 5, not ticked yet"),
            (("3", ".workflow/specs/pages.md"), "item 3 has its spec approved, .workflow/specs/pages.md: /overload:build builds it"),
            (("5", ".workflow/specs/pages.md"), "item 3 is started and not ticked: one item at a time"),
            (("5", "--started", "3"), "item 3 is started and not ticked: one item at a time"),
            (("x",), "x is not an item's number"),
        ]
        for args, problem in cases:
            with self.subTest(args):
                self.assertEqual(
                    run("opens", ".workflow/plans/lists.md", *args),
                    (1, "", "spec.py: .workflow/plans/lists.md: %s\n" % problem),
                )
        self.assertEqual(run("opens", ".workflow/plans/lists.md", "5", "--started", "5")[0], 0)

    def test_a_command_with_the_wrong_arguments_prints_the_usage(self):
        for args in [(), ("plan",), ("check",), ("items",), ("next",), ("opens", "a.md"), ("items", "a.md", "--started"),
                     ("revision", "a.md"), ("status", "a.md", "b.md")]:
            with self.subTest(args):
                code, _, err = run(*args)
                self.assertEqual(code, 2)
                self.assertIn("Usage: spec.py", err)


if __name__ == "__main__":
    unittest.main()
