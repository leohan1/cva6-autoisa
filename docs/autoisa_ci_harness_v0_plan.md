# AutoISA compute-only CI Harness implementation plan

## Scope decision

The first RTL drop is a functional, single-inflight slice. It proves that an
instruction can be recognized, normalized into the canonical ABI, evaluated as
a pure function, held private until commit, killed without writeback, and
returned through a stable ready/valid channel. It is intentionally not the
complete concurrent Harness.

Memory-fused/H1 forms are excluded from the default path. The existing H1
experiment remains optional and separate.

## v0 instruction layouts

Every layout uses an explicit 32-bit match/mask entry. `layout_id` is produced by
the decoder; it is not a globally fixed instruction field.

| Layout | Recognition | Payload | Initial semantic |
|---|---|---|---|
| L0 2R1W GPR32 | custom-2, funct3=0 | rd, rs1, rs2, ci_id[6:0] | D0_ADD2 |
| L1 3R1W GPR32 | custom-2, funct3=1 | rd, rs1, rs2, rs3, ci_id[1:0] | D1_MAC3 |
| L2 4R1W GPR8 | custom-2, funct3=2 | four RVC8 sources, one RVC8 destination, ci_id[4:0] | D2_MIX4 |
| L3 2R2W pair | custom-2, funct3=3 | rs1, rs2, even rd0, derived rd1, ci_id[6:0] | D3_SUMDIFF |
| L4 4R2W GPR8 | custom-2, funct3=4 plus reserved high bits | four RVC8 sources, two RVC8 destinations | fixed D4_BFLY4X2 |
| L5 6R1W GPR8 | custom-1 plus reserved high bits | six sources, one destination | fixed D5_REDUCE6 |
| L6 6R2W GPR8 | custom-3 plus reserved bit 31 | six sources, two destinations | fixed D6_DUAL6 |
| L7 2R1W immediate | custom-0 | rd, rs1, rs2, scattered signed imm10 (`imm[9:3]=instr[31:25]`, `imm[2:0]=instr[14:12]`) | fixed D7_IMM_MIX |

## Delivery stages

1. **Functional slice (this drop)**: canonical types, v2 decoder, D0-D7 engine,
   tag/epoch, commit visibility, kill priority and self-checking unit test.
2. **Concurrent coprocessor shell**: depth-parameterized request/inflight/result
   storage, oldest-ready dispatch, completion credits, D8-D11 and OOO tests.
3. **Host transport**: tagged destination map, atomic 2W reservation and a
   two-physical-port gather queue for 1-6 logical sources.
4. **CVA6 integration**: extended operand/result sidecar, forwarding/writeback,
   mixed architectural ELF tests and standard regressions.
5. **Generation/release**: schema-driven decoder and encoder generation,
   differential reference, benefit A/B, PPA and reproducible manifests.

WP0/WP1 update (2026-08-17): the Layout v2 catalog, schemas, overlap and
bit-budget checks, RTL/Python/C/assembly generation, deterministic manifest and
G0 regression are implemented. Layout v2 RTL is regenerated automatically by
the normal CI entry point. Differential semantic reference, benefit A/B and PPA
remain later work packages.

Current stage-2 progress: the canonical request queue is implemented with
depth 1/2/4/8 support, fall-through bypass, simultaneous enqueue/dequeue,
flush, occupancy/high-watermark and lifetime traffic/stall counters. A
depth-parameterized inflight table provides duplicate identity
rejection, oldest-first dispatch, out-of-order completion capture, commit-gated
retirement, queued/running/completed kill handling, stable stalled results and
terminal accounting. A minimal concurrent shell now atomically allocates each
accepted request into both the request queue and inflight table, rejects queued
or inflight duplicate identities, drains killed queue tombstones, dispatches to
one dummy engine, captures late killed/flush completions, and retires only
committed results. A D9 long-latency dummy creates measured queue occupancy
above one. A parameterized result queue now stores complete 1W/2W responses,
and the shell reserves one completion credit at dispatch, releases it at result
enqueue or dispatched kill, clears credits on flush, and blocks dispatch before
capacity can overflow. A kill-aware one-entry engine skid buffer is integrated:
requests killed in the skid never execute, while running kills drain a late
engine result. D8 variable-latency (1-8), D9 long (16), D10 output-backpressure
and D11 engine-fault dummies now close the protocol catalog. Fixed-seed
100k-cycle randomized closure is active. A standalone two-engine cluster now
maps D0-D7 to engine 0 and D8-D11 to engine 1, keeps a depth-4 pending table,
selects the oldest request whose target engine is ready, and locks merged
responses under backpressure. Integration of this cluster with the concurrent
shell's kill/flush/credit path remains pending.

Protocol-dummy regression command:

```sh
python ci/autoisa/run_ci.py --tb autoisa_ci_engine_protocols
```

Result-queue regression command:

```sh
python ci/autoisa/run_ci.py --tb autoisa_ci_result_queue
```

Concurrent-shell regression command:

```sh
python ci/autoisa/run_ci.py --tb autoisa_ci_concurrent_shell
```

Inflight-table regression command:

```sh
verilator --binary --timing --assert -Wall -Wno-fatal \
  --top-module tb_autoisa_ci_inflight_table \
  -f core/autoisa/tb/autoisa_ci_inflight_table.f
./obj_dir/Vtb_autoisa_ci_inflight_table
```

Request-queue regression command:

```sh
verilator --binary --timing --assert -Wall -Wno-fatal \
  --top-module tb_autoisa_ci_request_queue \
  -f core/autoisa/tb/autoisa_ci_request_queue.f
./obj_dir/Vtb_autoisa_ci_request_queue
```

## v0 acceptance checks

- Eight layouts decode without overlap; x0 destinations are rejected.
- Pair destinations reject x0, odd rd0 and x31.
- D0-D7 implement the documented 32-bit bit-vector formulas.
- Results are invisible before matching tag+epoch commit.
- Matching kill suppresses writeback and wins a same-cycle completion race.
- Result payload remains stable while `result_valid && !result_ready`.
- Unsupported semantic/layout combinations are rejected explicitly.

From the repository root, the standalone regression command is:

```sh
verilator --binary --timing --assert -Wall -Wno-fatal \
  --top-module tb_autoisa_ci_harness_v0 \
  -f core/autoisa/tb/autoisa_ci_harness_v0.f
./obj_dir/Vtb_autoisa_ci_harness_v0
```

## Known v0 limitations

- One live transaction; no request/result FIFO or OOO completion yet.
- Operands arrive already gathered; the CVA6 two-port gather path is not wired.
- Destination reservation, forwarding and architectural writeback remain Host
  integration work.
- D8-D11 protocol dummies and exception terminal paths are deferred.
- The layout table is hand-authored for bring-up; schema generation is next.
