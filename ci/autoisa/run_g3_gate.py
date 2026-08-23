#!/usr/bin/env python3
"""Run the blocking AutoISA G3 program-level integration gate."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")


@dataclass(frozen=True)
class GateStep:
    name: str
    command: list[str]


def gate_steps(python: str, vivado: Path, toolchain: Path | None) -> list[GateStep]:
    elf_command = [
        python,
        str(ROOT / "ci/autoisa/run_autoisa_elf_smoke.py"),
        "--vivado",
        str(vivado),
    ]
    if toolchain is not None:
        elf_command.extend(["--toolchain", str(toolchain)])
    return [
        GateStep(
            "layout-g0",
            [python, "-m", "unittest", "-v",
             "tests.autoisa.layout.test_layout_generator"],
        ),
        GateStep(
            "source-manifest",
            [python, str(ROOT / "ci/autoisa/check_source_manifest.py")],
        ),
        GateStep("minimal-elf", elf_command),
    ]


def execute_gate(steps: list[GateStep], summary_path: Path) -> int:
    started = datetime.now(timezone.utc).isoformat()
    start_time = time.monotonic()
    results: list[dict[str, object]] = []
    passed = True

    for step in steps:
        print(f"\n=== G3: {step.name} ===", flush=True)
        print("$", " ".join(step.command), flush=True)
        step_start = time.monotonic()
        try:
            returncode = subprocess.run(step.command, cwd=ROOT).returncode
        except OSError as error:
            print(f"ERROR: cannot start {step.name}: {error}", file=sys.stderr)
            returncode = 127
        results.append({
            "name": step.name,
            "command": step.command,
            "returncode": returncode,
            "duration_seconds": round(time.monotonic() - step_start, 3),
        })
        if returncode != 0:
            passed = False
            print(f"FAIL: G3 stopped at {step.name}", file=sys.stderr)
            break

    summary = {
        "schema_version": 1,
        "gate": "G3",
        "name": "AutoISA minimal ELF program gate",
        "status": "PASS" if passed else "FAIL",
        "started_utc": started,
        "duration_seconds": round(time.monotonic() - start_time, 3),
        "git_sha": os.environ.get("GITHUB_SHA", ""),
        "steps": results,
    }
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    print(f"G3 summary: {summary_path}")
    print(f"{'PASS' if passed else 'FAIL'}: AutoISA G3 program-level gate")
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    default_vivado = Path(os.environ.get("AUTOISA_VIVADO_BIN") or DEFAULT_VIVADO)
    parser.add_argument(
        "--vivado",
        type=Path,
        default=default_vivado,
    )
    parser.add_argument(
        "--toolchain",
        type=Path,
        default=(Path(os.environ["AUTOISA_RISCV_TOOLCHAIN"])
                 if os.environ.get("AUTOISA_RISCV_TOOLCHAIN") else None),
    )
    parser.add_argument(
        "--summary",
        type=Path,
        default=ROOT / "ci/autoisa/build/g3_gate_summary.json",
    )
    args = parser.parse_args()
    return execute_gate(gate_steps(sys.executable, args.vivado, args.toolchain),
                        args.summary.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
