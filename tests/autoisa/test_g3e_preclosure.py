from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from ci.autoisa.generate_g3e_oracle import ROOT, generate


class G3EPreclosureTest(unittest.TestCase):
    def test_generated_artifacts_are_current_and_deterministic(self) -> None:
        checked_in = ROOT / "generated/g3e"
        with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
            first = Path(first_dir)
            second = Path(second_dir)
            generate(first)
            generate(second)
            for name in ("g3e_preclosure_vectors.hex", "generation_manifest.json"):
                self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
                self.assertEqual((first / name).read_bytes(), (checked_in / name).read_bytes())

    def test_manifest_covers_only_extended_p3_through_p7(self) -> None:
        manifest = json.loads(
            (ROOT / "generated/g3e/generation_manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(manifest["profile_count"], 5)
        self.assertEqual(
            [record["profile"] for record in manifest["records"]],
            ["P3", "P4", "P5", "P6", "P7"],
        )
        self.assertEqual(
            [record["expected_results"] for record in manifest["records"]],
            [[29, 0], [29, 13], [0xFFFFFFF5, 29], [21, 0], [68, 28]],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
