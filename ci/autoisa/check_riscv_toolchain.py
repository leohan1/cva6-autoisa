#!/usr/bin/env python3
"""Locate a bare-metal RISC-V toolchain and build the minimal AutoISA D0 ELF."""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCAL_PATTERN = "xpack-riscv-none-elf-gcc-*"
PREFIXES = ("riscv-none-elf", "riscv64-unknown-elf")
EXPECTED_D0 = (0x007302DB).to_bytes(4, "little")


def executable(bin_dir: Path, name: str) -> Path | None:
    for suffix in (".exe", ""):
        candidate = bin_dir / f"{name}{suffix}"
        if candidate.is_file():
            return candidate
    return None


def candidate_bins(explicit: Path | None) -> list[Path]:
    candidates: list[Path] = []
    if explicit:
        candidates.append(explicit / "bin" if (explicit / "bin").is_dir() else explicit)
    env_root = os.environ.get("AUTOISA_RISCV_TOOLCHAIN")
    if env_root:
        path = Path(env_root).expanduser()
        candidates.append(path / "bin" if (path / "bin").is_dir() else path)
    local_root = ROOT / "tools"
    if local_root.is_dir():
        candidates.extend(path / "bin" for path in sorted(local_root.glob(LOCAL_PATTERN), reverse=True))
    return candidates


def locate_tools(explicit: Path | None) -> dict[str, Path]:
    for bin_dir in candidate_bins(explicit):
        for prefix in PREFIXES:
            gcc = executable(bin_dir, f"{prefix}-gcc")
            if gcc:
                tools = {name: executable(bin_dir, f"{prefix}-{name}") for name in
                         ("gcc", "objcopy", "objdump", "readelf")}
                if all(tools.values()):
                    return {name: path for name, path in tools.items() if path is not None}

    for prefix in PREFIXES:
        gcc_name = shutil.which(f"{prefix}-gcc")
        if gcc_name:
            bin_dir = Path(gcc_name).parent
            tools = {name: executable(bin_dir, f"{prefix}-{name}") for name in
                     ("gcc", "objcopy", "objdump", "readelf")}
            if all(tools.values()):
                return {name: path for name, path in tools.items() if path is not None}

    raise FileNotFoundError(
        "No complete RISC-V bare-metal toolchain found. Pass --toolchain, set "
        "AUTOISA_RISCV_TOOLCHAIN, or install it under tools/."
    )


def run(command: list[str], *, capture: bool = False) -> str:
    print("$", " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=capture)
    if result.returncode:
        if capture:
            sys.stderr.write(result.stdout)
            sys.stderr.write(result.stderr)
        raise subprocess.CalledProcessError(result.returncode, command)
    return (result.stdout + result.stderr) if capture else ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", type=Path,
                        help="Toolchain root or bin directory; auto-detected by default")
    parser.add_argument("--build-dir", type=Path,
                        default=ROOT / "ci/autoisa/build/software")
    args = parser.parse_args()

    try:
        tools = locate_tools(args.toolchain)
    except FileNotFoundError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    build_dir = args.build_dir.resolve()
    build_dir.mkdir(parents=True, exist_ok=True)
    source = ROOT / "tests/autoisa/software/minimal_d0.S"
    linker = ROOT / "config/gen_from_riscv_config/cv32a65x/linker/link.ld"
    elf = build_dir / "minimal_d0.elf"
    binary = build_dir / "minimal_d0.bin"
    disassembly = build_dir / "minimal_d0.dump"

    version = run([str(tools["gcc"]), "--version"], capture=True).splitlines()[0]
    run([
        str(tools["gcc"]), "-march=rv32imac_zicsr", "-mabi=ilp32",
        "-mcmodel=medany", "-mno-relax", "-nostdlib", "-nostartfiles",
        "-static", "-Wl,--build-id=none", "-T", str(linker), str(source),
        "-o", str(elf),
    ])
    run([str(tools["objcopy"]), "-O", "binary", str(elf), str(binary)])
    header = run([str(tools["readelf"]), "-h", str(elf)], capture=True)
    dump = run([str(tools["objdump"]), "-d", str(elf)], capture=True)
    disassembly.write_text(dump, encoding="utf-8", newline="\n")

    if "Class:                             ELF32" not in header or "Machine:                           RISC-V" not in header:
        print("ERROR: output is not an ELF32 RISC-V image", file=sys.stderr)
        return 1
    if EXPECTED_D0 not in binary.read_bytes():
        print("ERROR: minimal ELF does not contain expected D0 encoding 0x007302db", file=sys.stderr)
        return 1

    print(f"PASS: {version}")
    print("PASS: rv32imac_zicsr/ilp32 compile and link")
    print("PASS: ELF32 RISC-V header")
    print("PASS: D0 encoding 0x007302db present")
    print(f"ELF: {elf}")
    print(f"DISASSEMBLY: {disassembly}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
