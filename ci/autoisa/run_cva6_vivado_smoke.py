#!/usr/bin/env python3
"""Build and run stock/control and AutoISA cv32a65x Ariane smoke tests."""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from check_cva6_warnings import audit_warning_log

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")


def run(command: list[str], log: Path) -> bool:
    print("$", " ".join(command))
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(result.stdout + result.stderr, encoding="utf-8")
    tail = (result.stdout + result.stderr).splitlines()[-8:]
    print("\n".join(tail))
    return result.returncode == 0


def warnings_ok(log: Path, stage: str) -> bool:
    audit = audit_warning_log(log, stage)
    print(
        f"{stage}: allowed_tool_warnings={len(audit.allowed)} "
        f"actionable_warnings={len(audit.actionable)}"
    )
    for warning in audit.actionable:
        print(f"ACTIONABLE: {warning}")
    return not audit.actionable


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vivado", type=Path, default=DEFAULT_VIVADO)
    parser.add_argument(
        "--mode", choices=("all", "stock", "autoisa", "autoisa-3r"), default="all"
    )
    parser.add_argument("--exact-stock-example", action="store_true",
                        help="retain COPRO_EXAMPLE (known to crash xelab 2025.2)")
    args = parser.parse_args()

    build = ROOT / "ci/autoisa/build"
    filelist = build / "cv32a65x_xsim.f"
    python = sys.executable
    if not run([python, str(ROOT / "ci/autoisa/prepare_vivado_filelist.py"), "--ariane"],
               build / "prepare_filelist.log"):
        return 1

    xvlog = str(args.vivado / "xvlog.bat")
    xelab = str(args.vivado / "xelab.bat")
    xsim = str(args.vivado / "xsim.bat")
    modes = (
        ("stock", "autoisa", "autoisa-3r")
        if args.mode == "all"
        else (args.mode,)
    )
    for mode in modes:
        defines: list[str] = []
        if mode == "autoisa":
            defines = ["-d", "AUTOISA_CI_CVXIF"]
        elif mode == "autoisa-3r":
            defines = ["-d", "AUTOISA_CI_CVXIF", "-d", "AUTOISA_CI_3R"]
        elif args.exact_stock_example:
            defines = ["-d", "AUTOISA_STOCK_EXAMPLE"]
        snapshot = {
            "stock": "autoisa_stock_ariane",
            "autoisa": "autoisa_ci_ariane",
            "autoisa-3r": "autoisa_ci_ariane_3r",
        }[mode]
        xvlog_log = build / f"{mode}_xvlog.log"
        if not run([xvlog, "-sv", *defines, "-f", str(filelist)], xvlog_log):
            return 1
        if not warnings_ok(xvlog_log, "xvlog"):
            return 1
        xelab_log = build / f"{mode}_xelab.log"
        if not run([xelab, "tb_autoisa_ci_ariane_smoke", "-s", snapshot,
                    "--timescale", "1ns/1ps"], xelab_log):
            return 1
        if not warnings_ok(xelab_log, "xelab"):
            return 1
        sim_log = build / f"{mode}_xsim.log"
        if not run([xsim, snapshot, "-runall"], sim_log):
            return 1
        if not warnings_ok(sim_log, "xsim"):
            return 1
        if "PASS: cv32a65x Ariane reset smoke completed" not in sim_log.read_text(encoding="utf-8"):
            print(f"{mode}: no PASS marker")
            return 1
        print(f"{mode}: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
