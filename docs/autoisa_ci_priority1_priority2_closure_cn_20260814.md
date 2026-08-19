# AutoISA Compute-only CI Harness 优先级 1/2 阶段收口报告

日期：2026-08-14  
验证工具：Vivado/XSim 2025.2  
范围：独立 Harness RTL 与 Concurrent Shell；不包含 CVA6 整核接线、软件 ELF 和 FPGA PPA 收口。

## 1. 本阶段结论

计划中的前两个优先级已经完成：

1. **优先级 1：多 Engine Cluster 接入 Concurrent Shell**——完成。
2. **优先级 2：Q00–Q15 验收项形成可审计闭环**——完成（Standalone/Shell RTL 级）。

本次全量回归共 10 个 testbench，全部通过；Q00–Q15 自动证据审计为 16/16 通过。单 Engine 与双 Engine 均完成固定种子 100,000 周期随机仿真，错误数为 0，接收、退休和杀死计数满足守恒关系。

## 2. 优先级 1：多 Engine 并发通路

### 2.1 RTL 结构

`autoisa_ci_concurrent_shell` 新增可选参数 `MULTI_ENGINE`。默认值为 0，保留原有单 Engine 行为；设为 1 时接入 `autoisa_ci_multi_engine_cluster`。

完整数据通路为：

```text
CI request
  -> request queue
  -> inflight table / completion-credit reservation
  -> multi-engine pending scheduler
  -> engine 0 或 engine 1
  -> completion arbiter
  -> inflight identity/tombstone check
  -> result queue
  -> commit/result output
```

Cluster 使用 Engine descriptor 判断 CI 指令是否可由某个 Engine 执行，再按“最老且当前可执行”原则调度。因此，队首如果等待忙碌的 Engine，后面的请求仍可发给空闲 Engine，避免不必要的队头阻塞。

### 2.2 Kill、Flush 与 ABA 防护

- **Pending kill**：请求尚在 Cluster pending 表时直接删除，并立即释放预留 completion credit。
- **Running kill**：Engine 已开始执行时，inflight 表保留 tombstone；迟到 completion 被识别为 orphan，不会误写到复用后的相同 tag。
- **Flush**：清空 request、pending、inflight、result 和 credit 状态；已经运行的 Engine 不被强制复位，其迟到结果会被安全排空并计为 orphan。
- 请求身份采用 `tag + epoch`，避免 tag 回绕后的 ABA/陈旧响应污染。

### 2.3 定向测试数据

双 Engine Cluster 独立测试：

| 指标 | 结果 |
|---|---:|
| accepted | 5 |
| engine0 dispatch | 2 |
| engine1 dispatch | 3 |
| completed | 5 |
| parallel busy cycles | 11 |
| pending HWM | 2 |
| completion order | 3, 1, 2 |

双 Engine Concurrent Shell 端到端测试：

| 指标 | 结果 |
|---|---:|
| accepted / dispatched | 8 / 8 |
| engine started / completed | 6 / 6 |
| retired / killed | 4 / 4 |
| orphan completion | 2 |
| pending kill / flush drop | 1 / 1 |
| inflight / credit HWM | 4 / 4 |

测试覆盖了 oldest-ready bypass、乱序完成、commit、pending kill、running kill、tombstone、flush 和迟到响应排空。

## 3. 优先级 2：Q00–Q15 验收闭环

验收矩阵位于 `ci/autoisa/q00_q15_coverage.json`，自动检查器位于 `ci/autoisa/check_q_coverage.py`。检查器要求：

- Q00–Q15 必须恰好各出现一次且状态为 covered；
- 每项必须给出检查目标和 testbench 证据；
- 所有引用的 XSim 日志必须含 `PASS:`；
- 单/双 Engine 随机测试均为 100,000 周期、0 error；
- `accepted = retired + killed`。

