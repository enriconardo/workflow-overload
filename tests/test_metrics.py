"""Tests of metrics.py on a synthetic transcript folder: `python3 -m unittest
discover -s tests`. The lines carry only the fields metrics.py reads, in the
shapes Claude Code 2.1 writes them."""

import importlib.util
import json
import os
import re
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("metrics", os.path.join(HERE, "..", "plugins", "workflow-overload", "scripts", "metrics.py"))
metrics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metrics)


def usage(inp, write, read, out):
    return {"input_tokens": inp, "cache_creation_input_tokens": write, "cache_read_input_tokens": read, "output_tokens": out}


def assistant(uuid, branch, msg_id, use, content, ts="2026-11-09T10:00:00Z", model="claude-opus-5-5"):
    return {"type": "assistant", "uuid": uuid, "gitBranch": branch, "timestamp": ts,
            "message": {"id": msg_id, "model": model, "usage": use, "content": content}}


def user(uuid, branch, content, ts="2026-11-09T10:00:00Z", **extra):
    line = {"type": "user", "uuid": uuid, "gitBranch": branch, "timestamp": ts, "message": {"content": content}}
    line.update(extra)
    return line


class TranscriptsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        session = [
            user("u1", "main", "fix the README please", ts="2026-11-09T10:00:00Z"),
            # two lines of one response: usage counted once
            assistant("a1", "main", "m1", usage(10, 100, 0, 5), [{"type": "text", "text": "ok"}], ts="2026-11-09T10:00:05Z"),
            assistant("a1b", "main", "m1", usage(10, 100, 0, 20), [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "bash scripts/branch.sh"}}]),
            user("u2", "docs/readme/x", "<command-name>/overload</command-name><command-args>go</command-args>", ts="2026-11-09T10:01:00Z"),
            assistant("a2", "docs/readme/x", "m2", usage(1, 0, 1000, 10), [
                {"type": "tool_use", "id": "t2", "name": "Bash", "input": {"command": "bash /p/scripts/verify.sh"}},
                {"type": "tool_use", "id": "t3", "name": "Agent", "input": {"subagent_type": "workflow-overload:code-reviewer", "prompt": "x"}},
            ], ts="2026-11-09T10:02:00Z"),
            user("u3", "docs/readme/x", [{"type": "tool_result", "tool_use_id": "t2", "is_error": True, "content": "Exit code 1"}],
                 toolUseResult="Error: Exit code 1"),
            user("u4", "docs/readme/x", [{"type": "tool_result", "tool_use_id": "t3", "content": [{"type": "text", "text": "done"}]}],
                 toolUseResult={"agentId": "abc", "agentType": "workflow-overload:code-reviewer"}),
            user("u5", "docs/readme/x", "[Request interrupted by user]"),
        ]
        with open(os.path.join(self.dir, "s1.jsonl"), "w") as handle:
            for line in session:
                handle.write(json.dumps(line) + "\n")
        sub = os.path.join(self.dir, "s1", "subagents")
        os.makedirs(sub)
        with open(os.path.join(sub, "agent-abc.jsonl"), "w") as handle:
            handle.write(json.dumps(assistant("x1", "docs/readme/x", "m9", usage(2, 50, 500, 30), [], model="claude-sonnet-5-5")) + "\n")
        with open(os.path.join(sub, "agent-abc.meta.json"), "w") as handle:
            json.dump({"agentType": "workflow-overload:code-reviewer"}, handle)

    def records(self):
        rows = metrics.collect_transcripts(self.dir, "main", __import__("re").compile(r"\bverify\.sh\b"), {"overload"})
        return {r["branch"]: r for r in rows}

    def test_main_lines_go_to_the_next_task_branch(self):
        rows = self.records()
        self.assertEqual(list(rows), ["docs/readme/x"])

    def test_usage_is_counted_once_per_response_by_phase(self):
        roles = self.records()["docs/readme/x"]["roles"]
        self.assertEqual(roles["main/intake"]["requests"], 1)
        self.assertEqual(roles["main/intake"]["output"], 20)
        self.assertEqual(roles["main/overload"]["cache_read"], 1000)

    def test_subagent_tokens_go_to_its_type(self):
        role = self.records()["docs/readme/x"]["roles"]["agent/workflow-overload:code-reviewer"]
        self.assertEqual(role["runs"], 1)
        self.assertEqual(role["output"], 30)
        self.assertIn("claude-sonnet-5-5", role["by_model"])

    def test_human_prompts_commands_interrupts_and_red_verify(self):
        r = self.records()["docs/readme/x"]
        self.assertEqual(r["human"]["prompts"], 2)
        self.assertEqual(r["human"]["interrupts"], 1)
        self.assertEqual(r["human"]["commands"], {"/overload": 1})
        self.assertEqual(r["verify"]["runs"], 1)
        self.assertEqual(r["verify"]["red"], 1)

    def test_verify_default_matches_only_the_plugins_steps(self):
        verify_re = __import__("re").compile(metrics.VERIFY_RE)
        for command in ["bash /p/scripts/verify.sh", "bash /p/scripts/integrate.sh", "cd x && bash ../scripts/verify.sh 2>&1"]:
            self.assertRegex(command, verify_re)
        for command in ["pnpm verify", "./dev.sh exec pnpm run verify:all", "bash scripts/verify-docs.sh", "make verify"]:
            self.assertNotRegex(command, verify_re)

    def test_a_piped_step_is_flagged(self):
        self.assertRegex("bash /p/scripts/verify.sh | tail -5", metrics.PIPED_RE)
        self.assertRegex("bash /p/scripts/integrate.sh 2>&1 | tail", metrics.PIPED_RE)
        self.assertNotRegex("bash /p/scripts/verify.sh || echo red", metrics.PIPED_RE)
        self.assertNotRegex("pnpm verify:all | tail", metrics.PIPED_RE)

    def test_weighted_uses_price_ratios(self):
        bucket = {"input": 10, "cache_write": 100, "cache_read": 1000, "output": 2}
        self.assertEqual(metrics.weighted(bucket), 10 + 125 + 100 + 10)


class GitTest(unittest.TestCase):
    def git(self, *args):
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "-C", self.repo] + list(args),
                       check=True, capture_output=True, env=env)

    def setUp(self):
        self.repo = tempfile.mkdtemp()
        self.git("init", "-q", "-b", "main")
        self.git("commit", "-q", "--allow-empty", "-m", "start")
        self.git("switch", "-q", "-c", "EN-209-snapshot-diff")
        with open(os.path.join(self.repo, "a.txt"), "w") as handle:
            handle.write("a\n")
        self.git("add", "a.txt")
        self.git("commit", "-q", "-m", "add a")
        self.git("switch", "-q", "main")
        self.git("merge", "-q", "--no-ff", "-m", "Merge branch 'EN-209-snapshot-diff'", "EN-209-snapshot-diff")

    def test_a_merge_is_read_with_its_branch_name_whole(self):
        rows = metrics.collect_git(self.repo, "main", r"\.workflow/specs/.*\.md", re.compile("review"), re.compile("critic"), re.compile(r"\.test\."))
        self.assertEqual([r["branch"] for r in rows], ["EN-209-snapshot-diff"])
        self.assertEqual(rows[0]["commits"], 1)
        self.assertNotIn("type", rows[0])


if __name__ == "__main__":
    unittest.main()
