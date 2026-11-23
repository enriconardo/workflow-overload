#!/usr/bin/env python3
"""Reads a spec of the L path: its frontmatter's status and its chunk lines,
the ones under its `## Chunks` heading.

  spec.py chunks <spec>   a line per chunk: <n> <open|done> <type> <first step>
  spec.py status <spec>   the frontmatter's status

A chunk line is `- [ ] <n>. <title> (<type>): <files>; <key>: <value>...`,
its type `test-first`, `no test-first` or `tests only`, printed with dashes.
Its first step: `stub` when it names `signatures` or `dependencies`, the
declarations and packages the test-author cannot put in place; `test` when
it is test-first or of tests only; `implement` otherwise. <spec> is a path,
or `-` for the standard input. A line under *Chunks* that reads as a chunk
but has no type, or a number given twice, is refused."""

import re
import sys
from collections import namedtuple

Chunk = namedtuple("Chunk", "number done type first_step")

LINE = re.compile(r"^- \[([ xX])\] (\d+)\.\s+(.*)$")
TYPE = re.compile(r"\((test-first|no test-first|tests only)\)(?::|\s*$)")
STUB_KEYS = ("signatures", "dependencies")


class SpecError(Exception):
    pass


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


def status(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        key, _, value = line.partition(":")
        if key.strip() == "status":
            return value.strip()
    return ""


def read(path):
    if path == "-":
        return sys.stdin.read()
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def main(argv):
    if len(argv) != 2 or argv[0] not in ("chunks", "status"):
        print("Usage: spec.py chunks <spec> | status <spec>", file=sys.stderr)
        return 2
    command, path = argv
    try:
        text = read(path)
        if command == "status":
            print(status(text))
            return 0
        for chunk in chunks(text):
            print("%d\t%s\t%s\t%s" % (chunk.number, "done" if chunk.done else "open", chunk.type, chunk.first_step))
    except (OSError, SpecError) as error:
        print("spec.py: %s: %s" % (path, error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
