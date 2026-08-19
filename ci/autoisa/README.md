# AutoISA Direct-CI CI Harness

Reproducible CI baseline for the AutoISA compute-only Direct-CI Harness on
CVA6 (`cv32a65x`, RV32).  It wraps Vivado/XSim 2025.2 so a single `make ci`
runs all 15 production testbench configurations and reports pass/fail.

Every normal CI run first validates `config/layout_profiles_v2.json` and
regenerates the Layout v2 RTL/software artifacts. Use `make wp0-wp1` to run
the complete Gate G0 suite independently (negative tests, deterministic
generation, 6R2W, scattered immediate, 10k round-trip and Vivado smoke).

The native scalar integration can be selected in an `ariane` build with the
SystemVerilog define `AUTOISA_CI_CVXIF`. It uses CVA6's real CV-X-IF
issue/register/commit/result structs. Layouts requiring more CV-X-IF operands
than `X_NUM_RS`, or requiring pair writeback, are rejected and remain on the
Direct-CI sidecar integration path.

## What it runs

| Testbench            | Top module                     | Filelist                                            | What's checked                                            |
|----------------------|--------------------------------|-----------------------------------------------------|-----------------------------------------------------------|
| `autoisa_ci_harness_v0`     | `tb_autoisa_ci_harness_v0`     | `core/autoisa/tb/autoisa_ci_harness_v0.f`     | L0–L7 decode, D0–D7 compute, commit/kill, backpressure  |
| `autoisa_ci_request_queue`  | `tb_autoisa_ci_request_queue`  | `core/autoisa/tb/autoisa_ci_request_queue.f`  | FIFO depth 1/2/4/8, flush, counters, bypass              |
| `autoisa_ci_inflight_table` | `tb_autoisa_ci_inflight_table` | `core/autoisa/tb/autoisa_ci_inflight_table.f` | duplicate identity, OOO completion, commit/kill          |
| `autoisa_ci_result_queue` | `tb_autoisa_ci_result_queue` | `core/autoisa/tb/autoisa_ci_result_queue.f` | FIFO depths, 2W atomic entry, backpressure, flush         |
| `autoisa_ci_engine_protocols` | `tb_autoisa_ci_engine_protocols` | `core/autoisa/tb/autoisa_ci_engine_protocols.f` | D8 variable latency, D10 stall, D11 fault                 |
| `autoisa_ci_concurrent_shell` | `tb_autoisa_ci_concurrent_shell` | `core/autoisa/tb/autoisa_ci_concurrent_shell.f` | atomic ingress, queue HWM>1, four inflight, flush         |
| `autoisa_ci_random_100k` | `tb_autoisa_ci_random_100k` | `core/autoisa/tb/autoisa_ci_random_100k.f` | fixed-seed D0-D11 bit-exact scoreboard, kill/flush/backpressure |
| `autoisa_ci_multi_engine_cluster` | `tb_autoisa_ci_multi_engine_cluster` | `core/autoisa/tb/autoisa_ci_multi_engine_cluster.f` | CI-to-engine mapping, oldest-ready bypass, parallel busy, response arbitration |
| `autoisa_ci_destination_map` | `tb_autoisa_ci_destination_map` | `core/autoisa/tb/autoisa_ci_destination_map.f` | tagged 1W/2W ownership, RAW/WAW, stale epoch, kill/flush release |
| `autoisa_ci_multi_engine_shell` | `tb_autoisa_ci_multi_engine_shell` | `core/autoisa/tb/autoisa_ci_multi_engine_shell.f` | multi-engine shell integration, pending kill/flush and completion credits |
| `autoisa_ci_random_100k_multi` | `tb_autoisa_ci_random_100k_multi` | `core/autoisa/tb/autoisa_ci_random_100k.f` | fixed-seed multi-engine 100k-cycle randomized closure |
| `autoisa_ci_cva6_host_adapter` | `tb_autoisa_ci_cva6_host_adapter` | `core/autoisa/tb/autoisa_ci_cva6_host_adapter.f` | CVA6 trans_id mapping, epoch, commit/kill, tagged Host result routing |
| `autoisa_ci_cva6_host_transport` | `tb_autoisa_ci_cva6_host_transport` | `core/autoisa/tb/autoisa_ci_cva6_host_transport.f` | End-to-end adapter, 1–6R gather, shell, early commit replay and scalar/pair WB |
| `autoisa_ci_cvxif_coprocessor` | `tb_autoisa_ci_cvxif_coprocessor` | `core/autoisa/tb/autoisa_ci_cvxif_coprocessor.f` | Real CV-X-IF typed scalar AutoISA issue/register/commit/result bridge |
| `autoisa_ci_operand_gather` | `tb_autoisa_ci_operand_gather` | `core/autoisa/tb/autoisa_ci_operand_gather.f` | queued 1-6R capture over two physical read ports, kill/flush/backpressure |

Pass/fail is decided by a `PASS:` line in the xsim transcript and a zero
xsim exit code.  Anything else (`$fatal`, `ERROR:`, non-zero exit, missing
`PASS:`) is reported as fail with the transcript path printed for inspection.

## Layout

```
ci/autoisa/
├── run_wp0_wp1.py ← WP0/WP1 generator and Gate G0 entry
├── run_ci.py     ← the actual harness (Python)
├── run_ci.cmd    ← CMD wrapper (calls Python)
├── Makefile      ← make ci / make ci-v0 / make ci-rq
├── README.md     ← this file
└── logs/         ← xsim transcripts, one per TB (created on first run)
```

