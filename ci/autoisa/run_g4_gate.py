#!/usr/bin/env python3
"""Run the blocking AutoISA G4 cross-layer semantic closure gate."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")


def gate_commands(python: str, vivado: Path, toolchain: Path | None) -> list[tuple[str, list[str]]]:
    g3 = [python, str(ROOT / "ci/autoisa/run_g3_gate.py"), "--vivado", str(vivado)]
    if toolchain is not None:
        g3.extend(["--toolchain", str(toolchain)])
    return [
        (
            "contract-mutation-closure",
            [python, "-m", "unittest", "-v", "tests.autoisa.test_g4_closure",
             "tests.autoisa.test_semantic_generator"],
        ),
        (
            "rtl-reference-differential",
            [python, str(ROOT / "ci/autoisa/run_semantic_diff.py"),
             "--vivado", str(vivado)],
        ),
        ("g3-program-signature-closure", g3),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--vivado", type=Path,
        default=Path(os.environ.get("AUTOISA_VIVADO_BIN") or DEFAULT_VIVADO),
    )
    parser.add_argument(
        "--toolchain", type=Path,
        default=(Path(os.environ["AUTOISA_RISCV_TOOLCHAIN"])
                 if os.environ.get("AUTOISA_RISCV_TOOLCHAIN") else None),
    )
    parser.add_argument(
        "--summary", type=Path,
        default=ROOT / "ci/autoisa/build/g4_gate_summary.json",
    )
    args = parser.parse_args()
    started = datetime.now(timezone.utc).isoformat()
    start_time = time.monotonic()
    results: list[dict[str, object]] = []
    passed = True
    for name, command in gate_commands(sys.executable, args.vivado, args.toolchain):
        print(f"\n=== G4: {name} ===", flush=True)
        print("$", " ".join(command), flush=True)
        step_start = time.monotonic()
        try:
            returncode = subprocess.run(command, cwd=ROOT).returncode
        except OSError as error:
            print(f"ERROR: cannot start {name}: {error}", file=sys.stderr)
            returncode = 127
        results.append({
            "name": name,
            "command": command,
            "returncode": returncode,
            "duration_seconds": round(time.monotonic() - step_start, 3),
        })
        if returncode:
            passed = False
            break
    summary = {
        "schema_version": 1,
        "gate": "G4",
        "name": "AutoISA cross-layer semantic closure",
        "status": "PASS" if passed else "FAIL",
        "started_utc": started,
        "duration_seconds": round(time.monotonic() - start_time, 3),
        "git_sha": os.environ.get("GITHUB_SHA", ""),
        "steps": results,
    }
    summary_path = args.summary.resolve()
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"G4 summary: {summary_path}")
    print(f"{'PASS' if passed else 'FAIL'}: AutoISA G4 cross-layer semantic closure")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
