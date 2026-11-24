#!/usr/bin/env python3
"""Reads the documents of .workflow/: a spec of the L path and a plan.

  spec.py status <doc>        the frontmatter's status: draft, approved, done
                              or dropped
  spec.py chunks <spec>       a line per chunk: <n> <open|done> <type> <first step>
  spec.py depends <spec>      the files of the frontmatter's depends_on, one
                              per line: those main must not have changed
                              since the approval for a build to start as is
  spec.py link <spec>         the plan and item of a plan's item spec, as
                              <plan> <n>; nothing for a spec of no plan
  spec.py ready <spec>...     those of the specs that /overload:build takes:
                              approved, with a chunk left to build, each as
                              <path> <k of n chunks open>; one it cannot
                              read as <path> unreadable: <why>
  spec.py check <plan>        the plan's counts, or each way it is out of
                              format, a line each
  spec.py items <plan> [<spec>...]
                              a line per item: <n> <open|started|done> <S|L>
                              <the items it depends on, or -> <title>; started
                              when one of the specs, approved or done, names
                              it in its link
  spec.py steps <plan>        a line per acceptance step: <k> <open|passed|
                              failed> <the requirements it checks, or ->
  spec.py revision <old> <new>
                              the items a revision of the plan adds, removes
                              or changes: <n> <added|removed|changed>

<doc> is a path, or `-` for the standard input; a command on a plan refuses a
plan out of format, with every way it is.

A chunk line is `- [ ] <n>. <title> (<type>): <files>; <key>: <value>...`,
its type `test-first`, `no test-first` or `tests only`, printed with dashes.
Its first step: `stub` when it names `signatures` or `dependencies`, the
declarations and packages the test-author cannot put in place; `test` when
it is test-first or of tests only; `implement` otherwise. A line under *Chunks*
that reads as a chunk but has no type, or a number given twice, is refused.

A plan's requirements sit under `## Requirements`, in an area each, under a
`### <Area>` heading: `- <AREA>-<nn>. <text> — verify: <ways>`, the ways among
test, test outside check, acceptance and measure, separated by `;` or `,`.
An area's IDs share one prefix, its own. Its items, under `## Items`:
`- [ ] <n>. <title> (<S|L> estimated[: why]): <intent>; covers <IDs>; closes
<IDs>; depends on <n>, ... | —`, each field after the intent optional. Its
acceptance steps, under `## Acceptance`: `- [ ] <IDs>: <preconditions>;
<action>; <expected result>`, the IDs left out for a step of no requirement
(the CI after the push), a failed step's outcome after it as ` — failed:
<what>`. Every requirement is covered by an item; one that two items cover is
closed by one of them; one verified by acceptance or measure has a step. A
draft plan has nothing ticked; a done one has everything ticked.

A spec of a plan's item names both in its frontmatter: `plan:
.workflow/plans/<name>.md` and `item: <n>`. A revision keeps the numbers of
the plan's items, numbers its new items from the old highest on, one after
the other (a split item's new part included), and leaves a ticked item as it
is."""

import os
import re
import sys
from collections import namedtuple

Chunk = namedtuple("Chunk", "number done type first_step")
Requirement = namedtuple("Requirement", "id area verify")
Item = namedtuple("Item", "number done tier title covers closes depends line")
Step = namedtuple("Step", "number done failed ids")
Plan = namedtuple("Plan", "status requirements items steps")

LINE = re.compile(r"^- \[([ xX])\] (\d+)\.\s+(.*)$")
TYPE = re.compile(r"\((test-first|no test-first|tests only)\)(?::|\s*$)")
STUB_KEYS = ("signatures", "dependencies")
STATUSES = ("draft", "approved", "done", "dropped")

