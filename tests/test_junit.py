"""Tests of junit.py on the JUnit XML of real runners: `python3 -m unittest
discover -s tests`. The pytest report is pytest 9.2's, from
`pytest --continue-on-collection-errors --junitxml=/dev/stdout`, cut to the
elements junit.py reads."""

import contextlib
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("junit", os.path.join(HERE, "..", "plugins", "overload", "scripts", "junit.py"))
junit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(junit)

PYTEST = """<?xml version="1.0" encoding="utf-8"?><testsuites name="pytest tests"><testsuite name="pytest" errors="1" failures="4" skipped="0" tests="6">\
<testcase classname="" name="tests.test_b" time="0.000"><error message="collection failure">ImportError while importing test module 'tests/test_b.py'.
tests/test_b.py:1: in &lt;module&gt;
    import missing_module
E   ModuleNotFoundError: No module named 'missing_module'</error></testcase>\
<testcase classname="tests.test_a" name="test_assert" time="0.000"><failure message="assert 1 == 2">def test_assert():
&gt;       assert 1 == 2
E       assert 1 == 2

tests/test_a.py:5: AssertionError</failure></testcase>\
<testcase classname="tests.test_a" name="test_stub" time="0.000"><failure message="NotImplementedError">def test_stub():
&gt;       stub()

tests/test_a.py:8:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

    def stub():
&gt;       raise NotImplementedError
E       NotImplementedError

tests/test_a.py:2: NotImplementedError</failure></testcase>\
<testcase classname="tests.test_a" name="test_ok" time="0.000" />\
<testcase classname="tests.test_c" name="test_custom" time="0.000"><failure message="test_c.Custom: a: b">def test_custom():
&gt;       raise Custom("a: b")
E       test_c.Custom: a: b

tests/test_c.py:3: Custom</failure></testcase>\
<testcase classname="tests.test_c" name="test_type" time="0.000"><failure message="TypeError: 'NoneType' object is not callable">def test_type():
&gt;       None()
E       TypeError: 'NoneType' object is not callable

tests/test_c.py:5: TypeError</failure></testcase></testsuite></testsuites>"""

TYPES = {"AssertionError", "NotImplementedError"}


class PytestTest(unittest.TestCase):
    def judge(self, *files):
        return junit.judge(PYTEST, list(files), TYPES)

    def test_reads_the_type_from_the_last_line_of_the_failure(self):
        problems, lines, green = self.judge("tests/test_a.py")
        self.assertEqual(problems, [], lines)
        self.assertIn("tests/test_a.py > test_assert: red, AssertionError", lines)
        self.assertIn("tests/test_a.py > test_stub: red, NotImplementedError", lines)
        self.assertEqual(green, ["tests/test_a.py > test_ok"])

    def test_refuses_the_other_types_by_name(self):
        problems, lines, _ = self.judge("tests/test_c.py")
        self.assertEqual(len(problems), 2, lines)
        self.assertTrue(any(line.startswith("tests/test_c.py > test_custom: red for the wrong reason, Custom") for line in lines), lines)
        self.assertTrue(any(line.startswith("tests/test_c.py > test_type: red for the wrong reason, TypeError") for line in lines), lines)

    def test_a_collection_error_is_a_load_error_of_its_file(self):
        problems, lines, _ = self.judge("tests/test_b.py")
        self.assertEqual(problems, ["tests/test_b.py > tests.test_b"], lines)
        self.assertTrue(lines[0].startswith("tests/test_b.py > tests.test_b: LOAD ERROR"), lines)

    def test_the_type_attribute_wins_over_the_text(self):
        xml = '<testsuite name="a.test.ts"><testcase classname="a.test.ts" name="t"><failure type="NotImplemented">x.ts:1: AssertionError</failure></testcase></testsuite>'
        problems, lines, _ = junit.judge(xml, ["a.test.ts"], {"NotImplemented"})
        self.assertEqual(problems, [], lines)
        self.assertEqual(lines, ["a.test.ts > t: red, NotImplemented"])


PLAYWRIGHT = """<testsuites id="" name="" tests="3" failures="1" skipped="0" errors="2">\
<testsuite name="assert.e2e.ts" tests="1" failures="1" errors="0"><testcase name="assert" classname="assert.e2e.ts">\
<failure message="expect(received).toBe(expected) // Object.is equality" type="expect.toBe">Error Context: x.md</failure></testcase></testsuite>\
<testsuite name="stub.e2e.ts" tests="2" failures="0" errors="2"><testcase name="stub" classname="stub.e2e.ts">\
<error message="not implemented" type="NotImplemented">Error Context: y.md</error></testcase>\
<testcase name="thrown" classname="stub.e2e.ts"><error message="x is not a function" type="TypeError">Error Context: z.md</error></testcase>\
</testsuite></testsuites>"""


