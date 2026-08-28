#!/usr/bin/env python3
"""AutoISA Direct-CI CI harness.

Runs xvlog -> xelab -> xsim on each AutoISA testbench and reports pass/fail.
Designed for Vivado/XSim 2025.2; the Vivado bin path is configurable.

Usage:
    python run_ci.py                          # run all testbenches
    python run_ci.py --tb autoisa_ci_harness_v0   # run one testbench
    python run_ci.py --clean                  # remove xsim work dirs and logs
    python run_ci.py --root D:/path/to/cva6-autoisa   # explicit project root
    python run_ci.py --vivado D:/apps/HLS/2025.2/Vivado/bin
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_VIVADO = Path(r"D:/apps/HLS/2025.2/Vivado/bin")
# Project root: ci/autoisa/run_ci.py  ->  ci/autoisa  ->  ci  ->  cva6-autoisa
DEFAULT_ROOT = Path(__file__).resolve().parent.parent.parent

TESTBENCHES = [
    {
        "name": "autoisa_ci_harness_v0",
        "top": "tb_autoisa_ci_harness_v0",
        "snapshot": "autoisa_sim_v0",
        "filelist": "core/autoisa/tb/autoisa_ci_harness_v0.f",
        "log": "autoisa_ci_harness_v0.log",
    },
    {
        "name": "autoisa_ci_request_queue",
        "top": "tb_autoisa_ci_request_queue",
        "snapshot": "autoisa_sim_rq",
        "filelist": "core/autoisa/tb/autoisa_ci_request_queue.f",
        "log": "autoisa_ci_request_queue.log",
    },
    {
        "name": "autoisa_ci_inflight_table",
        "top": "tb_autoisa_ci_inflight_table",
        "snapshot": "autoisa_sim_inflight",
        "filelist": "core/autoisa/tb/autoisa_ci_inflight_table.f",
        "log": "autoisa_ci_inflight_table.log",
    },
    {
        "name": "autoisa_ci_result_queue",
        "top": "tb_autoisa_ci_result_queue",
        "snapshot": "autoisa_sim_result_queue",
        "filelist": "core/autoisa/tb/autoisa_ci_result_queue.f",
        "log": "autoisa_ci_result_queue.log",
    },
    {
        "name": "autoisa_ci_engine_protocols",
        "top": "tb_autoisa_ci_engine_protocols",
        "snapshot": "autoisa_sim_engine_protocols",
        "filelist": "core/autoisa/tb/autoisa_ci_engine_protocols.f",
        "log": "autoisa_ci_engine_protocols.log",
    },
    {
        "name": "autoisa_ci_concurrent_shell",
        "top": "tb_autoisa_ci_concurrent_shell",
        "snapshot": "autoisa_sim_concurrent",
        "filelist": "core/autoisa/tb/autoisa_ci_concurrent_shell.f",
        "log": "autoisa_ci_concurrent_shell.log",
    },
    {
        "name": "autoisa_ci_random_100k",
        "top": "tb_autoisa_ci_random_100k",
        "snapshot": "autoisa_sim_random_100k",
        "filelist": "core/autoisa/tb/autoisa_ci_random_100k.f",
        "log": "autoisa_ci_random_100k.log",
    },
    {
        "name": "autoisa_ci_multi_engine_cluster",
        "top": "tb_autoisa_ci_multi_engine_cluster",
        "snapshot": "autoisa_sim_multi_engine",
        "filelist": "core/autoisa/tb/autoisa_ci_multi_engine_cluster.f",
        "log": "autoisa_ci_multi_engine_cluster.log",
    },
    {
        "name": "autoisa_ci_operand_gather",
        "top": "tb_autoisa_ci_operand_gather",
        "snapshot": "autoisa_sim_operand_gather",
        "filelist": "core/autoisa/tb/autoisa_ci_operand_gather.f",
        "log": "autoisa_ci_operand_gather.log",
    },
    {
        "name": "autoisa_ci_cva6_host_adapter",
        "top": "tb_autoisa_ci_cva6_host_adapter",
        "snapshot": "autoisa_sim_cva6_host_adapter",
        "filelist": "core/autoisa/tb/autoisa_ci_cva6_host_adapter.f",
        "log": "autoisa_ci_cva6_host_adapter.log",
    },
    {
        "name": "autoisa_ci_destination_map",
        "top": "tb_autoisa_ci_destination_map",
        "snapshot": "autoisa_sim_destination_map",
        "filelist": "core/autoisa/tb/autoisa_ci_destination_map.f",
        "log": "autoisa_ci_destination_map.log",
    },
    {
        "name": "autoisa_ci_multi_engine_shell",
        "top": "tb_autoisa_ci_multi_engine_shell",
        "snapshot": "autoisa_sim_multi_shell",
        "filelist": "core/autoisa/tb/autoisa_ci_multi_engine_shell.f",
        "log": "autoisa_ci_multi_engine_shell.log",
    },
    {
        "name": "autoisa_ci_random_100k_multi",
        "top": "tb_autoisa_ci_random_100k_multi",
        "snapshot": "autoisa_sim_random_100k_multi",
        "filelist": "core/autoisa/tb/autoisa_ci_random_100k.f",
        "log": "autoisa_ci_random_100k_multi.log",
    },
    {
        "name": "autoisa_ci_cva6_host_transport",
        "top": "tb_autoisa_ci_cva6_host_transport",
        "snapshot": "autoisa_sim_host_transport",
        "filelist": "core/autoisa/tb/autoisa_ci_cva6_host_transport.f",
        "log": "autoisa_ci_cva6_host_transport.log",
    },
    {
        "name": "autoisa_ci_cvxif_coprocessor",
        "top": "tb_autoisa_ci_cvxif_coprocessor",
        "snapshot": "autoisa_sim_cvxif",
        "filelist": "core/autoisa/tb/autoisa_ci_cvxif_coprocessor.f",
        "log": "autoisa_ci_cvxif_coprocessor.log",
    },
]


def find_tool(vivado_bin: Path, name: str) -> Path:
    """Locate a Vivado tool by name.  Tries `<name>.bat`, `<name>.exe`, and the
    `unwrapped/win64.o/<name>.exe` form that some installs use internally.
    """
    for cand in (vivado_bin / f"{name}.bat",
                 vivado_bin / f"{name}.exe",
                 vivado_bin / "unwrapped" / "win64.o" / f"{name}.exe"):
        if cand.exists():
            return cand
    raise FileNotFoundError(
        f"Cannot find Vivado tool '{name}' under {vivado_bin}. "
        "Pass --vivado to point at the Vivado bin directory."
    )


def step(label: str, cmd: list, cwd: Path, log_path: Path = None) -> subprocess.CompletedProcess:
    """Run a command, optionally tee output to a log file, return CompletedProcess."""
    print(f"  $ {' '.join(map(str, cmd))}")
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        # Run synchronously, capture output, write to log so the user can inspect.
        result = subprocess.run(
            cmd, cwd=str(cwd), capture_output=True, text=True, shell=False
        )
        with log_path.open("w", encoding="utf-8") as fh:
            fh.write(f"$ {' '.join(map(str, cmd))}\n")
            fh.write(f"cwd: {cwd}\n")
            fh.write(f"exit: {result.returncode}\n")
            fh.write("\n--- stdout ---\n")
            fh.write(result.stdout)
            if result.stderr:
                fh.write("\n--- stderr ---\n")
                fh.write(result.stderr)
        # Echo tail to console for live feedback.
        tail = (result.stdout or "").splitlines()[-6:]
        for line in tail:
            print(f"    | {line}")
        return result
    else:
        return subprocess.run(cmd, cwd=str(cwd))


def detect_pass(result: subprocess.CompletedProcess) -> tuple[bool, str]:
    """Decide pass/fail from xsim output.

    Pass = exit code 0 AND transcript contains "PASS:".
    Fail = anything else, with a short reason.
    """
    out = (result.stdout or "") + "\n" + (result.stderr or "")
    if result.returncode != 0:
        return False, f"xsim exit code = {result.returncode}"
    if "$fatal" in out.lower() or "fatal:" in out.lower():
        return False, "$fatal in transcript (assertion or timeout)"
    if "ERROR:" in out:
        return False, "ERROR: line in transcript"
    if "PASS:" in out:
        return True, "PASS line found"
    return False, "no PASS: line in transcript"


def clean(root: Path, log_dir: Path) -> None:
    """Remove xsim work directories and CI logs."""
    targets = []
    for tb in TESTBENCHES:
        targets.append(root / "xsim.dir")
    if log_dir.exists():
        targets.append(log_dir)
    for tb in TESTBENCHES:
        wd = root / "xsim.dir"
        if wd.exists():
            shutil.rmtree(wd, ignore_errors=True)
    if log_dir.exists():
        shutil.rmtree(log_dir, ignore_errors=True)
    print("cleaned xsim work dirs and log dir")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT,
                        help="Path to cva6-autoisa project root (default: parent of this script's parent).")
    parser.add_argument("--vivado", type=Path, default=DEFAULT_VIVADO,
                        help="Path to Vivado bin directory (default: %(default)s).")
    parser.add_argument("--tb", action="append", default=[],
                        help="Run only this testbench (name). Repeatable. Default: all.")
    parser.add_argument("--clean", action="store_true",
                        help="Remove xsim work dirs and CI logs, then exit.")
    parser.add_argument("--no-logs", action="store_true",
                        help="Do not write per-TB transcript logs.")
    parser.add_argument("--skip-layout-generate", action="store_true",
                        help="Use the checked-in Layout v2 RTL without regenerating it first.")
    parser.add_argument("--skip-semantic-generate", action="store_true",
                        help="Use the checked-in Semantic v2 RTL without regenerating it first.")
    args = parser.parse_args()

    root: Path = args.root.resolve()
    vivado_bin: Path = args.vivado.resolve()
    log_dir: Path = Path(__file__).resolve().parent / "logs"

    if not root.is_dir():
        print(f"ERROR: project root does not exist: {root}", file=sys.stderr)
        return 2
    if not vivado_bin.is_dir():
        print(f"ERROR: Vivado bin dir does not exist: {vivado_bin}", file=sys.stderr)
        return 2

    if args.clean:
        clean(root, log_dir)
        return 0

    if not args.skip_layout_generate:
        generator = root / "scripts/generate_layout_decoder.py"
        result = step("layout-v2", [sys.executable, str(generator)], cwd=root)
        if result.returncode != 0:
            print("ERROR: Layout v2 generation/validation failed", file=sys.stderr)
            return 2

    if not args.skip_semantic_generate:
        generator = root / "scripts/generate_semantics.py"
        result = step("semantic-v2", [sys.executable, str(generator)], cwd=root)
        if result.returncode != 0:
            print("ERROR: Semantic v2 generation/validation failed", file=sys.stderr)
            return 2

    try:
        xvlog = find_tool(vivado_bin, "xvlog")
        xelab = find_tool(vivado_bin, "xelab")
        xsim = find_tool(vivado_bin, "xsim")
    except FileNotFoundError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    selected = [tb for tb in TESTBENCHES if not args.tb or tb["name"] in args.tb]
    if args.tb:
        unknown = set(args.tb) - {tb["name"] for tb in TESTBENCHES}
        if unknown:
            print(f"ERROR: unknown testbench(es): {sorted(unknown)}", file=sys.stderr)
            return 2

    print(f"AutoISA CI harness")
    print(f"  project root : {root}")
    print(f"  vivado bin   : {vivado_bin}")
    print(f"  testbenches  : {[tb['name'] for tb in selected]}")
    print(f"  layout v2    : {'checked-in' if args.skip_layout_generate else 'regenerated'}")
    print(f"  semantic v2  : {'checked-in' if args.skip_semantic_generate else 'regenerated'}")
    print(f"  log dir      : {log_dir if not args.no_logs else '(disabled)'}")
    print()

    results: list[tuple[str, bool, str]] = []
    for tb in selected:
        print(f"=== {tb['name']} ===")
        flist = root / tb["filelist"]
        if not flist.is_file():
            print(f"  ERROR: filelist not found: {flist}")
            results.append((tb["name"], False, "missing filelist"))
            continue

        log_path = None if args.no_logs else (log_dir / tb["log"])

        # 1) xvlog
        r = step("xvlog", [str(xvlog), "-sv", "-f", str(flist)], cwd=root, log_path=None)
        if r.returncode != 0:
            print(f"  xvlog FAILED (exit {r.returncode})")
            results.append((tb["name"], False, f"xvlog exit {r.returncode}"))
            continue

        # 2) xelab
        r = step("xelab", [str(xelab), "-top", tb["top"], "-snapshot", tb["snapshot"]],
                 cwd=root, log_path=None)
        if r.returncode != 0:
            print(f"  xelab FAILED (exit {r.returncode})")
            results.append((tb["name"], False, f"xelab exit {r.returncode}"))
            continue

        # 3) xsim  (log written here)
        r = step("xsim", [str(xsim), tb["snapshot"], "-runall"], cwd=root, log_path=log_path)
        passed, reason = detect_pass(r)
        if passed:
            print(f"  PASS  ({reason})")
        else:
            print(f"  FAIL  ({reason})")
            print(f"  transcript: {log_path if log_path else '(no log written)'}")
        results.append((tb["name"], passed, reason))

    # summary
    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    width = max(len(n) for n, _, _ in results) if results else 10
    for name, ok, reason in results:
        flag = "PASS" if ok else "FAIL"
        print(f"  {name:<{width}}  {flag}   {reason}")
    failed = [n for n, ok, _ in results if not ok]
    if failed:
        print()
        print(f"FAILED: {', '.join(failed)}")
        return 1
    print()
    print("ALL TESTBENCHES PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
