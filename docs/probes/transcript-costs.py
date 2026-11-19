#!/usr/bin/env python3
"""Where a probe's tokens, money and time went, read from Claude Code's transcripts.

    python3 docs/probes/transcript-costs.py <transcripts folder>

The folder is the project's under ~/.claude/projects/: one <session>.jsonl per
session, the main agent's, and <session>/subagents/*.jsonl with a .meta.json
each, the subagents'. Each API call counts once, by its message id.

A main agent's phase is the last `journal.sh set phase` its own commands ran;
before the first one, the phase `branch.sh` wrote as it opened the task, or, in
a resumed session, the one in the first journal header it read; else "start".
A subagent's cost goes to the phase in which it was launched. Costs are at the
API prices below, so with a subscription they compare parts, not a bill.

What enters the main context counts the tool results and the agents' reports:
an agent launched in the background reports in a message of its own, not in
its tool result, which only says it started.
"""
import collections
import datetime
import glob
import json
import os
import re
import sys

# $ per million tokens: input, cache read, output. A cache write costs 1.25x
# the input for a 5-minute entry, 2x for a 1-hour one. Prices of 2026-11.
PRICES = {"opus": (4.0, 0.20, 20.0), "sonnet": (2.0, 0.10, 10.0), "haiku": (0.10, 0.01, 0.50)}
SCRIPTS = re.compile(r"(journal|commit|verify|red-check|suite|integrate|sync|status|branch)\.sh")
PHASE = re.compile(r"journal\.sh set phase ([\w/\-]+)")
OPENED = re.compile(r"branch\.sh ([SL])\b")
HEADER = re.compile(r"^phase: ([\w/\-]+)\s*$", re.M)
SPEC = re.compile(r"specs/[^\s\"'`]+\.md")
MAX_GAP = 300  # seconds: a longer gap is a pause, not work, as in the probe's tables


def family(model):
    return next((f for f in PRICES if model and f in model), "opus")


def cost(usage, model):
    price_in, price_read, price_out = PRICES[family(model)]
    writes = usage.get("cache_creation") or {}
    short = writes.get("ephemeral_5m_input_tokens") or 0
    long_ = writes.get("ephemeral_1h_input_tokens") or 0
    if not writes:
        short = usage.get("cache_creation_input_tokens") or 0
    return ((usage.get("input_tokens") or 0) * price_in + short * price_in * 1.25
            + long_ * price_in * 2 + (usage.get("cache_read_input_tokens") or 0) * price_read
            + (usage.get("output_tokens") or 0) * price_out) / 1e6


def tokens(usage):
    keys = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
    return sum(usage.get(k) or 0 for k in keys)


def entries(path):
    with open(path) as f:
        for line in f:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def calls(path):
    """The API calls of a transcript in order: message id -> (usage, model, tool uses, text)."""
    out = collections.OrderedDict()
    for e in entries(path):
        m = e.get("message") or {}
        if e.get("type") != "assistant" or not m.get("id"):
            continue
        call = out.setdefault(m["id"], {"usage": None, "model": None, "uses": [], "text": ""})
        if m.get("usage"):
            call["usage"], call["model"] = m["usage"], m.get("model")
        for c in m.get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                call["uses"].append(c)
            elif isinstance(c, dict) and c.get("type") == "text":
                call["text"] += c.get("text", "")
    return out


def text_of(content):
    if isinstance(content, str):
        return content
    parts = []
    for c in content or []:
        if isinstance(c, dict) and c.get("type") == "text":
            parts.append(c.get("text", ""))
        elif isinstance(c, dict) and c.get("type") == "tool_result":
            parts.append(text_of(c.get("content")))
    return "\n".join(parts)


def phase_of(name):
    name = re.sub(r"chunk-\d+", "chunk", name)
    return "chunk:" + name.split("/")[-1] if name.startswith("l/chunk") else name


