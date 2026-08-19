# AutoISA Compute-only CI Harness 工作总结（截至 2026-08-10）

> 目标：CVA6 `cv32a65x` / RV32 compute-only Direct-CI Harness   
> 当前进度：**REVISE——并发 Coprocessor Shell 初版已闭环**
> 
## 1. 至今完成的设计

1. **Canonical ABI**：定义 6 输入、2 输出、4-bit tag、2-bit epoch 的 Host descriptor、
   request 和 response。
2. **Layout Decoder v2**：使用 per-layout match/mask，识别 L0–L7，覆盖 2R–6R、
   1W/2W 和 immediate。
3. **Dummy Engine D0–D11**：
   - D0–D7：计算与接口能力；
   - D8：确定性 variable latency 1–8；
   - D9：16-cycle long operation；
   - D10：result backpressure；
   - D11：test-only `ENGINE_FAULT`。
4. **单事务 Harness v0**：decode、execute、commit-gated visibility、kill priority 和
   result backpressure。
5. **Request Queue**：深度 1/2/4/8、bypass、full replacement、flush、occupancy 和计数。
6. **Inflight Table**：4 个同时在途事务、duplicate tag/epoch 拒绝、oldest dispatch、
   OOO completion、commit/kill 和 terminal accounting。
7. **Result Queue**：深度 1/2/4/8，完整 1W/2W response 原子 entry、反压和 flush-drop。
8. **Completion credits**：dispatch reserve；result enqueue、dispatched kill 和 flush
   release；assert `result_occupancy + reserved_credits <= depth`。
9. **Kill-aware engine skid**：1-entry elastic buffer；skid kill 不进入 engine，running
   kill 的晚到 completion 被 drain/drop。
10. **Concurrent Shell**：原子 Queue/Inflight acceptance、入口判重、skid dispatch、
    Dummy Engine、Result Queue、credits、commit/kill/flush 全路径已连接。

## 2. 当前数据通路

```text
Canonical Request
  -> Queue + Inflight 原子分配
  -> oldest live request selection
  -> completion credit reserve
  -> kill-aware 1-entry skid
  -> D0-D11 Dummy Engine
  -> tagged Inflight completion
  -> commit/kill gate
  -> Result Queue
  -> Host result ready/valid
```

## 3. 截至今天的实测数据

| Testbench | 结果 | 结束时间 | 主要证据 |
|---|---|---:|---|
| Harness v0 | PASS | 525 ns | L0–L7、D0–D7、commit/kill/backpressure |
| Request Queue | PASS | 270 ns | full/bypass/replacement/flush/counters |
| Inflight Table | PASS | 660 ns | 4 inflight、OOO completion、三阶段 kill |
| Result Queue | PASS | 290 ns | 2W 原子 entry、full、flush-drop |
| Engine Protocols | PASS | 260 ns | D8=1/8 cycle、D10 stall=3、D11 fault |
| Concurrent Shell | PASS | 685 ns | skid、credits、result full、kill、flush |

Result Queue 数据：

```text
enqueued=8, dequeued=6, full_stall=1, flush_drop=2
```

Concurrent Shell 数据：

```text
accepted=8
dispatched_to_skid=8
engine_started=6
completed=6
retired=4
killed=4
orphan_completion=2
skid_killed_drop=1
skid_flush_drop=1
request_high_watermark=2
inflight_high_watermark=4
result_high_watermark=2
credit_high_watermark=2
credit_stall_cycles=24
final_reserved_credits=0
```


## 4. 需求符合性结论

目前已经符合或初步符合：

- compute-only，无默认 memory side effect；
- canonical tagged ABI；
- L0–L7 和 D0–D11；
- ready/valid payload stability；
- Request/Inflight/Result storage；
- 至少 4 个 simultaneous inflight；
- tagged OOO completion 单元验证；
- queued/skid/running/completed kill；
- result-before-commit 与 commit-before-result；
- 2W 原子 result entry；
- completion credit 无泄漏定向测试。

仍未满足完整 Harness 要求：

- 多 engine oldest-ready scheduler；
- Q00–Q15 全套和 fixed-seed 100k-cycle random；
- Host tagged destination map；
- 两物理读口的 1–6R multi-beat gather；
- CVA6 scoreboard、forwarding、writeback 和 custom CI ELF；
- schema/typed CDFG/SV/reference 自动生成；
- semantic CI A/B 收益和 PPA。


## 5. 下一步

1. 增加多 engine descriptor 和 oldest-ready selection；
2. 建立 Q00–Q14 定向场景与固定 seed 的 100k-cycle Q15；
3. 输出 counters、occupancy、credits、seed 和结果 hash 的 JSON；
4. 并发 shell 关闭后进入 Host destination map、operand gather 和 CVA6 integration。
