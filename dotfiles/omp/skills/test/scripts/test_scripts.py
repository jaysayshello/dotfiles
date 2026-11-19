#!/usr/bin/env python3
"""Tests for report.py and run_checks.py. Run: python3 scripts/test_scripts.py"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORT = HERE / "report.py"
RUNNER = HERE / "run_checks.py"


def run(script: Path, *args: str, stdin: str | None = None) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if k != "NO_COLOR"}
    return subprocess.run(
        [sys.executable, str(script), *args], input=stdin, capture_output=True, text=True, timeout=60, env=env
    )


class ReportTest(unittest.TestCase):
    def test_fixed_format_plain(self):
        results = [
            {"status": "PASS", "name": "render diff changes only the sidecar image", "seconds": 2},
            {"status": "FAIL", "name": "image signature", "where": "values.yaml:14",
             "detail": "The new tag has no signature.\nSign it, or pin the signed digest.\nthird line is cut"},
            {"status": "SKIP", "name": "kind cluster test", "detail": "Docker is not on."},
        ]
        out = run(REPORT, "-", "--plain", "--log", "/tmp/r.log", stdin=json.dumps(results))
        self.assertEqual(out.returncode, 1)
        self.assertEqual(
            out.stdout.splitlines(),
            [
                "✅ PASS  render diff changes only the sidecar image",
                "❌ FAIL  image signature",
                "         values.yaml:14  The new tag has no signature.",
                "         Sign it, or pin the signed digest. …",
                "⏭️  SKIP  kind cluster test",
                "         Docker is not on.",
                "1 passed · 1 failed · 1 skipped · 2 s · log: /tmp/r.log",
            ],
        )

    def test_colours_on_by_default_and_off_with_no_color(self):
        data = json.dumps([{"status": "PASS", "name": "a"}, {"status": "FAIL", "name": "b", "detail": "x"}])
        coloured = run(REPORT, "-", stdin=data).stdout
        self.assertIn("\x1b[1;32mPASS\x1b[0m", coloured)
        self.assertIn("\x1b[1;31mFAIL\x1b[0m", coloured)
        no_color_env = {"NO_COLOR": "1", "PATH": "/usr/bin:/bin"}
        plain = subprocess.run([sys.executable, str(REPORT), "-"], input=data, capture_output=True,
                               text=True, env=no_color_env).stdout
        self.assertNotIn("\x1b[", plain)
        forced = subprocess.run([sys.executable, str(REPORT), "-", "--color"], input=data, capture_output=True,
                                text=True, env=no_color_env).stdout
        self.assertIn("\x1b[1;31mFAIL\x1b[0m", forced)

    def test_tsv_input_and_all_pass_exit_zero(self):
        tsv = "status\tname\tdetail\twhere\tseconds\nPASS\tunit tests\t\t\t3.4\nWARN\tlint\tslow\t\t65\n"
        out = run(REPORT, "-", "--plain", stdin=tsv)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout.splitlines()[-1], "1 passed · 0 failed · 1 warned · 1 min 8 s")

    def test_ansi_and_long_lines_are_cleaned(self):
        data = json.dumps([{"status": "FAIL", "name": "x", "detail": "\x1b[31m" + "word " * 60}])
        line = run(REPORT, "-", "--plain", stdin=data).stdout.splitlines()[1]
        self.assertNotIn("\x1b", line)
        self.assertLessEqual(len(line.strip()), 110)
        self.assertTrue(line.endswith("…"))

    def test_tips_go_last_and_do_not_count(self):
        data = json.dumps([
            {"status": "TIP", "name": "add a kind test for the new image"},
            {"status": "PASS", "name": "render diff", "seconds": 2},
            {"status": "TIP", "name": "second tip"},
            {"status": "TIP", "name": "third tip is dropped"},
        ])
        out = run(REPORT, "-", "--plain", stdin=data)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout.splitlines(), [
            "✅ PASS  render diff",
            "💡 TIP   add a kind test for the new image",
            "💡 TIP   second tip",
            "1 passed · 0 failed · 2 s",
        ])

    def test_bad_status_is_rejected(self):
        out = run(REPORT, "-", stdin=json.dumps([{"status": "OK", "name": "x"}]))
        self.assertEqual(out.returncode, 2)
        self.assertIn("status must be one of", out.stderr)


class RunnerTest(unittest.TestCase):
    def plan(self, tmp: str, checks: list[dict], budget: float = 300) -> Path:
        path = Path(tmp) / "plan.json"
        path.write_text(json.dumps({"budget": budget, "log": str(Path(tmp) / "run.log"), "checks": checks}))
        return path

    def test_pass_fail_expect_and_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = self.plan(tmp, [
                {"name": "passes", "cmd": "echo hidden-output"},
                {"name": "fails on base as it should", "cmd": "exit 3", "expect": "fail"},
                {"name": "fails", "cmd": "echo 'Error: boom'; exit 1"},
                {"name": "fails with hint", "cmd": "exit 1", "on_fail": "The tag is not signed.", "where": "a.yaml:2"},
                {"name": "red check passes by mistake", "cmd": "true", "expect": "fail"},
            ])
            out = run(RUNNER, "--plain", str(plan))
            lines = out.stdout.splitlines()
            self.assertEqual(out.returncode, 1)
            self.assertNotIn("hidden-output", out.stdout)
            self.assertIn("hidden-output", (Path(tmp) / "run.log").read_text())
            self.assertEqual(lines[0], "✅ PASS  passes")
            self.assertEqual(lines[1], "✅ PASS  fails on base as it should")
            self.assertEqual(lines[3], "         Error: boom")
            self.assertEqual(lines[5], "         a.yaml:2  The tag is not signed.")
            self.assertIn("does not prove the change", lines[7])
            self.assertTrue(lines[-1].startswith("2 passed · 3 failed · "))
            self.assertTrue(lines[-1].endswith(f"log: {Path(tmp) / 'run.log'}"))
            saved = json.loads((Path(tmp) / "run.json").read_text())
            self.assertEqual(len(saved["results"]), 5)

    def test_timeout_warns_and_budget_skips(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = self.plan(tmp, [
                {"name": "slow", "cmd": "sleep 30", "timeout": 1},
                {"name": "never runs", "cmd": "true"},
                {"name": "skipped on purpose", "skip": "No cluster access."},
            ], budget=1)
            out = run(RUNNER, "--plain", str(plan))
            lines = out.stdout.splitlines()
            self.assertEqual(out.returncode, 0)
            self.assertEqual(lines[0], "⚠️  WARN  slow")
            self.assertIn("Stopped after 1 s", lines[1])
            self.assertEqual(lines[2], "⏭️  SKIP  never runs")
            self.assertIn("time limit", lines[3])
            self.assertEqual(lines[4], "⏭️  SKIP  skipped on purpose")


if __name__ == "__main__":
    unittest.main(verbosity=1)