The AutoISA production RTL, generated decoder, testbenches, CVA6 file lists,
and the optional `AUTOISA_CI_CVXIF` Ariane integration are part of this
baseline.  Reproducible Vivado build products remain ignored.

## Quick start

```bash
# Default: Vivado at D:/apps/HLS/2025.2/Vivado/bin
cd D:/assignment/Direct-CI\ Integration/cva6-autoisa/ci/autoisa
make ci
```

Or run the Python script directly:

```bash
python run_ci.py
```

WP0/WP1 only:

```bash
python ci/autoisa/run_wp0_wp1.py --vivado D:/apps/HLS/2025.2/Vivado/bin
```

RV32 software-toolchain preparation:

```bash
python ci/autoisa/check_riscv_toolchain.py
```

The check searches `--toolchain`, `AUTOISA_RISCV_TOOLCHAIN`, the ignored local
`tools/xpack-riscv-none-elf-gcc-*` directory, and finally `PATH`.  It builds a
freestanding `rv32imac_zicsr/ilp32` ELF from
`tests/autoisa/software/minimal_d0.S`, verifies the ELF32 RISC-V header, and
checks that the generated binary contains the expected D0 instruction encoding
`0x007302db`.  Build outputs go to the ignored `ci/autoisa/build/software/`
directory.

Or from CMD:

```cmd
cd /d "D:\assignment\Direct-CI Integration\cva6-autoisa\ci\autoisa"
run_ci.cmd
```

Expected output (excerpt):

```
AutoISA CI harness
  project root : D:\assignment\Direct-CI Integration\cva6-autoisa
  vivado bin   : D:\apps\HLS\2025.2\Vivado\bin
  testbenches  : ['autoisa_ci_harness_v0', 'autoisa_ci_request_queue']
  log dir      : ...\ci\autoisa\logs

=== autoisa_ci_harness_v0 ===
  $ ...\xvlog.bat -sv -f ...\autoisa_ci_harness_v0.f
  $ ...\xelab.bat -top tb_autoisa_ci_harness_v0 -snapshot autoisa_sim_v0
  $ ...\xsim.bat autoisa_sim_v0 -runall
  PASS  (PASS line found)
=== autoisa_ci_request_queue ===
  $ ...
  PASS  (PASS line found)

============================================================
SUMMARY
============================================================
  autoisa_ci_harness_v0     PASS   PASS line found
  autoisa_ci_request_queue  PASS   PASS line found

ALL TESTBENCHES PASSED
```

## Selecting a subset

```bash
make ci-v0              # only the harness testbench
make ci-rq              # only the request queue testbench
make ci-inf             # only the inflight table testbench
make ci-result          # only the result queue testbench
make ci-proto           # only the D8-D11 protocol testbench
make ci-shell           # only the concurrent shell testbench
make ci-random          # fixed seed, 100,000 stimulus cycles
make ci-multi           # two-engine oldest-ready scheduler
python run_ci.py --tb autoisa_ci_harness_v0
```

## Override paths

```bash
# Override Vivado bin
make ci VIVADO=D:/apps/HLS/2024.2/Vivado/bin

# Override project root (any way to spell the path with a space)
make ci ROOT="D:/assignment/Direct-CI Integration/cva6-autoisa"
python run_ci.py --root "D:/assignment/Direct-CI Integration/cva6-autoisa"

# From the CMD wrapper, set env vars instead of flags
set CI_PROJECT_ROOT=D:\assignment\Direct-CI Integration\cva6-autoisa
set CI_VIVADO_BIN=D:\apps\HLS\2024.2\Vivado\bin
run_ci.cmd
```

## Cleaning

```bash
make clean                # remove xsim work dirs and logs/
python run_ci.py --clean
```

## Where the logs go

Per-TB xsim transcripts are written to:

```
ci/autoisa/logs/autoisa_ci_harness_v0.log
ci/autoisa/logs/autoisa_ci_request_queue.log
ci/autoisa/logs/autoisa_ci_random_100k.log
ci/autoisa/logs/autoisa_ci_random_100k.json
```

If a test fails, the log path is printed so you can `tail` it.  The `xsim.dir`
working directory is left in place after the run so you can re-run xsim
interactively if needed.

## Limitations (intentional, by design)

- This is the **minimum** CI: no lint, no waveform diff, no coverage, no
  regression comparison.  It only answers "did the testbench still pass?"
- The script does not vendor a Vivado license.  If you point `--vivado` at a
  Vivado install that needs a license, xsim will fail with whatever message
  AMD ships.
- The flow runs serially.  If you add more testbenches later and the runtime
  becomes painful, add a `multiprocessing.Pool` wrapper around the per-TB
  loop in `run_ci.py`.

## Adding a new testbench

1. Append a dict to `TESTBENCHES` in `run_ci.py` with `name`, `top`,
   `snapshot`, `filelist`, and `log` keys.
2. Add a `make ci-<short-name>` target to the `Makefile` if you want a
   per-testbench shortcut.
3. `make ci` now runs it alongside the existing configurations.

## Frozen baseline

The 2026-08-19 baseline was revalidated with Vivado/XSim 2025.2:

- Layout generator tests: 10/10 PASS, including 10,000 encoder/decoder round trips.
- Source manifest: 20 production RTL sources, ABI v1.0.
- Q00-Q15 evidence audit: 16/16 PASS.
- Harness regression: 15/15 PASS, including both 100k-cycle random configurations.
- Full Ariane smoke: stock and `AUTOISA_CI_CVXIF` both compile, elaborate, and run to 195 ns.

The current integration boundary is still reset-level Ariane smoke.  Executing
an ELF containing AutoISA instructions and checking architectural retirement is
the next gate; this baseline does not claim that program-level closure.
