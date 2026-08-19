# AutoISA Compute-only CI Harness 工作总结（截至 2026-08-11）

## 1. 本阶段结论

本阶段完成了固定种子、10 万周期的随机并发验证，并将其加入默认 Vivado/XSim CI。随机 scoreboard 首轮运行发现并复现了一个定向测试未覆盖的问题：运行中的事务被 kill 后，同一个 `(tag, epoch)` 身份可能在旧引擎响应返回前被复用，导致旧响应被错误匹配到新事务（ABA / late-response alias）。

修复方法是在 inflight table 中为“已经真正进入引擎且随后被 kill”的事务保留 tombstone。tombstone 占用身份和结构槽位但不会退休；旧响应到达后被计为 orphan 并释放槽位。仅进入 skid、尚未启动的事务仍可直接删除，已完成事务也无需等待第二个响应。Concurrent Shell 新增运行中引擎身份跟踪，以区分这三种状态。

## 2. 当前 RTL 构成

- `autoisa_ci_types_pkg.sv`：canonical request/response ABI，包含 tag、epoch、最多 6 输入和 2 输出。
- `autoisa_ci_layout_decoder_v2.sv`：L0–L7 指令布局识别。
- `autoisa_ci_dummy_engine.sv`：D0–D11 bit-exact 参考执行语义、定长/变长延迟、fault 与 backpressure 场景。
- `autoisa_ci_request_queue.sv`：请求 FIFO、判重、flush 与统计。
- `autoisa_ci_inflight_table.sv`：并发事务、commit/kill、完成匹配、tombstone 与终态统计。
- `autoisa_ci_engine_skid.sv`：引擎前 1-entry 弹性缓冲和 kill/flush drop。
- `autoisa_ci_result_queue.sv`：完整 1W/2W response 的原子队列与 backpressure。
- `autoisa_ci_concurrent_shell.sv`：将 Queue、Inflight、Skid、Engine、Result Queue 和 completion credits 串联。
- `tb_autoisa_ci_random_100k.sv`：本阶段新增的固定种子随机 scoreboard。

## 3. 数据通路与事务原则

```text
Canonical Request
  -> Request Queue + Inflight Table 原子分配
  -> oldest live dispatch + completion credit 预留
  -> kill-aware skid
  -> D0-D11 compute engine
  -> tagged completion / killed tombstone absorption
  -> commit gate
  -> Result Queue
  -> Host ready/valid result
```

主要不变量：

1. 同一个 `(tag, epoch)` 不能有两个活动身份。
2. 每次 dispatch 都先预留 result credit，避免完成后无处存放。
3. kill 优先于完成、commit 和退休。
4. 已启动 kill 在晚响应被吸收前不得复用身份。
5. drain 完成后应满足 `accepted = retired + killed`，且所有 occupancy/credit 为 0。

## 4. 新增 10 万周期随机验证

- 固定 seed：`0x1a2b3c4d`，结果可重复。
- stimulus：100,000 cycles，随后确定性 drain。
- 指令：D0–D11 全覆盖；每个请求使用独立参考函数计算期望 response。
- 并发事件：request、commit、kill、4 次安全 flush、随机 result backpressure。
- 强制压力：每 257 周期包含 16 周期 result stall 窗口；result queue 必须达到满深度。
- 检查：完整 packed response bit-exact 比较、tag/epoch 合法性、kill hit、引擎输入输出、计数闭合、无残留 credit。
- 机器可读证据：`ci/autoisa/logs/autoisa_ci_random_100k.json`。

最终固定种子数据：

| 指标 | 数值 |
|---|---:|
| stimulus cycles | 100,000 |
| accepted | 8,872 |
| retired | 4,318 |
| killed | 4,554 |
| safe flushes | 4 |
| orphan completions | 1,290 |
| result queue high watermark | 4 / 4 |
| accounting errors | 0 |

`8,872 = 4,318 + 4,554`，证明最终无未结事务。Request/Inflight 随机阶段的 HWM 为 1；深度 4 的并发占用已由定向 Concurrent Shell 测试覆盖，随机阶段本次重点是长时间身份复用、晚响应和结果反压组合。

## 5. 回归结果

2026-08-11 使用本机 Vivado/XSim 2025.2 完成 tombstone 修改后的七项全量回归，全部通过：

| Testbench | 结果 | 仿真终点/规模 |
|---|---|---:|
| Harness v0 | PASS | 525 ns |
| Request Queue | PASS | 270 ns |
| Inflight Table | PASS | 660 ns |
| Result Queue | PASS | 290 ns |
| Engine Protocols | PASS | 260 ns |
| Concurrent Shell | PASS | 685 ns |
| Random 100k | PASS | 100,000 stimulus cycles |

此外，`core/autoisa` 下全部生产 SystemVerilog 文件再次通过 Vivado `xvlog -sv` 语法分析，`git diff --check` 无空白错误。

## 6. 要求符合性与边界

目前已满足 compute-only、canonical tagged ABI、L0–L7 识别、D0–D11 执行、ready/valid、commit/kill/flush、并发结构、2W 原子结果、completion credit、晚响应隔离和可重复随机验证等初版要求。

尚未完成的系统级工作包括：多物理 engine 调度、Host destination map、多拍 operand gather、CVA6 scoreboard/forwarding/writeback 接入、custom CI ELF，以及综合后的 PPA 数据。下一阶段建议进入多 engine descriptor 与 oldest-ready scheduler，同时保留本阶段 100k regression 作为防回归门槛。
