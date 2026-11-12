"""Tests of junit.py on the JUnit XML of real runners: `python3 -m unittest
discover -s tests`. The pytest report is pytest 9.2's, from
`pytest --continue-on-collection-errors --junitxml=/dev/stdout`, cut to the
elements junit.py reads."""

import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("junit", os.path.join(HERE, "..", "plugins", "workflow-overload", "scripts", "junit.py"))
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


if __name__ == "__main__":
    unittest.main()