ID = r"[A-Z][A-Z0-9]*-\d{2,}"
ID_LIST = re.compile(r"^%s(?:\s*,\s*%s)*$" % (ID, ID))
REQUIREMENT = re.compile(r"^- ([A-Z][A-Z0-9]*)-(\d{2,})\.\s+(.+?)\s+—\s+verify:\s*(.+)$")
WAYS = ("test", "test outside check", "acceptance", "measure")
TIER = re.compile(r"\(([SL]) estimated(?::[^()]*)?\)(?::\s*|\s*$)")
STEP = re.compile(r"^- \[([ xX])\]\s+(.*)$")
STEP_IDS = re.compile(r"^(%s(?:\s*,\s*%s)*):\s+(.*)$" % (ID, ID))
FAILED = re.compile(r"\s+—\s+failed:\s*(.*)$")
PLAN_PATH = re.compile(r"^\.workflow/plans/[^/]+\.md$")


class SpecError(Exception):
    """A document out of format; `problems` holds each way it is."""

    def __init__(self, *problems, where=None):
        super().__init__("; ".join(problems))
        self.problems = list(problems)
        self.where = where


def section(text, title):
    """The lines under a `## <title>` heading, up to the next `## `."""
    lines, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            inside = line[3:].strip() == title
            continue
        if inside:
            lines.append(line)
    return lines


def first_step(kind, rest):
    for field in rest.split(";"):
        key, _, value = field.partition(":")
        if key.strip() in STUB_KEYS and value.strip() not in ("", "none"):
            return "stub"
    return "implement" if kind == "no test-first" else "test"


def chunks(text):
    found, seen = [], set()
    for line in section(text, "Chunks"):
        match = LINE.match(line.rstrip())
        if not match:
            continue
        mark, number, body = match.groups()
        number = int(number)
        if number in seen:
            raise SpecError("chunk %d is numbered twice" % number)
        seen.add(number)
        kind = TYPE.search(body)
        if not kind:
            raise SpecError("chunk %d has no type: (test-first), (no test-first) or (tests only)" % number)
        rest = body[kind.end():]
        found.append(Chunk(number, mark != " ", kind.group(1).replace(" ", "-"), first_step(kind.group(1), rest)))
    return found


