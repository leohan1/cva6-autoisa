#!/usr/bin/env python3
"""Expand CVA6 nested file lists into a Vivado/XSim-compatible flat list."""
from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


def expand_vars(text: str, env: dict[str, str]) -> str:
    return re.sub(r"\$\{([^}]+)\}", lambda m: env.get(m.group(1), m.group(0)), text)


def normalize(path_text: str, base: Path) -> Path:
    path = Path(path_text.strip().strip('"'))
    return (path if path.is_absolute() else base / path).resolve()


def quote(path: Path) -> str:
    value = path.as_posix()
    return f'"{value}"' if " " in value else value


def expand_filelist(path: Path, env: dict[str, str], output: list[str], seen_lists: set[Path]) -> None:
    path = path.resolve()
    if path in seen_lists:
        return
    if not path.is_file():
        raise FileNotFoundError(f"missing file list: {path}")
    seen_lists.add(path)
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = expand_vars(raw.split("//", 1)[0].strip(), env)
        if not line or line.startswith("#"):
            continue
        fields = line.split(maxsplit=1)
        if fields[0].lower() == "-f":
            if len(fields) != 2:
                raise ValueError(f"bad nested file list in {path}: {raw}")
            expand_filelist(normalize(fields[1], path.parent), env, output, seen_lists)
        elif line.startswith("+incdir+"):
            inc = normalize(line[len("+incdir+"):], path.parent)
            output.append(f"-i {quote(inc)}")
        elif line.startswith("+") or line.startswith("-"):
            output.append(line)
        else:
            source = normalize(line, path.parent)
            if not source.is_file():
                raise FileNotFoundError(f"missing source referenced by {path}: {source}")
            output.append(quote(source))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--target", default="cv32a65x")
    parser.add_argument("--input", default="core/Flist.cva6")
    parser.add_argument("--output", default="ci/autoisa/build/cv32a65x_xsim.f")
    parser.add_argument("--ariane", action="store_true", help="append ariane AXI package and wrapper")
    parser.add_argument("--ariane-elf", action="store_true",
                        help="append ariane AXI package and program-level AutoISA ELF top")
    args = parser.parse_args()

    root = args.root.resolve()
    hpdcache = root / "core/cache_subsystem/hpdcache"
    env = dict(os.environ)
    env.update(CVA6_REPO_DIR=str(root), TARGET_CFG=args.target, HPDCACHE_DIR=str(hpdcache))
    lines: list[str] = []
    expand_filelist(normalize(args.input, root), env, lines, set())
    if args.ariane or args.ariane_elf:
        lines.extend([
            quote(root / "corev_apu/tb/ariane_axi_pkg.sv"),
            quote(root / "corev_apu/src/ariane.sv"),
            quote(root / ("core/autoisa/tb/tb_autoisa_ci_ariane_elf.sv"
                          if args.ariane_elf else
                          "core/autoisa/tb/tb_autoisa_ci_ariane_smoke.sv")),
        ])

    # Preserve first occurrence; duplicated modules otherwise upset Vivado.
    unique = list(dict.fromkeys(lines))
    output = normalize(args.output, root)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(unique) + "\n", encoding="utf-8")
    print(f"generated {output} ({len(unique)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
