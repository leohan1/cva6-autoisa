#!/usr/bin/env python3
"""Validate the frozen G5 contract and build P0-P8 scalar/AutoISA ELF pairs."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

try:
    from .check_riscv_toolchain import locate_tools
    from .g4_contract import validate_bidirectional
except ImportError:
    from check_riscv_toolchain import locate_tools
    from g4_contract import validate_bidirectional

ROOT = Path(__file__).resolve().parents[2]


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


def run(command: list[str]) -> str:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        sys.stderr.write(result.stdout + result.stderr)
        raise subprocess.CalledProcessError(result.returncode, command)
    return result.stdout + result.stderr


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_contract(contract: dict[str, object]) -> list[dict[str, object]]:
    layout_manifest = json.loads(
        (ROOT / "generated/layout/generation_manifest.json").read_text(encoding="utf-8")
    )
    semantic_manifest = json.loads(
        (ROOT / "generated/semantics/generation_manifest.json").read_text(encoding="utf-8")
    )
    if contract["layout_catalog_sha256"] != layout_manifest["catalog_sha256"]:
        raise ValueError("G5 contract layout hash is stale")
    if contract["semantic_catalog_sha256"] != semantic_manifest["catalog_sha256"]:
        raise ValueError("G5 contract semantic hash is stale")
    layouts = json.loads((ROOT / "config/layout_profiles_v2.json").read_text(encoding="utf-8"))
    semantics = json.loads((ROOT / "config/semantics_v2.json").read_text(encoding="utf-8"))
    validate_bidirectional(layouts, semantics)
    profiles = contract["profiles"]
    if [item["id"] for item in profiles] != [f"P{i}" for i in range(9)]:
        raise ValueError("G5 contract must contain ordered P0-P8 exactly once")
    reference = load_module(
        ROOT / "generated/semantics/autoisa_ci_semantic_ref.py", "g5_semantic_ref"
    )
    encoder = load_module(
        ROOT / "generated/layout/autoisa_ci_encode.py", "g5_layout_encoder"
    )
    layouts_by_id = {item["id"]: item for item in layouts["layouts"]}
    iterations = int(contract["iterations"])
    for index, item in enumerate(profiles):
        if index == 0:
            if item["kind"] != "control" or item["expected_ci_retired"] != 0:
                raise ValueError("P0 must be the zero-CI control profile")
            continue
        if item["semantic_id"] != index - 1 or item["layout_id"] != index - 1:
            raise ValueError(f"{item['id']} must map to D{index - 1}/L{index - 1}")
        layout = layouts_by_id[item["layout_id"]]
        if item["backend"] != layout["backend"]:
            raise ValueError(f"{item['id']} backend disagrees with Layout catalog")
        encoded = encoder.encode_layout(
            layout["name"], item["source_registers"], item["destination_registers"],
            item["semantic_id"], item["immediate"]
        )
        if encoded != int(item["instruction_encoding"], 0):
            raise ValueError(f"{item['id']} encoding disagrees with generated Layout encoder")
        throughput_encodings = item["throughput_instruction_encodings"]
        if "throughput" in item["measurement_modes"]:
            if item["backend"] != "AUTOISA_CVXIF_NATIVE" or len(throughput_encodings) != 4:
                raise ValueError(f"{item['id']} throughput mode requires four Native encodings")
            destinations: set[tuple[int, ...]] = set()
            for text in throughput_encodings:
                raw = int(text, 0)
                decoded = encoder.decode_instruction(raw)
                if decoded is None or decoded["layout_id"] != item["layout_id"] or \
                        decoded["semantic_id"] != item["semantic_id"] or \
                        decoded["sources"] != item["source_registers"] or \
                        decoded["immediate"] != item["immediate"]:
                    raise ValueError(f"{item['id']} throughput encoding is inconsistent")
                regenerated = encoder.encode_layout(
                    layout["name"], item["source_registers"], decoded["destinations"],
                    item["semantic_id"], item["immediate"]
                )
                if regenerated != raw:
                    raise ValueError(f"{item['id']} throughput encoding is not reproducible")
                destinations.add(tuple(decoded["destinations"]))
            if len(destinations) != 4:
                raise ValueError(f"{item['id']} throughput destinations must be independent")
        elif throughput_encodings:
            raise ValueError(f"{item['id']} has unused throughput encodings")
        actual = reference.evaluate(
            item["semantic_id"], item["inputs"], item["immediate"]
        )["results"]
        if actual != item["expected_results"]:
            raise ValueError(f"{item['id']} expected results disagree with generated reference")
        if item["expected_ci_retired"] != iterations:
            raise ValueError(f"{item['id']} CI retire count must equal iterations")
    return profiles


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", type=Path)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "ci/autoisa/build/g5")
    args = parser.parse_args()
    contract_path = ROOT / "config/g5_workloads.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    try:
        profiles = validate_contract(contract)
        tools = locate_tools(args.toolchain)
    except (FileNotFoundError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    source = ROOT / "tests/autoisa/software/g5_workload.S"
    linker = ROOT / "tests/autoisa/software/g5_workload.ld"
    artifacts: list[dict[str, object]] = []
    try:
        for profile_index, profile in enumerate(profiles):
            for measurement in profile["measurement_modes"]:
                for variant, autoisa in (("scalar", 0), ("autoisa", 1)):
                    stem = f"{profile['id'].lower()}_{measurement}_{variant}"
                    elf = build / f"{stem}.elf"
                    binary = build / f"{stem}.bin"
                    hex_image = build / f"{stem}.hex"
                    dump = build / f"{stem}.dump"
                    run([
                        str(tools["gcc"]), "-march=rv32imac_zicsr", "-mabi=ilp32",
                        "-mcmodel=medany", "-mno-relax", "-nostdlib", "-nostartfiles",
                        "-static", "-Wl,--build-id=none", f"-DG5_PROFILE={profile_index}",
                        f"-DG5_AUTOISA={autoisa}",
                        f"-DG5_ITERATIONS={contract['iterations']}",
                        f"-DG5_THROUGHPUT={1 if measurement == 'throughput' else 0}",
                        "-T", str(linker), str(source), "-o", str(elf),
                    ])
                    run([
                        str(tools["objcopy"]), "-O", "binary",
                        "--only-section=.text.init", str(elf), str(binary),
                    ])
                    image = binary.read_bytes()
                    frozen_encodings = (
                        profile["throughput_instruction_encodings"]
                        if measurement == "throughput" else
                        [profile["instruction_encoding"]]
                        if profile["instruction_encoding"] else []
                    )
                    for text in frozen_encodings:
                        encoded_bytes = int(text, 0).to_bytes(4, "little")
                        if variant == "autoisa" and encoded_bytes not in image:
                            raise ValueError(
                                f"{profile['id']} AutoISA ELF lacks frozen encoding"
                            )
                        if variant == "scalar" and encoded_bytes in image:
                            raise ValueError(
                                f"{profile['id']} scalar ELF contains AutoISA encoding"
                            )
                    words = []
                    for offset in range(0, len(image), 8):
                        chunk = image[offset:offset + 8].ljust(8, b"\0")
                        words.append(f"{int.from_bytes(chunk, 'little'):016x}")
                    hex_image.write_text("\n".join(words) + "\n", encoding="ascii")
                    dump.write_text(
                        run([str(tools["objdump"]), "-d", str(elf)]), encoding="utf-8"
                    )
                    artifacts.append({
                        "profile": profile["id"], "measurement": measurement,
                        "variant": variant,
                        "execution_status": profile["execution_status"],
                        "elf": str(elf.relative_to(ROOT)).replace("\\", "/"),
                        "hex": str(hex_image.relative_to(ROOT)).replace("\\", "/"),
                        "elf_sha256": sha256(elf), "binary_sha256": sha256(binary),
                        "size_bytes": elf.stat().st_size,
                    })
    except (subprocess.CalledProcessError, ValueError) as error:
        if isinstance(error, ValueError):
            print(f"ERROR: {error}", file=sys.stderr)
            return 1
        print(f"ERROR: build command failed: {' '.join(error.cmd)}", file=sys.stderr)
        return 1

    evidence = {
        "schema_version": "1.0", "status": "PASS",
        "contract": str(contract_path.relative_to(ROOT)).replace("\\", "/"),
        "contract_sha256": sha256(contract_path), "source_sha256": sha256(source),
        "toolchain": run([str(tools["gcc"]), "--version"]).splitlines()[0],
        "pair_count": sum(len(profile["measurement_modes"]) for profile in profiles),
        "artifact_count": len(artifacts),
        "artifacts": artifacts,
    }
    (build / "g5_elf_manifest.json").write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"PASS: frozen G5 contract validated ({len(profiles)} profiles)")
    print(f"PASS: built {evidence['pair_count']} scalar/AutoISA ELF pairs")
    print(f"MANIFEST: {build / 'g5_elf_manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
