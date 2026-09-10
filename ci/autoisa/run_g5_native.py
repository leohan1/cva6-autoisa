#!/usr/bin/env python3
"""Build and execute the Native G5-A P0/P1/P2/P8 scalar/AutoISA pairs."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from .check_cva6_warnings import audit_warning_log
except ImportError:  # Direct script execution.
    from check_cva6_warnings import audit_warning_log

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")
NATIVE_PROFILES = (0, 1, 2, 8)
NATIVE_CASES = (
    (0, "latency"),
    (1, "latency"), (1, "throughput"),
    (2, "latency"), (2, "throughput"),
    (8, "latency"), (8, "throughput"),
)
DATA_RE = re.compile(
    r"G5_DATA: profile=P(?P<profile>[0-8]) mode=(?P<mode>[01]) "
    r"pattern=(?P<pattern>[01]) "
    r"roi_cycles=(?P<cycles>\d+) roi_instret=(?P<instret>\d+) "
    r"checksum0=(?P<checksum0>[0-9a-fA-F]+) checksum1=(?P<checksum1>[0-9a-fA-F]+) "
    r"ci_issue=(?P<issue>\d+) ci_commit=(?P<commit>\d+) ci_result=(?P<result>\d+)"
)
PIPE_RE = re.compile(
    r"G5_PIPE: issue_span=(?P<issue_span>\d+) result_span=(?P<result_span>\d+) "
    r"issue_commit_sum=(?P<commit_sum>\d+) issue_result_sum=(?P<result_sum>\d+) "
    r"inflight_hwm=(?P<inflight_hwm>\d+)"
)


def run(command: list[str], log: Path) -> subprocess.CompletedProcess[str]:
    print("$", " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(output, encoding="utf-8", newline="\n")
    for line in output.splitlines()[-8:]:
        print(line)
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_result(
    output: str, profile: int, measurement: str, variant: str
) -> dict[str, int | float | str]:
    matches = list(DATA_RE.finditer(output))
    pipe_matches = list(PIPE_RE.finditer(output))
    if len(matches) != 1 or len(pipe_matches) != 1:
        raise ValueError(
            f"expected one G5_DATA/G5_PIPE record, found {len(matches)}/{len(pipe_matches)}"
        )
    values = matches[0].groupdict()
    pipe = pipe_matches[0].groupdict()
    expected_mode = 1 if variant == "autoisa" else 0
    expected_pattern = 1 if measurement == "throughput" else 0
    if int(values["profile"]) != profile or int(values["mode"]) != expected_mode or \
            int(values["pattern"]) != expected_pattern:
        raise ValueError("G5_DATA identity disagrees with requested run")
    issue = int(values["issue"])
    commit = int(values["commit"])
    result = int(values["result"])
    return {
        "profile": f"P{profile}", "measurement": measurement, "variant": variant,
        "roi_cycles": int(values["cycles"]), "roi_instret": int(values["instret"]),
        "checksum0": int(values["checksum0"], 16),
        "checksum1": int(values["checksum1"], 16),
        "ci_issue": issue, "ci_commit": commit, "ci_result": result,
        "issue_span_cycles": int(pipe["issue_span"]),
        "result_span_cycles": int(pipe["result_span"]),
        "average_issue_interval": round(int(pipe["issue_span"]) / issue, 6) if issue else 0.0,
        "average_issue_to_commit": round(int(pipe["commit_sum"]) / commit, 6)
        if commit else 0.0,
        "average_issue_to_result": round(int(pipe["result_sum"]) / result, 6)
        if result else 0.0,
        "inflight_high_watermark": int(pipe["inflight_hwm"]),
    }


def summarize(
    runs: list[dict[str, int | float | str]]
) -> list[dict[str, int | float | str]]:
    by_key = {
        (item["profile"], item["measurement"], item["variant"]): item for item in runs
    }
    comparisons: list[dict[str, int | float | str]] = []
    for profile_number, measurement in NATIVE_CASES:
        profile = f"P{profile_number}"
        scalar = by_key[(profile, measurement, "scalar")]
        autoisa = by_key[(profile, measurement, "autoisa")]
        comparisons.append({
            "profile": profile, "measurement": measurement,
            "scalar_cycles": scalar["roi_cycles"],
            "autoisa_cycles": autoisa["roi_cycles"],
            "speedup": round(scalar["roi_cycles"] / autoisa["roi_cycles"], 6),
            "scalar_instret": scalar["roi_instret"],
            "autoisa_instret": autoisa["roi_instret"],
            "instruction_reduction": round(
                1.0 - autoisa["roi_instret"] / scalar["roi_instret"], 6
            ),
            "cycle_outcome": (
                "IMPROVEMENT" if scalar["roi_cycles"] > autoisa["roi_cycles"] else
                "NEUTRAL" if scalar["roi_cycles"] == autoisa["roi_cycles"] else
                "REGRESSION"
            ),
            "autoisa_average_issue_interval": autoisa["average_issue_interval"],
            "autoisa_average_issue_to_commit": autoisa["average_issue_to_commit"],
            "autoisa_average_issue_to_result": autoisa["average_issue_to_result"],
            "autoisa_inflight_high_watermark": autoisa["inflight_high_watermark"],
        })
    return comparisons


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado", type=Path, default=DEFAULT_VIVADO)
    parser.add_argument("--toolchain", type=Path)
    args = parser.parse_args()
    build = ROOT / "ci/autoisa/build"
    g5_build = build / "g5"
    python = sys.executable

    build_command = [python, str(ROOT / "ci/autoisa/build_g5_workloads.py")]
    if args.toolchain:
        build_command.extend(["--toolchain", str(args.toolchain)])
    stages = [
        (build_command, build / "g5_native_build.log"),
        ([python, str(ROOT / "ci/autoisa/prepare_vivado_filelist.py"), "--ariane-elf"],
         build / "g5_native_filelist.log"),
    ]
    for command, log in stages:
        if run(command, log).returncode:
            print(f"ERROR: Native G5-A preparation failed; see {log}", file=sys.stderr)
            return 1

    filelist = build / "cv32a65x_xsim.f"
    snapshot = "autoisa_ci_ariane_g5_native"
    compile_stages = [
        ("xvlog", [str(args.vivado / "xvlog.bat"), "-sv", "-d", "AUTOISA_CI_CVXIF",
                   "-d", "AUTOISA_CI_3R", "-f", str(filelist)], build / "g5_native_xvlog.log"),
        ("xelab", [str(args.vivado / "xelab.bat"), "tb_autoisa_ci_ariane_g5_native",
                   "-s", snapshot, "--timescale", "1ns/1ps"], build / "g5_native_xelab.log"),
    ]
    for stage, command, log in compile_stages:
        result = run(command, log)
        if result.returncode:
            print(f"ERROR: Native G5-A {stage} failed; see {log}", file=sys.stderr)
            return 1
        audit = audit_warning_log(log, stage)
        if audit.actionable:
            for warning in audit.actionable:
                print(f"ACTIONABLE: {warning}", file=sys.stderr)
            return 1

    runs: list[dict[str, int | float | str]] = []
    for profile, measurement in NATIVE_CASES:
        pattern = 1 if measurement == "throughput" else 0
        for variant, autoisa in (("scalar", 0), ("autoisa", 1)):
            hex_image = g5_build / f"p{profile}_{measurement}_{variant}.hex"
            shutil.copyfile(hex_image, build / "g5_run.hex")
            (build / "g5_selection.hex").write_text(
                f"{profile:08x}\n{autoisa:08x}\n{pattern:08x}\n", encoding="ascii"
            )
            log = build / f"g5_native_p{profile}_{measurement}_{variant}.log"
            command = [
                str(args.vivado / "xsim.bat"), snapshot, "-runall",
            ]
            result = run(command, log)
            output = result.stdout + result.stderr
            pass_marker = f"PASS: Native G5-A P{profile} mode={autoisa} pattern={pattern}"
            if result.returncode or pass_marker not in output:
                print(f"ERROR: Native G5-A run failed; see {log}", file=sys.stderr)
                return 1
            try:
                runs.append(parse_result(output, profile, measurement, variant))
            except ValueError as error:
                print(f"ERROR: {error}; see {log}", file=sys.stderr)
                return 1

    comparisons = summarize(runs)
    elf_manifest_path = g5_build / "g5_elf_manifest.json"
    elf_manifest = json.loads(elf_manifest_path.read_text(encoding="utf-8"))
    git_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.strip()
    report = {
        "schema_version": "1.0", "status": "PASS",
        "benefit_outcome": (
            "REGRESSION" if any(item["cycle_outcome"] == "REGRESSION" for item in comparisons)
            else "IMPROVEMENT" if any(item["cycle_outcome"] == "IMPROVEMENT" for item in comparisons)
            else "NEUTRAL"
        ),
        "profiles": [f"P{i}" for i in NATIVE_PROFILES],
        "cases": [{"profile": f"P{p}", "measurement": m} for p, m in NATIVE_CASES],
        "runs": runs, "comparisons": comparisons,
        "provenance": {
            "git_commit": git_commit,
            "contract_sha256": elf_manifest["contract_sha256"],
            "elf_manifest_sha256": sha256(elf_manifest_path),
            "workload_source_sha256": elf_manifest["source_sha256"],
            "testbench_sha256": sha256(
                ROOT / "core/autoisa/tb/tb_autoisa_ci_ariane_elf.sv"
            ),
            "runner_sha256": sha256(Path(__file__)),
            "toolchain": elf_manifest["toolchain"],
            "vivado_bin": str(args.vivado.resolve()),
        },
    }
    summary = build / "g5_native_summary.json"
    summary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for item in report["comparisons"]:
        print(
            f"{item['profile']} {item['measurement']}: cycles "
            f"{item['scalar_cycles']}->{item['autoisa_cycles']} "
            f"speedup={item['speedup']:.6f} instret "
            f"{item['scalar_instret']}->{item['autoisa_instret']}"
        )
    print(f"SUMMARY: {summary}")
    print(f"BENEFIT_OUTCOME: {report['benefit_outcome']}")
    print("PASS: Native G5-A evidence integrity")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
