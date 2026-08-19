#!/usr/bin/env python3
"""Audit Q00-Q15 coverage against current XSim logs and random summaries."""

import json
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
MATRIX = HERE / "q00_q15_coverage.json"
LOG_DIR = HERE / "logs"


def fail(message: str) -> int:
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def main() -> int:
    matrix = json.loads(MATRIX.read_text(encoding="utf-8"))
    requirements = matrix.get("requirements", {})
    expected = {f"Q{i:02d}" for i in range(16)}
    actual = set(requirements)
    if actual != expected:
        return fail(f"requirement IDs differ: missing={sorted(expected-actual)}, extra={sorted(actual-expected)}")

    evidence_names = set()
    for qid in sorted(expected):
        entry = requirements[qid]
        if entry.get("status") != "covered":
            return fail(f"{qid} is not covered")
        evidence = entry.get("evidence", [])
        if not evidence or not entry.get("check"):
            return fail(f"{qid} lacks evidence or a check description")
        evidence_names.update(evidence)

    for name in sorted(evidence_names):
        log_path = LOG_DIR / f"{name}.log"
        if not log_path.is_file():
            return fail(f"missing XSim evidence log: {log_path}")
        transcript = log_path.read_text(encoding="utf-8", errors="replace")
        if "PASS:" not in transcript:
            return fail(f"PASS marker missing from {log_path.name}")

    for name in ("autoisa_ci_random_100k", "autoisa_ci_random_100k_multi"):
        summary_path = LOG_DIR / f"{name}.json"
        if not summary_path.is_file():
            return fail(f"missing random summary: {summary_path}")
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        if summary.get("stimulus_cycles") != 100000:
            return fail(f"{name}: stimulus_cycles is not 100000")
        if summary.get("errors") != 0:
            return fail(f"{name}: errors is not zero")
        if summary.get("accepted") != summary.get("retired") + summary.get("killed"):
            return fail(f"{name}: accepted != retired + killed")

    print(f"PASS: autoisa_ci_q00_q15_coverage ({len(expected)} requirements, {len(evidence_names)} evidence logs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
