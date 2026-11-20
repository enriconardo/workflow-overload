#!/usr/bin/env python3
"""Judges whether a run of the recorded suite is red for the right reason.

  junit.py --types "AssertionError, NotImplemented" [--existing <names-file>] [--green <file>] <output-file> <test-file>...
  junit.py --list <output-file> <test-file>...
  junit.py --types-found <output-file> <test-file>...
  junit.py --passes <output-file> <test-file>...

<output-file> holds what the test command printed: the JUnit XML is the
part from the first `<?xml` or `<testsuites` to the last `</testsuites>`, so
a runner's other output around it does no harm. Each <test-file> is a path
from the project's root; a runner names its files from its own root, which
may be a package's folder, so a suite matches a file when one path ends with
the other at a path boundary.

The test files may run through two commands, `run_tests` for those `check`
runs and `run_integrate_tests` for those it leaves out: `--also
<key>=<output-file>` adds the second run, `--also-file <test-file>` names
each of its files, and the files are judged across both as one run. Each
run's suites match only that run's files: Playwright names a suite from its
testDir (`login.spec.ts`), which would end another run's file too. `--key`
names the first run's command (`run_tests` by default), for the message on
an output with no XML.

The rules, from the probe of 2026-11-09 on vitest and pytest, and Playwright
measured on 2026-11-19:

1. every test file appears in the XML, and none of its testcases is a load
   error: a testcase named after the file itself, or an <error> element with
   no `type`, as pytest writes for a collection error. Playwright types its
   <error>, any error but an assertion: that one is a failure of its type;
2. no new testcase is skipped. One that passes already is no valid red by
   itself: it goes to the step reviewer, who checks that it fails when the
   behavior it covers breaks (--green writes them to a file);
3. each failure's type is among --types; a TypeError, for instance, means
   a missing export in Node, a stub that was never written. The type is the
   failure's `type`; pytest writes none, and with its default traceback the
   type ends the failure's text, on a last line `<path>:<line>: <Type>`. A
   type of --types ending in `*` matches every type it starts: Playwright
   types an assertion with its matcher (`expect.toBe`), so `expect.*`;
4. at least one testcase fails.

A testcase listed in --existing (lines `<test-file>\t<name>`, as --list
prints them for a run of the files as they are in HEAD) was there before the
chunk: it may pass, or fail by rule 3 when the chunk changes the behavior it
tests.

--types-found judges nothing: it prints each testcase's outcome, the
failure's type by rule 3, LOAD ERROR by rule 1, `skipped` or `passes`, and
each file the report lacks. The setup's red probe reads it to measure
red_types.

--passes judges a run that must be green, the recorded suites run again by
verify.sh: every file in the report, no load error, no failure; a skipped
test is counted. Exit 0 when green, 1 when not.

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


LAST_LINE_TYPE = re.compile(r":\d+: ([A-Za-z_][\w.]*)$")


def failure_type(failure):
    kind = failure.get("type")
    if kind:
        return kind
    lines = (failure.text or "").strip().splitlines()
    match = LAST_LINE_TYPE.search(lines[-1].strip()) if lines else None
    return match.group(1).rsplit(".", 1)[-1] if match else ""


def type_allowed(kind, types):
    return kind in types or any(t.endswith("*") and len(t) > 1 and kind.startswith(t[:-1]) for t in types)


def failure_of(case):
    """The failure of a testcase that is no load error: a <failure>, or an
    <error> with a type."""
    node = case.find("failure")
    return node if node is not None else case.find("error")


def same_file(a, b):
    a, b = norm(a), norm(b)
    return a == b or a.endswith("/" + b) or b.endswith("/" + a)


def owner_of(files, *names):
    """The file a suite or testcase names, by one of its names. Several files
    may end with a name (Playwright names e2e/admin/login.spec.ts and
    e2e/login.spec.ts as admin/login.spec.ts and login.spec.ts): the closest
    in length is the one meant, the rest of its path being the runner's root."""
    for name in names:
        candidates = [f for f in files if same_file(f, name)]
        if candidates:
            return min(candidates, key=lambda f: abs(len(norm(f)) - len(norm(name))))
    return None


