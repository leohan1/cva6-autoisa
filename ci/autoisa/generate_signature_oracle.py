#!/usr/bin/env python3
"""Generate the G3 program signature oracle from generated semantics."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path

try:
    from .g4_contract import verify_reference_triplet
except ImportError:  # Direct script execution.
    from g4_contract import verify_reference_triplet

ROOT = Path(__file__).resolve().parents[2]


def load_reference(path: Path):
    spec = importlib.util.spec_from_file_location("autoisa_g3_semantic_ref", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


def build_oracle(reference) -> tuple[list[int], list[int], dict[str, object]]:
    verify_reference_triplet(reference)

    def result(ci_id: int, operands: list[int], immediate: int = 0) -> int:
        return int(reference.evaluate(ci_id, operands, immediate)["results"][0])

    words = [
        0x4155544F, 1, 1, 0x00003FFF, 2, 2, 0,
        12,
        result(0, [0, 0]),
        result(0, [0xFFFFFFFF, 1]),
        result(0, [0xFFFFFFFF, 0xFFFFFFFF]),
        result(0, [1, 2]),
        result(0, [3, 2]),
        result(0, [5, 3]),
        30, 0xAAAAAAAA, 1,
        result(7, [5, 9], 3),
        0x13579BDF, 0x2468ACE0, 0x5349474E,
        result(1, [6, 7, 8]),
    ]
    masks = [0xFFFFFFFF] * len(words)
    masks[6] = 0  # mtval is implementation-defined for the rejected instruction.
    evidence = {
        "schema_version": 1,
        "reference_catalog_sha256": reference.CATALOG_SHA256,
        "word_count": len(words),
        "masked_word_indices": [6],
        "reference_backed_words": {
            "D0": [8, 9, 10, 11, 12, 13],
            "D1": [21],
            "D7": [17],
        },
    }
    return words, masks, evidence


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reference",
        type=Path,
        default=ROOT / "generated/semantics/autoisa_ci_semantic_ref.py",
    )
    parser.add_argument(
        "--output-dir", type=Path, default=ROOT / "ci/autoisa/build/software"
    )
    args = parser.parse_args()
    reference = load_reference(args.reference.resolve())
    words, masks, evidence = build_oracle(reference)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "program_signature_oracle.hex").write_text(
        "".join(f"{word & 0xFFFFFFFF:08x}\n" for word in words), encoding="ascii"
    )
    (output / "program_signature_mask.hex").write_text(
        "".join(f"{word & 0xFFFFFFFF:08x}\n" for word in masks), encoding="ascii"
    )
    (output / "program_signature_oracle.json").write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        f"PASS: generated {len(words)}-word G3 signature oracle from "
        f"{reference.CATALOG_SHA256}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
