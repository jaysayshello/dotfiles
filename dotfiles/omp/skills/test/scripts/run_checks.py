#!/usr/bin/env python3
"""Run a /test plan, write the logs to a file, and print the report.

Plan (JSON):
{
  "budget": 300,                 # seconds for the full run (default 300)
  "log": "/tmp/x.log",           # optional; default $TMPDIR/test-runs/<dir>-<time>.log
  "checks": [
    {
      "name": "render diff changes only the sidecar image",
      "cmd": "make test",        # run with bash -c, from the directory where you start the runner
      "cwd": "path",             # optional, relative to that directory (for example a base worktree)
      "expect": "pass",          # "pass" (exit 0 is good) or "fail" (non-zero is good)
      "timeout": 60,             # seconds (default 60)
      "on_fail": "plain words",  # optional detail to show if the check fails
      "where": "values.yaml:14", # optional file:line or resource
      "skip": "reason"           # optional: do not run, report SKIP with this reason
    }
  ]
}

The command output goes only to the log. A results JSON file is written next
to the log, so report.py can print it again after you edit a detail line.
Exit code: 1 if any check failed, 2 for a bad plan, else 0.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import report  # noqa: E402

DEFAULT_TIMEOUT = 60
DEFAULT_BUDGET = 300


def default_log() -> Path:
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "test-runs"
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return base / f"{Path.cwd().name or 'run'}-{stamp}.log"


def last_line(output: str) -> str:
    for line in reversed(report.clean(output).splitlines()):
        if line.strip():
            return line.strip()
    return ""


def git_state(cwd: Path) -> str:
    """Commit and dirty state, so the log shows which code the run checked."""
    try:
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=cwd, capture_output=True,
                             text=True, timeout=5).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=cwd, capture_output=True,
                               text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "commit=none"
    if not sha:
        return "commit=none"
    return f"commit={sha}" + (" with uncommitted changes" if dirty else "")


def run_one(check: dict, base_dir: Path, log, remaining: float) -> dict:
    name = check["name"]
    result = {"status": "PASS", "name": name, "detail": "", "where": check.get("where", ""), "seconds": 0.0}
    if check.get("skip"):
        result.update(status="SKIP", detail=check["skip"])
        log.write(f"\n=== SKIP {name}: {check['skip']}\n")
        return result
    timeout = float(check.get("timeout", DEFAULT_TIMEOUT))
    if remaining <= 0:
        result.update(status="SKIP", detail="Not run: the time limit for the full run is used.")
        log.write(f"\n=== SKIP {name}: time limit for the run is used\n")
        return result
    limit = min(timeout, remaining)
    expect = check.get("expect", "pass")
    cwd = (base_dir / check["cwd"]).resolve() if check.get("cwd") else base_dir
    log.write(f"\n=== RUN {name}\n$ cd {cwd}\n$ {check['cmd']}\n")
    log.flush()

    start = time.monotonic()
    proc = subprocess.Popen(
        ["bash", "-c", check["cmd"]], cwd=cwd, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        errors="replace", start_new_session=True,
    )
    try:
        output, _ = proc.communicate(timeout=limit)
        timed_out = False
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        output, _ = proc.communicate()
        timed_out = True
    result["seconds"] = time.monotonic() - start
    log.write(output or "")
    log.write(f"\n=== exit {proc.returncode} after {result['seconds']:.1f}s{' (timeout)' if timed_out else ''}\n")

    if timed_out:
        result.update(
            status="WARN",
            detail=f"Stopped after {round(limit)} s. Use a smaller check, or permit a longer time.",
        )
        return result
    good = proc.returncode == 0 if expect == "pass" else proc.returncode != 0
    if good:
        return result
    if check.get("on_fail"):
        detail = check["on_fail"]
    elif expect == "fail":
        detail = "This check passed without the change, so it does not prove the change."
    else:
        detail = last_line(output) or f"The command stopped with exit code {proc.returncode}."
    result.update(status="FAIL", detail=detail)
    return result


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    plain = "--plain" in args
    force = "--color" in args
    paths = [a for a in args if a not in ("--plain", "--color")]
    if len(paths) != 1:
        print("usage: run_checks.py [--plain | --color] plan.json", file=sys.stderr)
        return 2
    plan_path = Path(paths[0]).resolve()
    try:
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
        checks = plan["checks"]
        for i, check in enumerate(checks):
            if not check.get("name") or not (check.get("cmd") or check.get("skip")):
                raise ValueError(f"check {i + 1} needs a name and a cmd (or a skip reason)")
            if check.get("expect", "pass") not in ("pass", "fail"):
                raise ValueError(f"check {i + 1}: expect must be pass or fail")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"run_checks.py: bad plan: {error}", file=sys.stderr)
        return 2

    log_path = Path(plan.get("log") or default_log())
    log_path.parent.mkdir(parents=True, exist_ok=True)
    budget = float(plan.get("budget", DEFAULT_BUDGET))
    results = []
    start = time.monotonic()
    base_dir = Path.cwd()
    with open(log_path, "w", encoding="utf-8") as log:
        log.write(f"/test run {datetime.now().isoformat(timespec='seconds')} plan={plan_path}\n")
        log.write(f"cwd={base_dir} {git_state(base_dir)}\n")
        for check in checks:
            remaining = budget - (time.monotonic() - start)
            results.append(run_one(check, base_dir, log, remaining))
    total = time.monotonic() - start

    results_path = log_path.with_suffix(".json")
    results_path.write_text(
        json.dumps({"results": results, "log": str(log_path), "seconds": round(total, 1)}, indent=2),
        encoding="utf-8",
    )
    normalised = [report.normalise(r, i) for i, r in enumerate(results)]
    print(report.render(normalised, str(log_path), total, report.use_colour(plain, force)))
    return 1 if any(r["status"] == "FAIL" for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