class PlaywrightTest(unittest.TestCase):
    """Playwright 1.65's JUnit reporter, measured on 2026-11-19: an assertion
    is a <failure> typed with its matcher, any other error an <error> typed
    with its name; a file that fails to load empties the whole report."""

    FILES = ["e2e/assert.e2e.ts", "e2e/stub.e2e.ts"]

    def test_a_type_ending_in_a_star_matches_its_prefix(self):
        problems, lines, _ = junit.judge(PLAYWRIGHT, ["e2e/assert.e2e.ts"], {"expect.*"})
        self.assertEqual(problems, [], lines)
        self.assertEqual(lines, ["e2e/assert.e2e.ts > assert: red, expect.toBe"])
        problems, lines, _ = junit.judge(PLAYWRIGHT, ["e2e/assert.e2e.ts"], {"expect"})
        self.assertEqual(len(problems), 1, lines)

    def test_an_error_with_a_type_is_a_failure_of_that_type_not_a_load_error(self):
        problems, lines, _ = junit.judge(PLAYWRIGHT, self.FILES, {"expect.*", "NotImplemented"})
        self.assertEqual(problems, ["e2e/stub.e2e.ts > thrown"], lines)
        self.assertIn("e2e/stub.e2e.ts > stub: red, NotImplemented", lines)
        self.assertTrue(any(line.startswith("e2e/stub.e2e.ts > thrown: red for the wrong reason, TypeError") for line in lines), lines)

    def test_types_found_and_passes_name_the_error_s_type(self):
        self.assertEqual(junit.types_found(PLAYWRIGHT, self.FILES), [
            "e2e/assert.e2e.ts > assert: expect.toBe",
            "e2e/stub.e2e.ts > stub: NotImplemented",
            "e2e/stub.e2e.ts > thrown: TypeError",
        ])
        problems, lines = junit.passes(PLAYWRIGHT, ["e2e/stub.e2e.ts"])
        self.assertEqual(len(problems), 2, lines)
        self.assertIn("e2e/stub.e2e.ts > stub: fails, NotImplemented: not implemented", lines)

    def test_two_runs_are_judged_as_one(self):
        vitest = ('<testsuites><testsuite name="__tests__/a.test.ts"><testcase classname="__tests__/a.test.ts" name="p"/>'
                  '</testsuite></testsuites>')
        runs = [(vitest, ["__tests__/a.test.ts"]), (PLAYWRIGHT, ["e2e/assert.e2e.ts"])]
        problems, lines, green = junit.judge(runs, ["__tests__/a.test.ts", "e2e/assert.e2e.ts"], {"expect.*"})
        self.assertEqual(problems, [], lines)
        self.assertEqual(green, ["__tests__/a.test.ts > p"])
        problems, lines = junit.passes(runs, ["__tests__/a.test.ts"])
        self.assertEqual(problems, [], lines)

    def test_a_run_s_suites_match_only_that_run_s_files(self):
        # Playwright names its suites from testDir: `login.spec.ts` ends
        # src/login.spec.ts as much as e2e/login.spec.ts.
        vitest = ('<testsuites><testsuite name="src/login.spec.ts"><testcase classname="src/login.spec.ts" name="u"/>'
                  '</testsuite></testsuites>')
        e2e = ('<testsuites><testsuite name="login.spec.ts"><testcase classname="login.spec.ts" name="e"/>'
               '</testsuite></testsuites>')
        runs = [(vitest, ["src/login.spec.ts"]), (e2e, ["e2e/login.spec.ts"])]
        problems, lines = junit.passes(runs, ["src/login.spec.ts", "e2e/login.spec.ts"])
        self.assertEqual(problems, [], lines)
        self.assertEqual(lines, ["2 passed, 0 skipped, in 2 files"])

    def test_a_suite_belongs_to_the_closest_file_that_ends_with_its_name(self):
        e2e = ('<testsuites><testsuite name="admin/login.spec.ts"><testcase classname="admin/login.spec.ts" name="a"/></testsuite>'
               '<testsuite name="login.spec.ts"><testcase classname="login.spec.ts" name="e"/></testsuite></testsuites>')
        files = ["e2e/admin/login.spec.ts", "./e2e/login.spec.ts"]
        problems, lines = junit.passes([(e2e, ["e2e/admin/login.spec.ts", "e2e/login.spec.ts"])], files)
        self.assertEqual(problems, [], lines)

    def test_refuses_an_also_file_that_is_not_a_test_file(self):
        with tempfile.TemporaryDirectory() as work:
            unit = os.path.join(work, "unit.xml")
            e2e = os.path.join(work, "e2e.xml")
            with open(unit, "w") as handle:
                handle.write('<testsuite name="a.test.ts"><testcase classname="a.test.ts" name="p"/></testsuite>')
            with open(e2e, "w") as handle:
                handle.write('<testsuite name="login.spec.ts"><testcase classname="login.spec.ts" name="e"/></testsuite>')
            argv = ["junit.py", "--passes", "--also", "run_integrate_tests=" + e2e,
                    "--also-file", "nope.spec.ts", unit, "a.test.ts", "e2e/login.spec.ts"]
            with mock.patch.object(sys, "argv", argv), contextlib.redirect_stderr(io.StringIO()) as err, \
                    contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    junit.main()
            self.assertEqual(raised.exception.code, 2)
            self.assertIn("nope.spec.ts", err.getvalue())


