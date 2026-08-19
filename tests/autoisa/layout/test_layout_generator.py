#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import random
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "config/layout_profiles_v2.json"

spec = importlib.util.spec_from_file_location("layout_generator", ROOT / "scripts/generate_layout_decoder.py")
generator = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(generator)


class LayoutGeneratorG0Test(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = json.loads(CONFIG.read_text(encoding="utf-8"))

    def assertCatalogError(self, catalog: dict) -> None:
        with self.assertRaises(generator.CatalogError):
            generator.validate_catalog(catalog)

    def test_schema_and_valid_catalog(self) -> None:
        schema = json.loads((ROOT / "schemas/layout_profile_v2.schema.json").read_text(encoding="utf-8"))
        semantic_schema = json.loads((ROOT / "schemas/ci_semantic_v1.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(schema["properties"]["schema_version"]["const"], "2.0")
        self.assertEqual(semantic_schema["properties"]["schema_version"]["const"], "1.0")
        layouts = generator.validate_catalog(self.catalog)
        self.assertEqual([layout["id"] for layout in layouts], list(range(8)))

    def test_overlap_is_rejected(self) -> None:
        broken = copy.deepcopy(self.catalog)
        broken["layouts"][1]["match"] = broken["layouts"][0]["match"]
        broken["layouts"][1]["mask"] = broken["layouts"][0]["mask"]
        self.assertCatalogError(broken)

    def test_out_of_range_is_rejected(self) -> None:
        broken = copy.deepcopy(self.catalog)
        broken["layouts"][0]["sources"][0]["slices"][0]["instr_msb"] = 32
        self.assertCatalogError(broken)

    def test_namespace_width_mismatch_is_rejected(self) -> None:
        broken = copy.deepcopy(self.catalog)
        broken["layouts"][2]["sources"][0]["slices"][0]["instr_msb"] = 19
        self.assertCatalogError(broken)

    def test_payload_recognition_overlap_is_rejected(self) -> None:
        broken = copy.deepcopy(self.catalog)
        broken["layouts"][0]["sources"][0]["slices"][0] = {"instr_msb": 6, "instr_lsb": 2, "value_lsb": 0}
        self.assertCatalogError(broken)

    def test_memory_profile_is_rejected(self) -> None:
        broken = copy.deepcopy(self.catalog)
        broken["layouts"][0]["backend"] = "AUTOISA_HOST_MEMORY_EXPERIMENTAL"
        self.assertCatalogError(broken)

    def test_six_read_two_write_and_scattered_immediate_exist(self) -> None:
        by_name = {layout["name"]: layout for layout in generator.validate_catalog(self.catalog)}
        six = by_name["L_6R2W_GPR8"]
        self.assertEqual((six["logical_sources"], six["logical_destinations"]), (6, 2))
        immediate = by_name["L_2R1W_IMM"]["immediate"]
        self.assertGreaterEqual(len(immediate["slices"]), 2)
        self.assertGreater(immediate["slices"][0]["instr_lsb"] - immediate["slices"][1]["instr_msb"], 1)

    def test_generation_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            first = generator.build(CONFIG, base / "a", base / "a.sv")
            second = generator.build(CONFIG, base / "b", base / "b.sv")
            self.assertEqual(first, second)
            self.assertEqual((base / "a.sv").read_bytes(), (base / "b.sv").read_bytes())
            for name in first:
                self.assertEqual((base / "a" / name).read_bytes(), (base / "b" / name).read_bytes())

    def test_generated_rtl_is_current(self) -> None:
        self.assertEqual(
            (ROOT / "core/autoisa/autoisa_ci_layout_decoder_v2.sv").read_bytes(),
            (ROOT / "generated/layout/autoisa_ci_layout_decoder.sv").read_bytes(),
        )

    def test_encoder_decoder_roundtrip_10000(self) -> None:
        encoder_path = ROOT / "generated/layout/autoisa_ci_encode.py"
        encoder_spec = importlib.util.spec_from_file_location("generated_encoder", encoder_path)
        encoder = importlib.util.module_from_spec(encoder_spec)
        assert encoder_spec.loader
        encoder_spec.loader.exec_module(encoder)
        rng = random.Random(0xA17015A)
        names = sorted(encoder.BY_NAME)
        for iteration in range(10_000):
            name = names[iteration % len(names)]
            layout = encoder.BY_NAME[name]
            sources = []
            for field in layout["sources"]:
                low, high = {"GPR32": (0, 31), "GPR16": (0, 15), "RVC8": (8, 15)}[field["namespace"]]
                sources.append(rng.randint(low, high))
            destinations, named = [], {}
            for field in layout["destinations"]:
                if field["namespace"] == "DERIVED_PAIR":
                    value = named[field["derived_from"]] + field["offset"]
                elif "pair_constraint" in layout and field["name"] == layout["pair_constraint"]["base"]:
                    value = rng.randrange(2, 31, 2)
                else:
                    low, high = {"GPR32": (1, 31), "GPR16": (1, 15), "RVC8": (8, 15)}[field["namespace"]]
                    value = rng.randint(low, high)
                destinations.append(value); named[field["name"]] = value
            semantic = layout["semantic"]
            semantic_id = rng.randrange(1 << semantic["width"]) if semantic["kind"] == "encoded" else semantic["value"]
            immediate = None
            if "immediate" in layout:
                imm = layout["immediate"]
                low = -(1 << (imm["width"] - 1)) if imm["signed"] else 0
                high = (1 << (imm["width"] - (1 if imm["signed"] else 0))) - 1
                immediate = rng.randint(low, high) << imm["scale"]
            instruction = encoder.encode_layout(name, sources, destinations, semantic_id, immediate)
            decoded = encoder.decode_instruction(instruction)
            self.assertIsNotNone(decoded)
            self.assertEqual(decoded["name"], name)
            self.assertEqual(decoded["sources"], sources)
            self.assertEqual(decoded["destinations"], destinations)
            self.assertEqual(decoded["semantic_id"], semantic_id)
            self.assertEqual(decoded["immediate"], immediate)


if __name__ == "__main__":
    unittest.main(verbosity=2)