| 验收项 | 主要验证内容 | 证据 |
|---|---|---|
| Q00 | DEPTH=1 基本收发 | request_queue |
| Q01 | 填满并额外施加 DEPTH+2 请求 | request_queue |
| Q02 | oldest-ready、队头旁路 | multi_engine_cluster/shell |
| Q03 | 可变延迟、乱序完成 | engine_protocols/multi_engine_shell |
| Q04 | 随机结果背压 | 两组 random_100k |
| Q05 | completion credit 防止结果路径超额占用 | concurrent_shell |
| Q06 | 满边界替换、旁路与稳定背压 | request/result queue |
| Q07 | DEPTH=4 指针回绕 128 次 | request_queue |
| Q08 | Engine dispatch 前 kill | concurrent/multi shell |
| Q09 | Engine running 时 kill 与迟到响应 | concurrent/multi shell |
| Q10 | completion 后、commit 前 kill | inflight_table |
| Q11 | 各阶段 flush | queue/result/concurrent/multi shell |
| Q12 | tag 回绕、epoch、stale completion | 两组 random_100k |
| Q13 | 双字结果原子性与背压 | result_queue |
| Q14 | 重复 live identity 拒绝 | inflight_table/concurrent_shell |
| Q15 | 单/双 Engine 100k 随机回归 | 两组 random_100k |

## 4. 全量回归结果

以下 10 项均由 Vivado `xvlog -> xelab -> xsim` 实际执行并通过：

1. `autoisa_ci_harness_v0`
2. `autoisa_ci_request_queue`
3. `autoisa_ci_inflight_table`
4. `autoisa_ci_result_queue`
5. `autoisa_ci_engine_protocols`
6. `autoisa_ci_concurrent_shell`
7. `autoisa_ci_random_100k`
8. `autoisa_ci_multi_engine_cluster`
9. `autoisa_ci_multi_engine_shell`
10. `autoisa_ci_random_100k_multi`

随机回归汇总：

| 模式 | accepted | retired | killed | flush | orphan | result HWM | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| 单 Engine | 8872 | 4318 | 4554 | 4 | 1290 | 4 | 0 |
| 双 Engine | 8760 | 4268 | 4492 | 4 | 1153 | 3 | 0 |

两组均满足：`accepted = retired + killed`。

## 5. 主要新增或修改文件

### RTL

- `core/autoisa/autoisa_ci_concurrent_shell.sv`
- `core/autoisa/autoisa_ci_multi_engine_cluster.sv`
- `core/autoisa/autoisa_ci_engine_descriptor.sv`

### Testbench 与 filelist

- `core/autoisa/tb/tb_autoisa_ci_multi_engine_shell.sv`
- `core/autoisa/tb/autoisa_ci_multi_engine_shell.f`
- `core/autoisa/tb/tb_autoisa_ci_multi_engine_cluster.sv`
- `core/autoisa/tb/tb_autoisa_ci_random_100k.sv`
- `core/autoisa/tb/tb_autoisa_ci_request_queue.sv`

### CI 与验收证据

- `ci/autoisa/run_ci.py`
- `ci/autoisa/q00_q15_coverage.json`
- `ci/autoisa/check_q_coverage.py`
- `ci/autoisa/Makefile`
- `ci/autoisa/README.md`

## 6. 尚未完成与下一优先级

当前“Q00–Q15 完成”仅指 Compute-only Harness 的独立 RTL/Concurrent Shell 范围，不能等同于 CVA6 整核集成完成。后续仍需：

1. 明确 Host destination/写回映射，并与真实 CVA6 scoreboard、commit/kill 信号接线。
2. 实现或收口 gather/operand 收集路径及其背压规则。
3. 在 CVA6 整核仿真中运行真实自定义指令 ELF，验证架构态结果。
4. 完成 Vivado synthesis/elaboration 与 PPA 报告；此前 synthesis 流程曾受本机 Vivado Tcl Store 损坏阻塞，需要先修复工具环境。
5. 固化接口 schema/生成流程，并加入持续集成环境。

因此，当前结果可以作为 **Harness RTL 初版的并发和异常控制闭环**；下一阶段应进入 **CVA6 Host 接口与整核执行闭环**。