class TypesFoundTest(unittest.TestCase):
    """What the setup's red probe reads: each testcase's outcome, with no
    judgment and nothing that changes from one run to the next."""

    def test_prints_each_testcase_s_type_in_the_order_of_the_files(self):
        lines = junit.types_found(PYTEST, ["tests/test_b.py", "tests/test_a.py", "tests/test_c.py"])
        self.assertEqual(lines, [
            "tests/test_b.py > tests.test_b: LOAD ERROR",
            "tests/test_a.py > test_assert: AssertionError",
            "tests/test_a.py > test_stub: NotImplementedError",
            "tests/test_a.py > test_ok: passes",
            "tests/test_c.py > test_custom: Custom",
            "tests/test_c.py > test_type: TypeError",
        ])

    def test_names_a_file_not_in_the_report_skips_and_failures_without_a_type(self):
        xml = ('<testsuites><testsuite name="a.test.ts">'
               '<testcase classname="a.test.ts" name="s"><skipped/></testcase>'
               '<testcase classname="a.test.ts" name="u"><failure message="boom">no type here</failure></testcase>'
               '<testcase classname="a.test.ts" name="a.test.ts"><failure type="Error" message="Cannot find module"/></testcase>'
               '</testsuite></testsuites>')
        lines = junit.types_found(xml, ["a.test.ts", "b.test.ts"])
        self.assertEqual(lines, [
            "a.test.ts > s: skipped",
            "a.test.ts > u: no type",
            "a.test.ts > a.test.ts: LOAD ERROR",
            "b.test.ts: not in the runner's report",
        ])


class PassesTest(unittest.TestCase):
    """What verify reads after the recorded suites run again: every test
    passes or is skipped, and every file is in the report."""

    def test_a_green_run_has_no_problem(self):
        xml =('<testsuite name="a.test.ts"><testcase classname="a.test.ts" name="p"/>'
               '<testcase classname="a.test.ts" name="s"><skipped/></testcase></testsuite>')
        problems, lines = junit.passes(xml, ["a.test.ts"])
        self.assertEqual(problems, [], lines)
        self.assertEqual(lines, ["1 passed, 1 skipped, in 1 file"])

    def test_names_failures_load_errors_and_missing_files(self):
        problems, lines = junit.passes(PYTEST, ["tests/test_a.py", "tests/test_b.py", "tests/test_d.py"])
        self.assertEqual(problems, [
            "tests/test_a.py > test_assert",
            "tests/test_a.py > test_stub",
            "tests/test_b.py > tests.test_b",
            "tests/test_d.py",
        ], lines)
        self.assertIn("tests/test_a.py > test_assert: fails, AssertionError: assert 1 == 2", lines)
        self.assertTrue(any(line.startswith("tests/test_b.py > tests.test_b: LOAD ERROR") for line in lines), lines)
        self.assertIn("tests/test_d.py: not in the runner's report", lines)


def case(name, body=""):
    return '<testcase classname="a.test.ts" name="%s">%s</testcase>' % (name, body)


def failing(kind, message):
    return '<failure message="%s" type="%s"/>' % (message, kind)


