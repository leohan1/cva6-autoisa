from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from ci.autoisa.build_g5_workloads import validate_contract

ROOT = Path(__file__).resolve().parents[2]


class G5WorkloadContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads(
            (ROOT / "config/g5_workloads.json").read_text(encoding="utf-8")
        )

    def test_frozen_contract_matches_generated_sources(self) -> None:
        profiles = validate_contract(self.contract)
        self.assertEqual([item["id"] for item in profiles], [f"P{i}" for i in range(9)])

    def test_reference_result_mutation_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.contract)
        mutated["profiles"][2]["expected_results"][0] ^= 1
        with self.assertRaisesRegex(ValueError, "generated reference"):
            validate_contract(mutated)

    def test_profile_mapping_mutation_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.contract)
        mutated["profiles"][3]["semantic_id"] = 3
        with self.assertRaisesRegex(ValueError, "must map"):
            validate_contract(mutated)

    def test_instruction_encoding_mutation_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.contract)
        mutated["profiles"][8]["instruction_encoding"] = "0x0094358b"
        with self.assertRaisesRegex(ValueError, "generated Layout encoder"):
            validate_contract(mutated)

    def test_throughput_destination_alias_mutation_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.contract)
        mutated["profiles"][1]["throughput_instruction_encodings"][1] = (
            mutated["profiles"][1]["throughput_instruction_encodings"][0]
        )
        with self.assertRaisesRegex(ValueError, "destinations must be independent"):
            validate_contract(mutated)


if __name__ == "__main__":
    unittest.main(verbosity=2)