def collect(runs, files):
    """Each file's testcases. <runs> is one run's XML for all the files, or a
    list of (xml, the files of that run): a file runs in one of them, and a
    run's suites match only its own files."""
    if isinstance(runs, str):
        runs = [(runs, files)]
    found = {f: [] for f in files}
    for xml_text, own in runs:
        own = {norm(f) for f in own}
        collect_run(ET.fromstring(xml_text), [f for f in files if norm(f) in own], found)
    return found


def collect_run(root, files, found):
    suites = [root] if root.tag == "testsuite" else root.iter("testsuite")
    for suite in suites:
        name = suite.get("name") or ""
        owner = owner_of(files, name)
        cases = list(suite.iter("testcase"))
        if owner is None:
            # pytest and others name suites by package: match by classname/file,
            # or by name for pytest's collection error, which has no classname
            for case in cases:
                where = case.get("file") or case.get("classname") or case.get("name") or ""
                owner = owner_of(files, where, where.replace(".", "/") + ".py")
                if owner:
                    found[owner].append(case)
            continue
        found[owner].extend(cases)


def load_error(case, f):
    """A testcase that stands for its file failing to load (rule 1)."""
    name = case.get("name") or ""
    classname = case.get("classname")
    error = case.find("error")
    return (error is not None and not error.get("type")) or same_file(name, f) or bool(classname and same_file(name, classname))


def types_found(runs, files):
    lines = []
    for f, cases in collect(runs, files).items():
        if not cases:
            lines.append("%s: not in the runner's report" % f)
        for case in cases:
            failure = failure_of(case)
            if load_error(case, f):
                kind = "LOAD ERROR"
            elif case.find("skipped") is not None:
                kind = "skipped"
            elif failure is None:
                kind = "passes"
            else:
                kind = failure_type(failure) or "no type"
            lines.append("%s > %s: %s" % (f, case.get("name"), kind))
    return lines


def passes(runs, files):
    """Whether a run is green: every file in the report, no load error, no
    failure; a skipped test is counted, not refused."""
    problems = []
    lines = []
    passed = skipped = 0
    for f, cases in collect(runs, files).items():
        if not cases:
            problems.append(f)
            lines.append("%s: not in the runner's report" % f)
        for case in cases:
            label = "%s > %s" % (f, case.get("name"))
            failure = failure_of(case)
            if load_error(case, f):
                problems.append(label)
                node = failure
                message = (node.get("message") if node is not None else "") or ""
                lines.append("%s: LOAD ERROR, %s" % (label, message.splitlines()[0][:160] if message else "no message"))
            elif failure is not None:
                problems.append(label)
                message = (failure.get("message") or "").splitlines()
                lines.append("%s: fails, %s%s" % (label, failure_type(failure) or "no type", (": " + message[0][:160]) if message else ""))
            elif case.find("skipped") is not None:
                skipped += 1
            else:
                passed += 1
    if not problems:
        lines.append("%d passed, %d skipped, in %d file%s" % (passed, skipped, len(files), "" if len(files) == 1 else "s"))
    return problems, lines


def judge(runs, files, types, existing=frozenset()):
    found = collect(runs, files)
    problems = []
    green = []
    red = 0
    lines = []
    for f in files:
        cases = found[f]
        if not cases:
            problems.append(f)
            lines.append("%s: not in the runner's report (not collected, or outside its root)" % f)
            continue
        for case in cases:
            label = "%s > %s" % (f, case.get("name"))
            failure = failure_of(case)
            skipped = case.find("skipped")
            name = case.get("name") or ""
            if load_error(case, f):
                problems.append(label)
                node = failure
                message = (node.get("message") if node is not None else "") or ""
                lines.append("%s: LOAD ERROR, %s" % (label, message.splitlines()[0][:160] if message else "no message"))
            elif (f, name) in existing and failure is None:
                lines.append("%s: %s, already in HEAD" % (label, "skipped" if skipped is not None else "passes"))
            elif skipped is not None:
                problems.append(label)
                lines.append("%s: skipped, not red" % label)
            elif failure is None:
                green.append(label)
                lines.append("%s: passes already, before the chunk's code" % label)
            else:
                kind = failure_type(failure)
                if type_allowed(kind, types):
                    red += 1
                    lines.append("%s: red, %s" % (label, kind))
                else:
                    problems.append(label)
                    message = (failure.get("message") or "").splitlines()
                    lines.append("%s: red for the wrong reason, %s%s" % (label, kind or "no type", (": " + message[0][:160]) if message else ""))
    if not problems and not red:
        problems.append("suite")
        lines.append("no recorded test fails: the suite tests nothing the chunk adds")
    return problems, lines, green