def next_phase(use, phase):
    command = (use.get("input") or {}).get("command", "") or ""
    found = PHASE.search(command)
    if found:
        return phase_of(found.group(1))
    opened = OPENED.search(command)
    if opened:
        return "s/implement" if opened.group(1) == "S" else "l/spec"
    return phase


def heard(entry):
    """What a user entry brings the main agent: a tool result, an agent's report, a reminder, a human's words."""
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, list) and any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
        return "tool result"
    text = text_of(content)
    if "<agent-message" in text or "<task-notification>" in text:
        return "agent report"
    if entry.get("isMeta") or text.lstrip().startswith("<system-reminder>"):
        return "reminder"
    return "human"


def kind(uses, then):
    if not uses:
        return "wait for an agent" if then == "agent report" else "text to the human"
    names = [u.get("name") for u in uses]
    commands = [(u.get("input") or {}).get("command", "") or "" for u in uses]
    if all(n == "Bash" and SCRIPTS.search(c) for n, c in zip(names, commands)):
        return "journal only" if set(SCRIPTS.findall(" ".join(commands))) == {"journal"} else "plugin scripts"
    if any(n in ("Agent", "Task") for n in names):
        return "agent launch"
    if all(n in ("Edit", "Write") for n in names):
        return "edit or write"
    if all(n == "Bash" for n in names):
        return "other bash"
    return "mixed"


def target(text):
    if "journal.md" in text:
        return "journal"
    return "spec" if SPEC.search(text) else None


def source(use):
    """What a tool result is, by its tool first and then by the file it names."""
    name, given = use.get("name"), use.get("input") or {}
    if name in ("Agent", "Task", "SendMessage"):
        return "agent launch"
    if name in ("Edit", "Write", "NotebookEdit"):
        return "edit or write"
    if name == "Read":
        what = target(given.get("file_path", "") or "")
        if not what:
            return "other"
        return what + (" read in part" if given.get("offset") or given.get("limit") else " read whole")
    command = given.get("command", "") or ""
    if "journal.sh show" in command:
        return "journal read whole"
    for part in re.split(r"&&|\|\||[;|\n]", command):
        words, what = part.split(), target(part)
        if not words or not what:
            continue
        if words[0] == "cat":
            return what + " read whole"
        if words[0] in ("grep", "head", "tail", "awk") or (words[0] == "sed" and "-i" not in words):
            return what + " read in part"
    for script in ("red-check", "verify", "commit"):
        if script + ".sh" in command:
            return script + ".sh"
    return "other"


def table(title, rows, total):
    print(f"\n{title}")
    for name, value, extra in rows:
        print(f"  {name:24} {value:9.1f} {100 * value / total:5.1f}%  {extra}")


