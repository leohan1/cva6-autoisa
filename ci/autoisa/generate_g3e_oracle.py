#!/usr/bin/env python3
"""Generate the reference-backed P3-P7 vectors for the G3E pre-closure."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

try:
    from .build_g5_workloads import ROOT, load_module, validate_contract
except ImportError:
    from build_g5_workloads import ROOT, load_module, validate_contract

DEFAULT_OUTPUT = ROOT / "generated/g3e"
WORDS_PER_VECTOR = 15


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(output: Path) -> dict[str, object]:
    contract_path = ROOT / "config/g5_workloads.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    profiles = validate_contract(contract)
    encoder = load_module(
        ROOT / "generated/layout/autoisa_ci_encode.py", "g3e_layout_encoder"
    )
    reference = load_module(
        ROOT / "generated/semantics/autoisa_ci_semantic_ref.py", "g3e_semantic_ref"
    )

    output.mkdir(parents=True, exist_ok=True)
    vector_path = output / "g3e_preclosure_vectors.hex"
    records: list[dict[str, object]] = []
    lines: list[str] = []
    for profile_number in range(3, 8):
        profile = profiles[profile_number]
        if profile["backend"] != "AUTOISA_DIRECT_CI_EXTENDED":
            raise ValueError(f"{profile['id']} is not an Extended profile")
        decoded = encoder.decode_instruction(int(profile["instruction_encoding"], 0))
        if decoded is None:
            raise ValueError(f"{profile['id']} encoding cannot be decoded")
        actual = reference.evaluate(
            profile["semantic_id"], profile["inputs"], profile["immediate"]
        )
        if actual["results"] != profile["expected_results"]:
            raise ValueError(f"{profile['id']} reference result is stale")

        source_pack = sum(reg << (index * 5)
                          for index, reg in enumerate(decoded["sources"]))
        destination_pack = sum(reg << (index * 5)
                               for index, reg in enumerate(decoded["destinations"]))
        inputs = [*profile["inputs"], *([0] * (6 - len(profile["inputs"])))][:6]
        words = [
            int(profile["instruction_encoding"], 0), profile_number,
            profile["semantic_id"], len(decoded["sources"]),
            len(decoded["destinations"]), source_pack, destination_pack,
            *inputs, *actual["results"],
        ]
        if len(words) != WORDS_PER_VECTOR:
            raise AssertionError("G3E vector width mismatch")
        lines.append("".join(f"{word & 0xFFFFFFFF:08x}" for word in words))
        records.append({
            "profile": profile["id"],
            "semantic_id": profile["semantic_id"],
            "layout_id": profile["layout_id"],
            "encoding": profile["instruction_encoding"],
            "sources": decoded["sources"],
            "destinations": decoded["destinations"],
            "inputs": profile["inputs"],
            "expected_results": actual["results"],
        })

    vector_path.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    manifest = {
        "schema_version": "1.0",
        "status": "PASS",
        "scope": "G3E pre-closure; not CVA6 whole-core integration",
        "profile_count": len(records),
        "words_per_vector": WORDS_PER_VECTOR,
        "layout_catalog_sha256": contract["layout_catalog_sha256"],
        "semantic_catalog_sha256": contract["semantic_catalog_sha256"],
        "workload_contract_sha256": sha256(contract_path),
        "vector_sha256": sha256(vector_path),
        "records": records,
    }
    (output / "generation_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8", newline="\n"
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        manifest = generate(args.output.resolve())
    except (FileNotFoundError, ValueError) as error:
        print(f"ERROR: {error}")
        return 1
    print(
        "PASS: generated reference-backed G3E vectors for "
        f"{manifest['profile_count']} Extended profiles"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
