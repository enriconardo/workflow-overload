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
