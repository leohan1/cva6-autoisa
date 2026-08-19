# AutoISA Compute-only CI Harness 阶段总结（2026-08-13）

## 本阶段目标

在已经通过 10 万周期随机验证的单引擎 Concurrent Shell 之外，建立多物理 Engine 调度的第一版可验证 RTL。为了控制修改风险，本次先把多引擎调度做成独立 cluster，没有立即替换现有 shell 的已验证单引擎通路。

## 新增设计

### 1. Engine Descriptor

`autoisa_ci_engine_descriptor.sv` 提供静态 CI-to-engine 映射：

| CI ID | Physical Engine | 用途 |
|---|---:|---|
| D0–D7 | Engine 0 | 基础 compute semantics |
| D8–D11 | Engine 1 | variable/long latency、backpressure、fault protocol |
| 其他 | unsupported | 不进入 pending scheduler |

Descriptor 的选择结果会在请求进入 pending table 时一同保存，调度扫描不再重复解释 CI ID。

### 2. Oldest-ready Multi-engine Cluster

`autoisa_ci_multi_engine_cluster.sv` 当前包含：

- 深度 4 的 pending table；
- 单调 age 编号；
- 两个可独立运行的 dummy physical engines；
- oldest-ready 扫描：只在目标 engine ready 的候选中选择 age 最小者；
- 每周期最多 dispatch 一个请求；
- 两路 response merge；
- response grant lock，保证反压期间输出 payload 不会因另一 engine 完成而改变；
- accepted、分 engine dispatch、completion、unsupported stall、occupancy/HWM 统计。

数据流如下：

```text
Canonical request
  -> CI-to-engine descriptor
  -> depth-4 pending table + age
  -> oldest request whose target engine is ready
       -> Engine 0 (D0-D7)
       -> Engine 1 (D8-D11)
  -> locked response arbiter
  -> tagged canonical response
```

## 定向验证结果

`tb_autoisa_ci_multi_engine_cluster.sv` 构造了两个关键场景。

第一组先向 Engine 1 提交长延迟 D9，再提交第二个 D9，最后提交较新的 D0。第二个 D9 因 Engine 1 busy 暂停，但 D0 可以绕过它并进入空闲的 Engine 0。实际完成顺序为 `tag 3 -> tag 1 -> tag 2`，证明调度不是简单 FIFO head blocking。

第二组让 Engine 1 的 D8 响应先到并持续 backpressure，同时 Engine 0 的 D4 在阻塞期间完成。Response arbiter 保持 Engine 1 grant，直到该响应握手后才允许 Engine 0 输出，验证了 ready/valid payload stability。

Vivado/XSim 2025.2 单项结果：

```text
accepted=5
engine0_dispatch=2
engine1_dispatch=3
completed=5
parallel_busy_cycles=11
pending_high_watermark=2
unsupported_stall=1
first_group_completion_order=3,1,2
PASS
```

## 与现有 Shell 的关系

当前 multi-engine cluster 是独立、可测试的下一阶段构件；现有 `autoisa_ci_concurrent_shell.sv` 仍使用单 dummy engine。暂不直接接入的原因是 shell 的 completion credits、running-kill tombstone 和 flush 目前按单个运行中 engine 身份实现。直接替换会使多个并行 running kill、多个晚响应和 credit release 的所有权不明确。

下一小阶段需要先扩展以下接口，再完成集成：

1. cluster 接收 kill/flush，并分别跟踪两个 running identity；
2. cluster 输出每个 dispatch/completion 的明确事件；
3. shell 将单个 running identity 改为多 engine running bitmap/identity；
4. completion merge 与 inflight table 保持一次一响应，但允许两个 engine 并行执行；
5. 增加 multi-engine kill、flush、credit saturation 和随机回归。

## 当前结论

多 Engine 调度的核心算法和 response merge 已有 RTL 初版与定向证据，但尚不能宣称完整集成要求已经满足。已经验证的是“CI 映射、两个 engine 并行、oldest-ready 绕行、乱序完成、跨 engine 反压稳定”；尚未验证的是“多 engine 与 shell commit/kill/flush/credits 的端到端闭环”。

## 工具验证与环境限制

2026-08-13 默认 CI 已扩展为 8 个 testbench，Vivado/XSim 2025.2 全部 PASS；原有固定种子 100k-cycle 数据保持为 `accepted=8872, retired=4318, killed=4554, errors=0`。`core/autoisa` 全部生产 SystemVerilog 文件也再次通过 `xvlog -sv`。

已增加 `ci/autoisa/synth_multi_engine.tcl` 供独立综合复现。本次 Vivado batch 在执行 `synth_design` 前被本机 Tcl Store 环境错误中止：缺少 `::tclapp::support::appinit 1.2`，同时报告用户 Tcl Store catalog 损坏。因此目前不能给出可信 LUT/FF 或时序数据；该失败不是 RTL `read_verilog`/`xvlog` 报错，也不应被记录为综合成功。
