#!/usr/bin/env python3
"""Classify warnings emitted by the CVA6 Vivado/XSim whole-core smoke."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


WARNING_RE = re.compile(r"(?:CRITICAL )?WARNING:", re.IGNORECASE)
UNSUPPORTED_ASSERTION_RE = re.compile(
    r"WARNING: \[XSIM 43-(?:4455|4127)\].*"
    r"(?:Unsupported feature in assertion/property/sequence|"
    r"System Verilog (?:Assertion|Assume).*not supported)",
    re.IGNORECASE,
)
ALLOWED_ASSERTION_PATHS = (
    "/core/cache_subsystem/hpdcache/",
    "/core/cache_subsystem/cva6_hpdcache_subsystem.sv",
    "/vendor/pulp-platform/axi/src/axi_pkg.sv",
)
RESET_UNIQUE_CASE_RE = re.compile(
    r"WARNING:\s+0ns\s+: none of the conditions were true for unique case from File:.*"
    r"/core/cache_subsystem/hpdcache/",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class WarningAudit:
    allowed: tuple[str, ...]
    actionable: tuple[str, ...]


def _normalized(line: str) -> str:
    return line.strip().replace("\\", "/")


def is_allowed_tool_warning(line: str, stage: str) -> bool:
    """Return true only for precisely scoped, known XSim limitations."""
    normalized = _normalized(line)
    if stage == "xelab":
        return bool(UNSUPPORTED_ASSERTION_RE.search(normalized)) and any(
            path in normalized for path in ALLOWED_ASSERTION_PATHS
        )
    if stage == "xsim":
        return bool(RESET_UNIQUE_CASE_RE.search(normalized))
    return False


def audit_warning_text(text: str, stage: str) -> WarningAudit:
    allowed: list[str] = []
    actionable: list[str] = []
    for raw_line in text.splitlines():
        if not WARNING_RE.search(raw_line):
            continue
        line = raw_line.strip()
        if is_allowed_tool_warning(line, stage):
            allowed.append(line)
        else:
            actionable.append(line)
    return WarningAudit(tuple(allowed), tuple(actionable))


def audit_warning_log(path: Path, stage: str) -> WarningAudit:
    return audit_warning_text(path.read_text(encoding="utf-8", errors="replace"), stage)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=("xvlog", "xelab", "xsim"))
    parser.add_argument("log", type=Path)
    args = parser.parse_args()

    audit = audit_warning_log(args.log, args.stage)
    print(
        f"{args.stage}: allowed_tool_warnings={len(audit.allowed)} "
        f"actionable_warnings={len(audit.actionable)}"
    )
    for warning in audit.actionable:
        print(f"ACTIONABLE: {warning}", file=sys.stderr)
    return 1 if audit.actionable else 0


if __name__ == "__main__":
    raise SystemExit(main())