class SummaryTest(unittest.TestCase):
    """What red-check.sh prints with --report: a summary for the main agent,
    the line per testcase in the report file."""

    def run_main(self, xml, files, *extra):
        with tempfile.TemporaryDirectory() as work:
            output = os.path.join(work, "output.txt")
            existing = os.path.join(work, "existing.txt")
            report = os.path.join(work, "report.txt")
            green = os.path.join(work, "green.txt")
            with open(output, "w") as handle:
                handle.write("some log line\n" + xml)
            with open(existing, "w") as handle:
                handle.write("a.test.ts\told\n")
            argv = ["junit.py", "--types", "AssertionError, NotImplemented", "--existing", existing,
                    "--green", green, "--report", report] + list(extra) + [output] + files
            with mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()) as out:
                code = junit.main()
            with open(report) as handle:
                written = handle.read()
            return code, out.getvalue().replace(report, "REPORT").replace(green, "GREEN"), written

    def test_a_valid_red_counts_reds_by_type_and_shows_the_messages_they_share(self):
        cases = ["".join(case("t%d" % i, failing("AssertionError", "expected 500 to be 200")) for i in range(6)),
                 case("old", failing("AssertionError", "expected 500 to be 200")),
                 case("s1", failing("NotImplemented", "not implemented")),
                 case("s2", failing("NotImplemented", "not implemented")),
                 case("alone", failing("AssertionError", "expected 1 to be 2")),
                 case("green")]
        xml = '<testsuite name="a.test.ts">%s</testsuite>' % "".join(cases)
        code, out, report = self.run_main(xml, ["a.test.ts"])
        self.assertEqual(code, 0, out)
        self.assertEqual(out.splitlines(), [
            "red check: valid red, every other new test fails for an allowed reason (AssertionError, NotImplemented).",
            "reds: AssertionError 7 new, 1 already in HEAD; NotImplemented 2 new",
            "  7 × AssertionError: expected 500 to be 200",
            "  2 × NotImplemented: not implemented",
            "red check: 1 new test passes already, before the chunk's code: give it to the step reviewer for a mutation check (GREEN).",
            "red check: the report, a line per test: REPORT",
        ])
        self.assertIn("a.test.ts > t0: red, AssertionError\n", report)
        self.assertIn("a.test.ts > green: passes already, before the chunk's code\n", report)

    def test_shows_at_most_five_groups_the_largest_first(self):
        cases = "".join(case("t%d%d" % (g, i), failing("AssertionError", "message %d" % g))
                        for g in range(7) for i in range(2 + (g == 6)))
        code, out, _ = self.run_main('<testsuite name="a.test.ts">%s</testsuite>' % cases, ["a.test.ts"])
        lines = out.splitlines()
        self.assertEqual(code, 0, out)
        self.assertEqual(lines[2], "  3 × AssertionError: message 6", out)
        self.assertEqual(sum(line.startswith("  2 × ") for line in lines), 4, out)
        self.assertIn("  2 more groups in the report", lines)

    def test_an_invalid_red_groups_its_problems_with_an_example(self):
        cases = "".join([case("t1", failing("TypeError", "x is not a function")),
                         case("t2", failing("TypeError", "x is not a function")),
                         case("s", "<skipped/>"),
                         case("r", failing("AssertionError", "expected 1 to be 2")),
                         case("a.test.ts", '<error message="Cannot find module"/>')])
        code, out, report = self.run_main('<testsuite name="a.test.ts">%s</testsuite>' % cases, ["a.test.ts", "b.test.ts"])
        self.assertEqual(code, 1, out)
        self.assertEqual(out.splitlines(), [
            "red check: NOT a valid red, 5 problem(s). Back to the test-author, with the report.",
            "  2 × red for the wrong reason, TypeError: x is not a function (e.g. a.test.ts > t1)",
            "  1 × skipped, not red (e.g. a.test.ts > s)",
            "  1 × LOAD ERROR: Cannot find module (e.g. a.test.ts > a.test.ts)",
            "  1 × not in the runner's report (e.g. b.test.ts)",
            "reds: AssertionError 1 new",
            "red check: the report, a line per test: REPORT",
        ])
        self.assertIn("a.test.ts > r: red, AssertionError\n", report)

    def test_without_report_prints_a_line_per_testcase_as_before(self):
        xml = '<testsuite name="a.test.ts">%s</testsuite>' % case("t", failing("AssertionError", "m"))
        with tempfile.TemporaryDirectory() as work:
            output = os.path.join(work, "output.txt")
            with open(output, "w") as handle:
                handle.write(xml)
            argv = ["junit.py", "--types", "AssertionError", output, "a.test.ts"]
            with mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(junit.main(), 0)
        self.assertIn("a.test.ts > t: red, AssertionError", out.getvalue())


if __name__ == "__main__":
    unittest.main()
