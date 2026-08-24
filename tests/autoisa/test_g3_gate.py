from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from ci.autoisa.run_g3_gate import GateStep, execute_gate, gate_steps


class G3GateTest(unittest.TestCase):
    def test_gate_steps_end_with_elf_execution(self) -> None:
        steps = gate_steps("python", Path("vivado"), Path("toolchain"))
        self.assertEqual([step.name for step in steps],
                         ["layout-g0", "source-manifest", "program-coverage-elf"])
        self.assertIn("run_autoisa_elf_smoke.py", steps[-1].command[1])
        self.assertEqual(steps[-1].command[-2:], ["--toolchain", "toolchain"])

    @patch("ci.autoisa.run_g3_gate.subprocess.run")
    def test_failure_blocks_following_steps_and_records_summary(self, run) -> None:
        run.return_value.returncode = 2
        with tempfile.TemporaryDirectory() as directory:
            summary = Path(directory) / "summary.json"
            result = execute_gate(
                [GateStep("first", ["false"]), GateStep("second", ["never"])],
                summary,
            )
            report = json.loads(summary.read_text(encoding="utf-8"))
        self.assertEqual(result, 1)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(report["status"], "FAIL")
        self.assertEqual(report["steps"][0]["returncode"], 2)

    @patch("ci.autoisa.run_g3_gate.subprocess.run")
    def test_success_requires_every_step(self, run) -> None:
        run.return_value.returncode = 0
        with tempfile.TemporaryDirectory() as directory:
            summary = Path(directory) / "summary.json"
            result = execute_gate(
                [GateStep("first", ["true"]), GateStep("second", ["true"])],
                summary,
            )
            report = json.loads(summary.read_text(encoding="utf-8"))
        self.assertEqual(result, 0)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(report["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
