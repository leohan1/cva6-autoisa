#!/usr/bin/env python3
"""Run generated RTL against the generated software semantic reference model."""
from __future__ import annotations

import argparse
import importlib.util
import json
import random
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")
BUILD = ROOT / "ci/autoisa/build/semantic_diff"
SEED = 0x5E6A17C
EDGE_VALUES = (0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFE, 0xFFFFFFFF)


def find_tool(vivado_bin: Path, name: str) -> Path:
    for candidate in (vivado_bin / f"{name}.bat", vivado_bin / f"{name}.exe",
                      vivado_bin / "unwrapped/win64.o" / f"{name}.exe"):
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"Cannot find {name} under {vivado_bin}")


def load_reference(path: Path):
    spec = importlib.util.spec_from_file_location("autoisa_generated_semantic_ref", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


def vector_operands(rng: random.Random, index: int) -> tuple[list[int], int]:
    if index < len(EDGE_VALUES):
        value = EDGE_VALUES[index]
        return [value] * 6, value
    if index < 2 * len(EDGE_VALUES):
        value = EDGE_VALUES[index - len(EDGE_VALUES)]
        return [value, value ^ 0xFFFFFFFF, 1, 0xFFFFFFFF, 0x7FFFFFFF, 0x80000000], value
    return [rng.getrandbits(32) for _ in range(6)], rng.getrandbits(32)


def create_vectors(reference, per_semantic: int) -> tuple[Path, int, dict[int, int]]:
    if per_semantic < 2 * len(EDGE_VALUES):
        raise ValueError(f"vectors-per-semantic must be at least {2 * len(EDGE_VALUES)}")
    BUILD.mkdir(parents=True, exist_ok=True)
    path = BUILD / "semantic_diff_vectors.hex"
    rng = random.Random(SEED)
    lines: list[str] = []
    counts: dict[int, int] = {}
    for semantic in reference.CATALOG["semantics"]:
        ci_id = semantic["ci_id"]
        counts[ci_id] = per_semantic
        for index in range(per_semantic):
            operands, immediate = vector_operands(rng, index)
            expected = reference.evaluate(ci_id, operands, immediate)
            words = [ci_id, immediate, *operands, int(expected["supported"]),
                     expected["latency"], expected["result_valid"], *expected["results"]]
            lines.append("".join(f"{word & 0xFFFFFFFF:08x}" for word in words))
    path.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    return path, len(lines), counts


def create_testbench(vector_path: Path, count: int) -> Path:
    path = BUILD / "tb_autoisa_ci_semantic_diff.sv"
    relative_vectors = vector_path.relative_to(ROOT).as_posix()
    source = f'''// Generated differential testbench; not a checked-in source artifact.
`timescale 1ns / 1ps
`default_nettype none
module tb_autoisa_ci_semantic_diff;
  localparam integer VECTOR_COUNT = {count};
  logic [415:0] vectors [0:VECTOR_COUNT-1];
  logic [7:0] ci_id;
  logic [31:0] ci_word;
  logic [5:0][31:0] operands;
  logic [31:0] immediate;
  logic supported;
  logic [4:0] latency;
  logic [1:0] result_valid;
  logic [1:0][31:0] results;
  logic [31:0] expected_supported;
  logic [31:0] expected_latency;
  logic [31:0] expected_valid;
  logic [1:0][31:0] expected_results;
  integer index;

  autoisa_ci_semantic_engine dut (
      .ci_id_i(ci_id), .operands_i(operands), .immediate_i(immediate),
      .supported_o(supported), .latency_o(latency),
      .result_valid_o(result_valid), .results_o(results)
  );

  initial begin
    $readmemh("{relative_vectors}", vectors);
    ci_id = '0;
    operands = '0;
    immediate = '0;
    for (index = 0; index < VECTOR_COUNT; index = index + 1) begin
      {{ci_word, immediate, operands[0], operands[1], operands[2], operands[3],
        operands[4], operands[5], expected_supported, expected_latency,
        expected_valid, expected_results[0], expected_results[1]}} = vectors[index];
      ci_id = ci_word[7:0];
      #1;
      if ((supported !== expected_supported[0]) ||
          (latency !== expected_latency[4:0]) ||
          (result_valid !== expected_valid[1:0]) ||
          (results[0] !== expected_results[0]) ||
          (results[1] !== expected_results[1])) begin
        $fatal(1, "semantic diff mismatch vector=%0d ci_id=%0d got=%h/%h/%h/%h/%h expected=%h/%h/%h/%h/%h",
               index, ci_id, supported, latency, result_valid, results[0], results[1],
               expected_supported[0], expected_latency[4:0], expected_valid[1:0],
               expected_results[0], expected_results[1]);
      end
    end
    $display("PASS: AutoISA semantic RTL/reference differential (%0d vectors)", VECTOR_COUNT);
    $finish;
  end
endmodule
`default_nettype wire
'''
    path.write_text(source, encoding="utf-8", newline="\n")
    return path


def run_command(command: list[str], log_path: Path) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, shell=False)
    log_path.write_text(f"$ {' '.join(command)}\n\n{result.stdout}\n{result.stderr}", encoding="utf-8")
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado", type=Path, default=DEFAULT_VIVADO)
    parser.add_argument("--vectors-per-semantic", type=int, default=10_000)
    parser.add_argument("--generate-only", action="store_true")
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    summary = {"schema_version": "1.0", "seed": SEED, "status": "failed",
               "vectors_per_semantic": args.vectors_per_semantic,
               "generated_at_utc": datetime.now(timezone.utc).isoformat()}
    summary_path = BUILD / "semantic_diff_summary.json"
    try:
        generated = subprocess.run([sys.executable, str(ROOT / "scripts/generate_semantics.py")],
                                   cwd=ROOT, check=True)
        del generated
        reference = load_reference(ROOT / "generated/semantics/autoisa_ci_semantic_ref.py")
        vector_path, count, counts = create_vectors(reference, args.vectors_per_semantic)
        testbench = create_testbench(vector_path, count)
        summary.update({"catalog_sha256": reference.CATALOG_SHA256, "vector_count": count,
                        "ci_vector_counts": {str(key): value for key, value in counts.items()}})
        if args.generate_only:
            summary["status"] = "generated"
            summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            print(f"Generated {count} differential vectors")
            return 0
        vivado = args.vivado.resolve()
        xvlog, xelab, xsim = (find_tool(vivado, tool) for tool in ("xvlog", "xelab", "xsim"))
        commands = [
            ([str(xvlog), "-sv", str(ROOT / "core/autoisa/autoisa_ci_semantic_engine.sv"), str(testbench)], BUILD / "xvlog.log"),
            ([str(xelab), "-top", "tb_autoisa_ci_semantic_diff", "-snapshot", "autoisa_semantic_diff"], BUILD / "xelab.log"),
            ([str(xsim), "autoisa_semantic_diff", "-runall"], BUILD / "xsim.log"),
        ]
        for command, log in commands:
            result = run_command(command, log)
            if result.returncode:
                summary["failed_command"] = command[0]
                return result.returncode
        transcript = (BUILD / "xsim.log").read_text(encoding="utf-8")
        if "PASS: AutoISA semantic RTL/reference differential" not in transcript:
            summary["failed_command"] = "pass-marker"
            return 1
        summary["status"] = "passed"
        print(f"WP8 semantic differential passed: {count} vectors")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        summary["error"] = str(error)
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    finally:
        summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