def read_existing(path):
    if not path:
        return frozenset()
    with open(path, encoding="utf-8") as handle:
        return frozenset(tuple(line.rstrip("\n").split("\t", 1)) for line in handle if "\t" in line)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--types", default="AssertionError, NotImplemented")
    parser.add_argument("--existing", help="the testcases already in HEAD, as --list prints them")
    parser.add_argument("--green", help="a file for the new testcases that pass already, one per line")
    parser.add_argument("--list", action="store_true", help="print each testcase as <test-file>\\t<name>")
    parser.add_argument("--types-found", action="store_true", help="print each testcase's failure type, judging nothing")
    parser.add_argument("--passes", action="store_true", help="judge a run that must be green")
    parser.add_argument("--key", default="run_tests", help="the config's key of the command that printed <output-file>")
    parser.add_argument("--also", metavar="KEY=FILE",
                        help="another run of some of the files, the config's key of its command and its output")
    parser.add_argument("--also-file", action="append", default=[], metavar="TEST_FILE",
                        help="a test file of the --also run")
    parser.add_argument("output")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    types = {t.strip() for t in args.types.split(",") if t.strip()}
    also_files = {norm(f) for f in args.also_file}
    unknown = also_files - {norm(f) for f in args.files}
    if unknown:
        parser.error("--also-file names files that are not among the test files: %s" % ", ".join(sorted(unknown)))
    outputs = [(args.key, args.output, [f for f in args.files if norm(f) not in also_files])]
    if args.also:
        key, sep, path = args.also.partition("=")
        if not sep or not key or not path:
            parser.error("--also takes <key>=<output-file>, not %r" % args.also)
        outputs.append((key, path, [f for f in args.files if norm(f) in also_files]))
    elif also_files:
        parser.error("--also-file needs --also")
    runs = []
    for key, path, own in outputs:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = extract_xml(handle.read())
        if text is None:
            print("%s: the test command printed no JUnit XML (%s); check the config's %s." % ("verify" if args.passes else "red check", path, key))
            return 2
        runs.append((text, own))
    try:
        if args.list:
            for f, cases in collect(runs, args.files).items():
                for case in cases:
                    print("%s\t%s" % (f, case.get("name") or ""))
            return 0
        if args.types_found:
            for line in types_found(runs, args.files):
                print(line)
            return 0
        if args.passes:
            problems, lines = passes(runs, args.files)
            for line in lines:
                print(line)
            return 1 if problems else 0
        problems, lines, green = judge(runs, args.files, types, read_existing(args.existing))
    except ET.ParseError as error:
        print("red check: the JUnit XML does not parse (%s)." % error)
        return 2
    for line in lines:
        print(line)
    if problems:
        print("red check: NOT a valid red, %d problem(s). Back to the test-author." % len(problems))
        return 1
    print("red check: valid red, every %snew test fails for an allowed reason (%s)." % ("other " if green else "", ", ".join(sorted(types))))
    if args.green:
        with open(args.green, "w", encoding="utf-8") as handle:
            handle.write("".join(label + "\n" for label in green))
    if green:
        print("red check: %d new test%s already, before the chunk's code: give %s to the step reviewer for a mutation check (%s)."
              % (len(green), " passes" if len(green) == 1 else "s pass", "it" if len(green) == 1 else "them", args.green or "listed above"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
