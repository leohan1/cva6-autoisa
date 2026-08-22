#!/usr/bin/env python3
"""Build and execute the minimal AutoISA D0 ELF on the real Ariane hierarchy."""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")
PASS_MARKER = "PASS: minimal AutoISA D0 ELF architectural closure"


def run(command: list[str], log: Path | None = None) -> subprocess.CompletedProcess[str]:
    print("$", " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(output, encoding="utf-8", newline="\n")
    for line in output.splitlines()[-12:]:
        print(line)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado", type=Path, default=DEFAULT_VIVADO)
    parser.add_argument("--toolchain", type=Path)
    args = parser.parse_args()

    build = ROOT / "ci/autoisa/build"
    python = sys.executable
    toolchain_cmd = [python, str(ROOT / "ci/autoisa/check_riscv_toolchain.py")]
    if args.toolchain:
        toolchain_cmd.extend(["--toolchain", str(args.toolchain)])
    if run(toolchain_cmd, build / "elf_toolchain.log").returncode:
        return 1
    if run([python, str(ROOT / "ci/autoisa/prepare_vivado_filelist.py"),
            "--ariane-elf"], build / "elf_prepare_filelist.log").returncode:
        return 1

    filelist = build / "cv32a65x_xsim.f"
    xvlog = str(args.vivado / "xvlog.bat")
    xelab = str(args.vivado / "xelab.bat")
    xsim = str(args.vivado / "xsim.bat")
    snapshot = "autoisa_ci_ariane_elf"
    steps = [
        ([xvlog, "-sv", "-d", "AUTOISA_CI_CVXIF", "-f", str(filelist)],
         build / "elf_xvlog.log"),
        ([xelab, "tb_autoisa_ci_ariane_elf", "-s", snapshot,
          "--timescale", "1ns/1ps"], build / "elf_xelab.log"),
        ([xsim, snapshot, "-runall"], build / "elf_xsim.log"),
    ]
    final_output = ""
    for command, log in steps:
        result = run(command, log)
        if result.returncode:
            print(f"ERROR: failed step; see {log}", file=sys.stderr)
            return 1
        final_output = result.stdout + result.stderr
    if PASS_MARKER not in final_output:
        print(f"ERROR: missing PASS marker; see {steps[-1][1]}", file=sys.stderr)
        return 1
    print("AutoISA minimal ELF smoke: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
