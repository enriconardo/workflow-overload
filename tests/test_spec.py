"""Tests of spec.py, the reader of a spec's frontmatter and chunk lines:
`python3 -m unittest discover -s tests`."""

import contextlib
import importlib.util
import io
import os
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


if __name__ == "__main__":
    unittest.main()
