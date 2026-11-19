#!/usr/bin/env python3
"""Print /test results in the fixed pass/fail format.

Input is a JSON file (a list of results, or an object with a "results" list)
or a TSV file with the columns: status, name, detail, where, seconds.
Use "-" to read from stdin.

Each result has:
  status   PASS, FAIL, WARN, SKIP, or TIP
  name     short check name, one line
  detail   plain words: what failed (FAIL), or why (WARN, SKIP)
  where    optional file:line or resource name
  seconds  optional run time of the check

Output:
  one line per check, 1-2 detail lines per FAIL, 1 per WARN or SKIP,
  then up to 2 TIP lines (a recommended check, not counted in the totals),
  then one totals line with the run time and the log path.

Exit code: 1 if any check failed, 2 for bad input, else 0.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import sys

STATUSES = ("PASS", "FAIL", "WARN", "SKIP", "TIP")
MARKS = {"PASS": "✅", "FAIL": "❌", "WARN": "⚠️ ", "SKIP": "⏭️ ", "TIP": "💡"}
COLOURS = {"PASS": "32", "FAIL": "31", "WARN": "33", "SKIP": "33", "TIP": "36"}
LABELS = {"TIP": "TIP "}
DETAIL_LINES = {"PASS": 0, "FAIL": 2, "WARN": 1, "SKIP": 1, "TIP": 0}
MAX_TIPS = 2
MAX_WIDTH = 110
INDENT = " " * 9

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
CONTROL_RE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


def clean(text: object) -> str:
    """Remove ANSI codes and control characters, keep newlines."""
    if text is None:
        return ""
    value = ANSI_RE.sub("", str(text)).replace("\r\n", "\n").replace("\t", " ")
    return CONTROL_RE.sub("", value)


def one_line(text: str, width: int = MAX_WIDTH) -> str:
    value = " ".join(text.split())
    return value if len(value) <= width else value[: width - 1].rstrip() + "…"


def fmt_seconds(total: float) -> str:
    if total < 1:
        return "under 1 s"
    seconds = round(total)
    if seconds < 60:
        return f"{seconds} s"
    minutes, rest = divmod(seconds, 60)
    return f"{minutes} min {rest} s" if rest else f"{minutes} min"


def load(path: str) -> tuple[list[dict], dict]:
    raw = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    stripped = raw.lstrip()
    if stripped.startswith(("[", "{")):
        data = json.loads(raw)
        if isinstance(data, dict):
            return list(data.get("results", [])), data
        return list(data), {}
    rows = []
    for row in csv.reader(io.StringIO(raw), delimiter="\t"):
        if not row or not row[0].strip() or row[0].startswith("#"):
            continue
        if row[0].strip().lower() == "status":
            continue  # header row
        row += [""] * (5 - len(row))
        rows.append(
            {"status": row[0], "name": row[1], "detail": row[2].replace("\\n", "\n"),
             "where": row[3], "seconds": row[4]}
        )
    return rows, {}


def normalise(item: dict, index: int) -> dict:
    status = clean(item.get("status", "")).strip().upper()
    if status not in STATUSES:
        raise ValueError(f"result {index + 1}: status must be one of {', '.join(STATUSES)}, not {status!r}")
    name = one_line(clean(item.get("name", "")))
    if not name:
        raise ValueError(f"result {index + 1}: name is empty")
    try:
        seconds = float(item.get("seconds") or 0)
    except (TypeError, ValueError):
        seconds = 0.0
    return {
        "status": status,
        "name": name,
        "detail": clean(item.get("detail", "")).strip(),
        "where": one_line(clean(item.get("where", ""))),
        "seconds": seconds,
    }


def detail_lines(result: dict) -> list[str]:
    limit = DETAIL_LINES[result["status"]]
    if limit == 0:
        return []
    lines = [one_line(line) for line in result["detail"].split("\n") if line.strip()]
    if result["where"]:
        first = lines[0] if lines else ""
        lines = [f"{result['where']}  {first}".rstrip()] + lines[1:]
        if len(lines[0]) > MAX_WIDTH:
            lines[0] = lines[0][: MAX_WIDTH - 1].rstrip() + "…"
    if len(lines) > limit:
        lines = lines[:limit]
        if not lines[-1].endswith("…"):
            lines[-1] = one_line(lines[-1] + " …")
    return lines


def render(results: list[dict], log: str, total_seconds: float | None, colour: bool) -> str:
    def paint(code: str, text: str) -> str:
        return f"\x1b[{code}m{text}\x1b[0m" if colour else text

    out = []
    counts = {status: 0 for status in STATUSES}
    checks = [r for r in results if r["status"] != "TIP"]
    tips = [r for r in results if r["status"] == "TIP"][:MAX_TIPS]
    for result in checks + tips:
        status = result["status"]
        counts[status] += 1
        label = paint("1;" + COLOURS[status], LABELS.get(status, status))
        out.append(f"{MARKS[status]} {label}  {result['name']}")
        for line in detail_lines(result):
            out.append(INDENT + (paint("2", line) if status != "FAIL" else line))

    seconds = total_seconds if total_seconds is not None else sum(r["seconds"] for r in checks)
    parts = [f"{counts['PASS']} passed", f"{counts['FAIL']} failed"]
    if counts["WARN"]:
        parts.append(f"{counts['WARN']} warned")
    if counts["SKIP"]:
        parts.append(f"{counts['SKIP']} skipped")
    parts.append(fmt_seconds(seconds))
    if log:
        parts.append(f"log: {log}")
    summary = " · ".join(parts)
    if counts["FAIL"]:
        summary = paint("1;31", summary)
    elif counts["WARN"] or counts["SKIP"] or not checks:
        summary = paint("1;33", summary)
    else:
        summary = paint("1;32", summary)
    out.append(summary)
    return "\n".join(out)


def use_colour(plain: bool, force: bool = False) -> bool:
    """--plain wins, then --color or FORCE_COLOR, then NO_COLOR. Default: colour on."""
    if plain:
        return False
    if force or os.environ.get("FORCE_COLOR", "0") not in ("", "0"):
        return True
    return not os.environ.get("NO_COLOR")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Print /test results as coloured pass/fail lines.")
    parser.add_argument("results", help="JSON or TSV results file, or - for stdin")
    parser.add_argument("--log", default=None, help="log file path for the last line")
    parser.add_argument("--seconds", type=float, default=None, help="total run time (default: sum of checks)")
    parser.add_argument("--plain", action="store_true", help="no ANSI colours")
    parser.add_argument("--color", action="store_true", help="ANSI colours even if NO_COLOR is set")
    args = parser.parse_args(argv)

    try:
        items, meta = load(args.results)
        results = [normalise(item, i) for i, item in enumerate(items)]
    except (OSError, ValueError) as error:
        print(f"report.py: {error}", file=sys.stderr)
        return 2

    log = args.log if args.log is not None else clean(meta.get("log", ""))
    log = os.path.normpath(log) if log else ""
    total = args.seconds if args.seconds is not None else meta.get("seconds")
    colour = use_colour(args.plain, args.color)
    print(render(results, log, float(total) if total is not None else None, colour))
    return 1 if any(r["status"] == "FAIL" for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
