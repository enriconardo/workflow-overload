#!/usr/bin/env python3
"""Judges whether a run of the recorded suite is red for the right reason.

  junit.py --types "AssertionError, NotImplemented" <output-file> <test-file>...

<output-file> holds what the test command printed: the JUnit XML is the
part from the first `<?xml` or `<testsuites` to the last `</testsuites>`, so
a runner's other output around it does no harm. Each <test-file> is a path
from the project's root; a runner names its files from its own root, which
may be a package's folder, so a suite matches a file when one path ends with
the other at a path boundary.

The rules, from the probe of 2026-11-09 on vitest:

1. every test file appears in the XML, and none of its testcases is a load
   error: a testcase named after the file itself, or an <error> element;
2. every testcase fails: a passing or skipped one is no valid red;
3. each failure's `type` is among --types; a TypeError, for instance, means
   a missing export in Node, a stub that was never written.

Exit 0 when the run is a valid red, 1 when it is not, 2 when the output
holds no JUnit XML. Python 3.8+, standard library only.
"""

import argparse
import re
import sys
import xml.etree.ElementTree as ET


def extract_xml(text):
    start = None
    for marker in ("<?xml", "<testsuites", "<testsuite"):
        index = text.find(marker)
        if index != -1 and (start is None or index < start):
            start = index
    if start is None:
        return None
    end_tag = "</testsuites>" if "</testsuites>" in text[start:] else "</testsuite>"
    end = text.rfind(end_tag)
    if end == -1:
        return None
    return text[start:end + len(end_tag)]


def norm(path):
    return path.replace("\\", "/").lstrip("./")


def same_file(a, b):
    a, b = norm(a), norm(b)
    return a == b or a.endswith("/" + b) or b.endswith("/" + a)


def judge(xml_text, files, types):
    root = ET.fromstring(xml_text)
    suites = [root] if root.tag == "testsuite" else root.iter("testsuite")
    found = {f: [] for f in files}
    problems = []
    for suite in suites:
        name = suite.get("name") or ""
        owner = next((f for f in files if same_file(f, name)), None)
        cases = list(suite.iter("testcase"))
        if owner is None:
            # pytest and others name suites by package: match by classname/file
            for case in cases:
                where = case.get("file") or case.get("classname") or ""
                owner = next((f for f in files if same_file(f, where) or same_file(f, where.replace(".", "/") + ".py")), None)
                if owner:
                    found[owner].append(case)
            continue
        found[owner].extend(cases)
    lines = []
    for f in files:
        cases = found[f]
        if not cases:
            problems.append(f)
            lines.append("%s: not in the runner's report (not collected, or outside its root)" % f)
            continue
        for case in cases:
            label = "%s > %s" % (f, case.get("name"))
            failure = case.find("failure")
            error = case.find("error")
            skipped = case.find("skipped")
            name = case.get("name") or ""
            if error is not None or same_file(name, f) or (case.get("classname") and same_file(name, case.get("classname") or "")):
                problems.append(label)
                node = error if error is not None else failure
                message = (node.get("message") if node is not None else "") or ""
                lines.append("%s: LOAD ERROR, %s" % (label, message.splitlines()[0][:160] if message else "no message"))
            elif skipped is not None:
                problems.append(label)
                lines.append("%s: skipped, not red" % label)
            elif failure is None:
                problems.append(label)
                lines.append("%s: PASSES on the stubs: it tests nothing the chunk adds" % label)
            else:
                kind = failure.get("type") or ""
                if kind in types:
                    lines.append("%s: red, %s" % (label, kind))
                else:
                    problems.append(label)
                    message = (failure.get("message") or "").splitlines()
                    lines.append("%s: red for the wrong reason, %s%s" % (label, kind or "no type", (": " + message[0][:160]) if message else ""))
    return problems, lines


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--types", default="AssertionError, NotImplemented")
    parser.add_argument("output")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    types = {t.strip() for t in args.types.split(",") if t.strip()}
    with open(args.output, encoding="utf-8", errors="replace") as handle:
        xml_text = extract_xml(handle.read())
    if xml_text is None:
        print("red check: the test command printed no JUnit XML; check the config's test_files.")
        return 2
    try:
        problems, lines = judge(xml_text, args.files, types)
    except ET.ParseError as error:
        print("red check: the JUnit XML does not parse (%s)." % error)
        return 2
    for line in lines:
        print(line)
    if problems:
        print("red check: NOT a valid red, %d problem(s). Back to the test-author." % len(problems))
        return 1
    print("red check: valid red, every recorded test fails for an allowed reason (%s)." % ", ".join(sorted(types)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
