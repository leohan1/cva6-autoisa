#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import random
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "config/semantics_v2.json"

spec = importlib.util.spec_from_file_location("semantic_generator", ROOT / "scripts/generate_semantics.py")
generator = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(generator)


def load_reference(path: Path):
    reference_spec = importlib.util.spec_from_file_location("semantic_reference", path)
    reference = importlib.util.module_from_spec(reference_spec)
    assert reference_spec.loader
    reference_spec.loader.exec_module(reference)
    return reference


class SemanticGeneratorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = json.loads(CONFIG.read_text(encoding="utf-8"))

    def assert_catalog_error(self, catalog: dict) -> None:
        with self.assertRaises(generator.CatalogError):
            generator.validate_catalog(catalog)

    def test_schema_and_catalog_cover_d0_through_d7(self) -> None:
        schema = json.loads((ROOT / "schemas/ci_semantic_v2.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(schema["properties"]["schema_version"]["const"], "2.0")
        semantics = generator.validate_catalog(self.catalog)
        self.assertEqual([item["ci_id"] for item in semantics], list(range(8)))

    def test_generation_is_deterministic_and_checked_in_rtl_is_current(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            first = generator.build(CONFIG, base / "a", base / "a.sv")
            second = generator.build(CONFIG, base / "b", base / "b.sv")
            self.assertEqual(first, second)
            self.assertEqual((base / "a.sv").read_bytes(), (base / "b.sv").read_bytes())
            self.assertEqual((base / "a.sv").read_text(encoding="utf-8"),
                             (ROOT / "core/autoisa/autoisa_ci_semantic_engine.sv").read_text(encoding="utf-8"))
            self.assertEqual((base / "a/autoisa_ci_semantic_ref.py").read_text(encoding="utf-8"),
                             (ROOT / "generated/semantics/autoisa_ci_semantic_ref.py").read_text(encoding="utf-8"))
        self.assertEqual(
            (ROOT / "core/autoisa/autoisa_ci_semantic_engine.sv").read_bytes(),
            (ROOT / "generated/semantics/autoisa_ci_semantic_engine.sv").read_bytes(),
        )

    def test_whole_core_filelist_orders_semantic_engine_before_wrapper(self) -> None:
        lines = (ROOT / "core/Flist.cva6").read_text(encoding="utf-8").splitlines()
        semantic = next(index for index, line in enumerate(lines)
                        if line.endswith("/autoisa_ci_semantic_engine.sv"))
        wrapper = next(index for index, line in enumerate(lines)
                       if line.endswith("/autoisa_ci_dummy_engine.sv"))
        self.assertLess(semantic, wrapper)

    def test_reference_matches_independent_d0_d7_formulas(self) -> None:
        reference = load_reference(ROOT / "generated/semantics/autoisa_ci_semantic_ref.py")
        mask = 0xFFFFFFFF
        rng = random.Random(0x5E6A17C)
        for _ in range(1000):
            op = [rng.getrandbits(32) for _ in range(6)]
            imm = rng.getrandbits(32)
            ab, cd, ef = op[0] * op[1], op[2] * op[3], op[4] * op[5]
            expected = {
                0: [(op[0] + op[1]) & mask],
                1: [(op[0] * op[1] + op[2]) & mask],
                2: [((op[0] * op[1] + op[2]) ^ op[3]) & mask],
                3: [(op[0] + op[1]) & mask, (op[0] - op[1]) & mask],
                4: [(op[0] * op[2] - op[1] * op[3]) & mask,
                    (op[0] * op[3] + op[1] * op[2]) & mask],
                5: [sum(op) & mask],
                6: [(ab + cd + ef) & mask, (ab - cd + ef) & mask],
                7: [((op[0] << (imm & 31)) ^ (op[1] + imm)) & mask],
            }
            for ci_id, values in expected.items():
                actual = reference.evaluate(ci_id, op, imm)
                self.assertTrue(actual["supported"])
                self.assertEqual(actual["results"][:len(values)], values)
        self.assertFalse(reference.evaluate(255, [0] * 6)["supported"])

    def test_duplicate_unknown_forward_and_hidden_work_are_rejected(self) -> None:
        duplicate = copy.deepcopy(self.catalog)
        duplicate["semantics"][1]["ci_id"] = 0
        self.assert_catalog_error(duplicate)
        unknown = copy.deepcopy(self.catalog)
        unknown["semantics"][0]["nodes"][0]["op"] = "load"
        self.assert_catalog_error(unknown)
        forward = copy.deepcopy(self.catalog)
        forward["semantics"][1]["nodes"][0]["args"][0] = "result"
        self.assert_catalog_error(forward)
        unused = copy.deepcopy(self.catalog)
        unused["semantics"][0]["nodes"].append({"id": "dead", "op": "xor", "args": ["operand0", "operand1"]})
        self.assert_catalog_error(unused)

    def test_immediate_and_operand_bounds_are_enforced(self) -> None:
        immediate = copy.deepcopy(self.catalog)
        immediate["semantics"][0]["nodes"][0]["args"][0] = "immediate"
        self.assert_catalog_error(immediate)
        operand = copy.deepcopy(self.catalog)
        operand["semantics"][0]["nodes"][0]["args"][0] = "operand2"
        self.assert_catalog_error(operand)


if __name__ == "__main__":
    unittest.main(verbosity=2)
