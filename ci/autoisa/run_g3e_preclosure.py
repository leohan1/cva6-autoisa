#!/usr/bin/env python3
"""Run the reference-backed Extended G3E pre-closure gate."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado", type=Path, default=DEFAULT_VIVADO)
    parser.add_argument(
        "--summary",
        type=Path,
        default=ROOT / "ci/autoisa/build/g3e_preclosure_summary.json",
    )
    args = parser.parse_args()
    started = datetime.now(timezone.utc).isoformat()
    start_time = time.monotonic()
    steps = [
        (
            "reference-oracle",
            [sys.executable, str(ROOT / "ci/autoisa/generate_g3e_oracle.py")],
        ),
        (
            "contract-tests",
            [sys.executable, "-m", "unittest", "-v",
             "tests.autoisa.test_g3e_preclosure",
             "tests.autoisa.test_g4_closure"],
        ),
        (
            "extended-transport-architectural-model",
            [sys.executable, str(ROOT / "ci/autoisa/run_ci.py"),
             "--vivado", str(args.vivado), "--tb", "autoisa_ci_g3e_preclosure",
             "--skip-layout-generate", "--skip-semantic-generate"],
        ),
    ]
    results: list[dict[str, object]] = []
    passed = True
    for name, command in steps:
        print(f"\n=== G3E pre-closure: {name} ===", flush=True)
        print("$", " ".join(command), flush=True)
        step_start = time.monotonic()
        result = subprocess.run(command, cwd=ROOT)
        results.append({
            "name": name,
            "command": command,
            "returncode": result.returncode,
            "duration_seconds": round(time.monotonic() - step_start, 3),
        })
        if result.returncode:
            passed = False
            break

    oracle_manifest = ROOT / "generated/g3e/generation_manifest.json"
    oracle = (
        json.loads(oracle_manifest.read_text(encoding="utf-8"))
        if oracle_manifest.exists() else {}
    )
    summary = {
        "schema_version": "1.0",
        "gate": "G3E-preclosure",
        "status": "PASS" if passed else "FAIL",
        "scope": "P3-P7 Extended sidecar plus architectural GPR model",
        "whole_core_integrated": False,
        "profile_count": oracle.get("profile_count", 0),
        "vector_sha256": oracle.get("vector_sha256", ""),
        "started_utc": started,
        "duration_seconds": round(time.monotonic() - start_time, 3),
        "steps": results,
    }
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8", newline="\n"
    )
    print(f"G3E summary: {args.summary.resolve()}")
    if passed:
        print("PASS: Extended G3E pre-closure (whole-core integration remains open)")
        return 0
    print("FAIL: Extended G3E pre-closure", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