def frontmatter(text, wanted):
    """A key's value in the frontmatter, between the first two `---`."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        key, _, value = line.partition(":")
        if key.strip() == wanted:
            return value.strip()
    return ""


def status(text):
    return frontmatter(text, "status")


def depends_on(text):
    value = frontmatter(text, "depends_on")
    if value in ("", "none"):
        return []
    return [path.strip() for path in value.split(",") if path.strip()]


def link(text):
    """The plan and item number a spec names, or None for a spec of no plan."""
    plan, item = frontmatter(text, "plan"), frontmatter(text, "item")
    if not plan and not item:
        return None
    if not plan or not item:
        raise SpecError("a spec of a plan's item names both: plan: .workflow/plans/<name>.md and item: <n>")
    plan = os.path.normpath(plan)
    if not PLAN_PATH.match(plan):
        raise SpecError("plan: %s is not .workflow/plans/<name>.md" % plan)
    if not item.isdigit() or int(item) < 1:
        raise SpecError("item: %s is not an item's number" % item)
    return plan, int(item)


def id_list(value, where, problems):
    value = value.strip()
    if not ID_LIST.match(value):
        problems.append("%s: %r is not a list of requirement IDs such as AUTH-01, AUTH-02" % (where, value))
        return []
    return [one.strip() for one in value.split(",")]


def requirements(text, problems):
    found, area = [], None
    for line in section(text, "Requirements"):
        line = line.rstrip()
        if line.startswith("### "):
            area = line[4:].strip()
            continue
        if not line.startswith("- "):
            continue
        match = REQUIREMENT.match(line)
        if not match:
            problems.append("requirement out of format: %r; it reads - <AREA>-<nn>. <text> — verify: <ways>" % line)
            continue
        prefix, number, _, verify = match.groups()
        ident = "%s-%s" % (prefix, number)
        if area is None:
            problems.append("%s is under no area: a ### <Area> heading comes first" % ident)
        ways = [way.strip() for way in re.split(r"[;,]", verify)]
        for way in ways:
            if way not in WAYS:
                problems.append("%s: verify %r is none of %s" % (ident, way, ", ".join(WAYS)))
        found.append(Requirement(ident, area, ways))
    return found


def item_fields(number, rest, problems):
    covers, closes, depends = [], [], []
    where = "item %d" % number
    for field in rest.split(";"):
        field = field.strip()
        key = field.split(" ", 1)[0]
        if key in ("covers", "closes"):
            ids = id_list(field[len(key):], "%s %s" % (where, key), problems)
            (covers if key == "covers" else closes).extend(ids)
        elif field.startswith("depends on"):
            value = field[len("depends on"):].strip()
            if value in ("—", "-", "none"):
                continue
            for one in value.split(","):
                if one.strip().isdigit():
                    depends.append(int(one))
                else:
                    problems.append("%s depends on %r: an item's number, or —" % (where, one.strip()))
    return covers, closes, depends


def items(text, problems):
    found, seen = [], set()
    for line in section(text, "Items"):
        line = line.rstrip()
        if not line.startswith("- "):
            continue
        match = LINE.match(line)
        if not match:
            problems.append("item out of format: %r; it reads - [ ] <n>. <title> (<S|L> estimated): ..." % line)
            continue
        mark, number, body = match.groups()
        number = int(number)
        if number in seen:
            problems.append("item %d is numbered twice" % number)
        seen.add(number)
        tier = TIER.search(body)
        if not tier:
            problems.append("item %d has no tier: (S estimated) or (L estimated), with an optional : <why>" % number)
            continue
        covers, closes, depends = item_fields(number, body[tier.end():], problems)
        found.append(
            Item(number, mark != " ", tier.group(1), body[: tier.start()].strip(), covers, closes, depends, body)
        )
    return found


def steps(text, problems):
    found = []
    for line in section(text, "Acceptance"):
        line = line.rstrip()
        if not line.startswith("- "):
            continue
        match = STEP.match(line)
        if not match:
            problems.append(
                "acceptance step out of format: %r; it reads - [ ] <IDs>: <preconditions>; <action>; <expected result>"
                % line
            )
            continue
        number = len(found) + 1
        mark, body = match.groups()
        failed = FAILED.search(body)
        if failed:
            body = body[: failed.start()]
        ids = []
        labelled = STEP_IDS.match(body)
        if labelled:
            ids = [one.strip() for one in labelled.group(1).split(",")]
            body = labelled.group(2)
        elif re.match(r"^[A-Z][A-Z0-9]*-", body):
            problems.append("acceptance step %d: its requirements are not a list of IDs such as AUTH-01, AUTH-02" % number)
        if len([part for part in body.split(";") if part.strip()]) < 3:
            problems.append("acceptance step %d has no preconditions; action; expected result" % number)
        done = mark != " "
        if done and failed:
            problems.append("acceptance step %d is ticked and failed" % number)
        found.append(Step(number, done, failed is not None, ids))
    return found


def cycle(found):
    """An item that depends on itself through others, or None."""
    depends = {item.number: item.depends for item in found}
    state = {}

    def visit(number):
        state[number] = "visiting"
        for other in depends.get(number, []):
            if state.get(other) == "visiting" or (other not in state and visit(other)):
                return True
        state[number] = "done"
        return False

    for number in sorted(depends):
        if number not in state and visit(number):
            return number
    return None


def check_plan(plan, problems):
    known = {requirement.id: requirement for requirement in plan.requirements}
    numbers = {item.number for item in plan.items}
    if plan.status not in STATUSES:
        problems.append("status %r is none of %s" % (plan.status, ", ".join(STATUSES)))
    if not plan.requirements:
        problems.append("no requirement under ## Requirements")
    if not plan.items:
        problems.append("no item under ## Items")

    seen, prefixes = set(), {}
    for requirement in plan.requirements:
        if requirement.id in seen:
            problems.append("%s is given twice" % requirement.id)
        seen.add(requirement.id)
        if requirement.area is not None:
            prefix = requirement.id.rsplit("-", 1)[0]
            prefixes.setdefault(requirement.area, set()).add(prefix)
    owners = {}
    for area, found in sorted(prefixes.items()):
        if len(found) > 1:
            problems.append("area %s holds IDs of %s: an area's IDs share its own prefix" % (area, ", ".join(sorted(found))))
        for prefix in found:
            owners.setdefault(prefix, []).append(area)
    for prefix, areas in sorted(owners.items()):
        if len(areas) > 1:
            problems.append("prefix %s is in areas %s: an area reads in one place" % (prefix, ", ".join(areas)))

    covered, closed = {}, {}
    for item in plan.items:
        for ident in item.covers + item.closes:
            if ident not in known:
                problems.append("item %d names %s, no requirement of the plan" % (item.number, ident))
        for ident in item.closes:
            if ident not in item.covers:
                problems.append("item %d closes %s without covering it" % (item.number, ident))
        for ident in sorted(set(item.covers)):
            covered.setdefault(ident, []).append(item.number)
        for ident in sorted(set(item.closes)):
            closed.setdefault(ident, []).append(item.number)
        for other in item.depends:
            if other == item.number:
                problems.append("item %d depends on itself" % item.number)
            elif other not in numbers:
                problems.append("item %d depends on item %d, which the plan lacks" % (item.number, other))
    looped = cycle(plan.items)
    if looped is not None:
        problems.append("item %d depends on itself through other items" % looped)

    for requirement in plan.requirements:
        by = covered.get(requirement.id, [])
        if not by:
            problems.append("%s is covered by no item" % requirement.id)
        elif len(by) > 1 and not closed.get(requirement.id):
            problems.append(
                "%s is covered by items %s and closed by none of them" % (requirement.id, ", ".join(map(str, by)))
            )
        if len(closed.get(requirement.id, [])) > 1:
            problems.append(
                "%s is closed by items %s: one closes it" % (requirement.id, ", ".join(map(str, closed[requirement.id])))
            )

    checked = set()
    for step in plan.steps:
        for ident in step.ids:
            if ident not in known:
                problems.append("acceptance step %d names %s, no requirement of the plan" % (step.number, ident))
            checked.add(ident)
    for requirement in plan.requirements:
        ways = [way for way in requirement.verify if way in ("acceptance", "measure")]
        if ways and requirement.id not in checked:
            problems.append("%s is verified by %s and has no acceptance step" % (requirement.id, " and ".join(ways)))

    if plan.status == "draft":
        if any(item.done for item in plan.items) or any(step.done or step.failed for step in plan.steps):
            problems.append("a draft plan has no item ticked and no step run")
    if plan.status == "done":
        if not all(item.done for item in plan.items) or not all(step.done for step in plan.steps):
            problems.append("a done plan has every item ticked and every step passed")


def plan(text):
    """The plan in the text; SpecError with every way it is out of format."""
    problems = []
    found = Plan(status(text), requirements(text, problems), items(text, problems), steps(text, problems))
    check_plan(found, problems)
    if problems:
        raise SpecError(*problems)
    return found


def item_states(found, path, specs):
    """Each item's state: done when ticked, started when one of the specs
    (texts), approved or done, names it, open otherwise."""
    started = set()
    for text in specs:
        named = link(text)
        if named and named[0] == os.path.normpath(path) and status(text) in ("approved", "done"):
            started.add(named[1])
    return {
        item.number: "done" if item.done else "started" if item.number in started else "open" for item in found.items
    }


def revision(old, new):
    """How a revision changes the items of a plan (parsed): (number,
    added|removed|changed)."""
    before = {item.number: item for item in old.items}
    after = {item.number: item for item in new.items}
    highest = max(before) if before else 0
    problems, found = [], []
    for number in sorted(set(before) | set(after)):
        if number not in after:
            if before[number].done:
                problems.append("item %d is ticked and the revision removes it" % number)
            found.append((number, "removed"))
        elif number not in before:
            if number != highest + 1 + sum(1 for _, change in found if change == "added"):
                problems.append(
                    "item %d is new: the new items take %d and on, one after the other" % (number, highest + 1)
                )
            found.append((number, "added"))
        elif before[number].line != after[number].line or before[number].done != after[number].done:
            if before[number].done:
                problems.append("item %d is ticked and the revision changes it" % number)
            found.append((number, "changed"))
    if problems:
        raise SpecError(*problems)
    return found


def ready(paths):
    found = []
    for path in paths:
        try:
            text = read(path)
            if status(text) != "approved":
                continue
            all_chunks = chunks(text)
        except (OSError, SpecError) as error:
            found.append("%s\tunreadable: %s" % (path, error))
            continue
        left = sum(1 for chunk in all_chunks if not chunk.done)
        if left:
            found.append("%s\t%d of %d chunks open" % (path, left, len(all_chunks)))
    return found


def read(path):
    if path == "-":
        return sys.stdin.read()
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def plan_at(path, text):
    """The plan in the text read from the path; its SpecError names the path."""
    try:
        return plan(text)
    except SpecError as error:
        error.where = path
        raise


def run(command, args):
    """The command's output lines."""
    if command == "ready":
        return ready(args)
    text = read(args[0])
    if command == "status":
        return [status(text)]
    if command == "depends":
        return depends_on(text)
    if command == "link":
        named = link(text)
        return ["%s\t%d" % named] if named else []
    if command == "chunks":
        return [
            "%d\t%s\t%s\t%s" % (chunk.number, "done" if chunk.done else "open", chunk.type, chunk.first_step)
            for chunk in chunks(text)
        ]
    found = plan_at(args[0], text)
    if command == "revision":
        try:
            return ["%d\t%s" % change for change in revision(found, plan_at(args[1], read(args[1])))]
        except SpecError as error:
            error.where = error.where or args[1]
            raise
    if command == "check":
        return [
            "%d requirements, %d items (%d ticked), %d acceptance steps (%d passed)"
            % (
                len(found.requirements),
                len(found.items),
                sum(item.done for item in found.items),
                len(found.steps),
                sum(step.done for step in found.steps),
            )
        ]
    if command == "items":
        states = item_states(found, args[0], [read(spec) for spec in args[1:]])
        return [
            "%d\t%s\t%s\t%s\t%s"
            % (item.number, states[item.number], item.tier, ",".join(map(str, item.depends)) or "-", item.title)
            for item in found.items
        ]
    return [
        "%d\t%s\t%s" % (step.number, "passed" if step.done else "failed" if step.failed else "open", ",".join(step.ids) or "-")
        for step in found.steps
    ]


ARGUMENTS = {"status": 1, "chunks": 1, "depends": 1, "link": 1, "check": 1, "steps": 1, "revision": 2}
USAGE = (
    "Usage: spec.py status <doc> | chunks <spec> | depends <spec> | link <spec> | ready <spec>... "
    "| check <plan> | items <plan> [<spec>...] | steps <plan> | revision <old> <new>"
)


def main(argv):
    command = argv[0] if argv else ""
    count = len(argv) - 1
    if not (
        command == "ready" or (command == "items" and count >= 1) or ARGUMENTS.get(command) == count
    ):
        print(USAGE, file=sys.stderr)
        return 2
    try:
        lines = run(command, argv[1:])
    except OSError as error:
        print("spec.py: %s" % error, file=sys.stderr)
        return 1
    except SpecError as error:
        for problem in error.problems:
            print("spec.py: %s: %s" % (error.where or argv[1], problem), file=sys.stderr)
        return 1
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
