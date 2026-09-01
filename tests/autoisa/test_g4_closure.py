from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from ci.autoisa.g4_contract import ContractError, validate_bidirectional, verify_reference_triplet
from ci.autoisa.generate_signature_oracle import build_oracle, load_reference

ROOT = Path(__file__).resolve().parents[2]

generator_spec = importlib.util.spec_from_file_location(
    "g4_semantic_generator", ROOT / "scripts/generate_semantics.py"
)
generator = importlib.util.module_from_spec(generator_spec)
assert generator_spec.loader
generator_spec.loader.exec_module(generator)


class G4ClosureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.layouts = json.loads(
            (ROOT / "config/layout_profiles_v2.json").read_text(encoding="utf-8")
        )
        self.semantics = json.loads(
            (ROOT / "config/semantics_v2.json").read_text(encoding="utf-8")
        )

    def test_layout_semantic_bidirectional_consistency(self) -> None:
        self.assertEqual(
            validate_bidirectional(self.layouts, self.semantics), list(range(8))
        )

    def test_g3_oracle_is_reference_backed_for_d0_d1_d7(self) -> None:
        reference = load_reference(
            ROOT / "generated/semantics/autoisa_ci_semantic_ref.py"
        )
        words, masks, evidence = build_oracle(reference)
        self.assertEqual(words[21], 50)
        self.assertEqual(masks[6], 0)
        self.assertEqual(set(evidence["reference_backed_words"]), {"D0", "D1", "D7"})

    def test_mutation_layout_routing_is_killed(self) -> None:
        mutated = copy.deepcopy(self.layouts)
        mutated["layouts"][7]["semantic"]["value"] = 6
        with self.assertRaisesRegex(ContractError, "cannot select"):
            validate_bidirectional(mutated, self.semantics)

    def test_mutation_semantic_arity_is_killed(self) -> None:
        mutated = copy.deepcopy(self.semantics)
        mutated["semantics"][1]["operands"] = 2
        with self.assertRaisesRegex(ContractError, "operands mismatch"):
            validate_bidirectional(self.layouts, mutated)

    def test_mutation_immediate_capability_is_killed(self) -> None:
        mutated = copy.deepcopy(self.semantics)
        mutated["semantics"][7]["immediate"] = False
        with self.assertRaisesRegex(ContractError, "immediate mismatch"):
            validate_bidirectional(self.layouts, mutated)

    def test_mutation_semantic_operator_is_killed(self) -> None:
        mutated = copy.deepcopy(self.semantics)
        mutated["semantics"][1]["nodes"][1]["op"] = "xor"
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = base / "semantics.json"
            config.write_text(json.dumps(mutated), encoding="utf-8")
            generator.build(config, base / "generated", base / "engine.sv")
            reference = load_reference(base / "generated/autoisa_ci_semantic_ref.py")
            with self.assertRaisesRegex(ContractError, "D1 reference behavior mismatch"):
                verify_reference_triplet(reference)


if __name__ == "__main__":
    unittest.main(verbosity=2)