def main(folder):
    by_agent = collections.defaultdict(collections.Counter)
    by_phase = collections.Counter()
    minutes = collections.Counter()
    by_kind = collections.Counter()
    kind_tokens = collections.Counter()
    kind_cost = collections.Counter()
    context = collections.Counter()
    pieces = collections.Counter()
    first, sizes = [], []
    for session in sorted(glob.glob(os.path.join(folder, "*.jsonl"))):
        sid = os.path.basename(session)[:-6]
        launched = {}
        for meta_path in glob.glob(os.path.join(folder, sid, "subagents", "*.meta.json")):
            with open(meta_path) as f:
                meta = json.load(f)
            launched[meta.get("toolUseId")] = (meta.get("agentType", "?"), meta_path[:-10] + ".jsonl")
        # One pass in order: the phase at each call and tool use, what each user
        # entry brings, and the time spent in each phase.
        phase, last = "start", None
        call_phase, use_phase, uses, order = {}, {}, {}, []
        for e in entries(session):
            m = e.get("message") or {}
            if e.get("type") == "assistant" and m.get("id"):
                if m["id"] not in call_phase:
                    order.append(("call", m["id"]))
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        uses[c.get("id")] = c
                        phase = next_phase(c, phase)
                        use_phase[c.get("id")] = phase
                call_phase[m["id"]] = phase
            elif e.get("type") == "user":
                what = heard(e)
                order.append(("heard", what))
                if what == "tool result":
                    for c in m["content"]:
                        if isinstance(c, dict) and c.get("type") == "tool_result":
                            body = c.get("content")
                            where = source(uses.get(c.get("tool_use_id"), {}))
                            context[where] += len(body if isinstance(body, str) else json.dumps(body))
                            pieces[where] += 1
                elif what == "agent report":
                    context[what] += len(text_of(m.get("content")))
                    pieces[what] += 1
                if phase == "start":
                    found = HEADER.search(text_of(m.get("content")))
                    if found:
                        phase = phase_of(found.group(1))
            stamp = e.get("timestamp")
            if stamp:
                t = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
                if last is not None and 0 < (t - last).total_seconds() < MAX_GAP:
                    minutes[phase] += (t - last).total_seconds() / 60
                if last is None or t > last:
                    last = t
        then = {}
        for i, (what, value) in enumerate(order):
            if what == "call":
                then[value] = next((v if w == "heard" else "call" for w, v in order[i + 1:]
                                    if w == "call" or v != "reminder"), "end")
        seen_first = False
        for mid, call in calls(session).items():
            for use in call["uses"]:
                agent = launched.get(use.get("id"))
                if agent and os.path.exists(agent[1]):
                    stats = by_agent[agent[0]]
                    stats["runs"] += 1
                    for sub in calls(agent[1]).values():
                        if sub["usage"]:
                            c = cost(sub["usage"], sub["model"])
                            stats["cost"] += c
                            stats["tokens"] += tokens(sub["usage"])
                            stats["output"] += sub["usage"].get("output_tokens") or 0
                            by_phase[use_phase.get(use.get("id"), "start")] += c
            if call["usage"]:
                u = call["usage"]
                c = cost(u, call["model"])
                stats = by_agent["main"]
                stats["cost"] += c
                stats["tokens"] += tokens(u)
                stats["output"] += u.get("output_tokens") or 0
                by_phase[call_phase.get(mid, "start")] += c
                k = kind(call["uses"], then.get(mid))
                by_kind[k] += 1
                kind_tokens[k] += tokens(u)
                kind_cost[k] += c
                size = tokens(u) - (u.get("output_tokens") or 0)
                sizes.append(size)
                if not seen_first:
                    first.append(size)
                    seen_first = True
        by_agent["main"]["runs"] += 1

    total = sum(s["cost"] for s in by_agent.values())
    print(f"total ${total:.1f}, {sum(s['tokens'] for s in by_agent.values()) / 1e6:.1f}M tokens")
    table("by agent ($)", [(a, s["cost"], f"{s['runs']} runs, {s['tokens'] / 1e6:.1f}M tokens, "
                            f"{s['output'] / 1e3:.0f}k out")
                           for a, s in sorted(by_agent.items(), key=lambda kv: -kv[1]["cost"])], total)
    table("by phase ($)", [(p, c, f"{minutes[p]:.0f} min") for p, c in by_phase.most_common()], total)
    all_tokens = sum(kind_tokens.values())
    table("main agent calls by kind (M tokens)", [(k, kind_tokens[k] / 1e6, f"{n} calls, ${kind_cost[k]:.1f}")
                                                  for k, n in by_kind.most_common()], all_tokens / 1e6)
    sizes.sort()
    print(f"\nmain context (k tokens): first call of each session {sorted(x // 1000 for x in first)}, "
          f"median {sizes[len(sizes) // 2] // 1000}, p90 {sizes[int(len(sizes) * 0.9)] // 1000}")
    chars = sum(context.values())
    table("what enters the main context (k chars)",
          [(s, n / 1e3, f"{pieces[s]} pieces") for s, n in context.most_common()], chars / 1e3)


if __name__ == "__main__":
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        sys.exit("usage: transcript-costs.py <transcripts folder>")
    main(sys.argv[1])
