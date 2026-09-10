# AutoISA CI 原始目标实现审计（2026-09-10）

## 1. 结论

当前实现已经可靠完成 G0-G4，并完成了 Native G5-A 的可复现证据链；但尚未完成最初定义的全部目标，不能宣布 Harness GO 或 G5/G6 完成。

主要缺口有三项：

1. 真实 Ariane 程序路径目前只接入 `AUTOISA_CVXIF_NATIVE`，Direct-CI Extended 的 4R/6R/2W 仍停留在侧车模块和模块级验证；
2. Native G5-A 的所有语义 workload 均未取得周期收益，P3-P7 也因 Extended 路径未接入而只能 build-only；
3. MIX00-MIX11、标准 CVA6 workload 回归，以及 stock/Harness/Harness+CI 的完整 PPA/功耗/release manifest 尚无闭环证据。

因此，准确状态是：**语义与协议可信，Native 整核子集可执行，性能目标未达成，Extended 整核路径与 G6 未完成。**

## 2. 审计基准

本审计以以下已签入设计文档为原始/演进基准：

- `docs/autoisa_ci_harness_v0_plan.md`：五阶段总体目标；
- `docs/autoisa_ci_harness_current_status_report_cn_20260809.md`：G0-G6、MIX00-MIX11、PPA 与 release 口径；
- `docs/autoisa_ci_baseline_freeze_cn_20260819.md`：冻结边界与后续工作；
- `docs/autoisa_ci_whole_core_warning_closure_and_g4_plan_cn_20260825.md`：G4 与 G5/G6 的责任边界。

审计遵循“模块级 PASS 不等于整核接线、ELF 构建不等于执行、证据完整不等于性能收益”的口径。

## 3. 原始目标逐项核对

| 目标 | 当前证据 | 判定 |
|---|---|---|
| G0 Layout schema/generator/encoder/decoder | 10k round-trip、确定性生成、越界/重叠/能力校验通过 | 完成 |
| G1 单请求功能切片 | Harness、semantic engine、协议错误路径测试通过 | 完成 |
| G2 并发 Harness | request/inflight/result queue、kill/flush、multi-engine、两组 100k 随机通过 | 完成 |
| G3 Host transport 与程序闭环 | Native D0/D1/D7 经真实 Ariane/CV-X-IF 执行；1-6R gather、2W serializer 仅在 sidecar TB 中通过 | 部分完成（当前收窄门禁通过） |
| G4 生成语义闭环 | D0-D7 reference model、4 类 mutation、Layout/Semantic 双向检查、80k differential、D0/D1/D7 reference-backed signature 全通过 | 完成 |
| G5 workload benefit | P0-P8 契约与 12 对 ELF 已冻结；Native P1/P2/P8 latency+throughput 已执行 | 未通过：证据完整但周期均回退 |
| G6 PPA/release | 缺少整核三配置面积/Fmax/功耗与统一 release manifest | 未完成 |
| 1-6R / 0-2W 能力 | ABI、decoder、gather、destination map、pair writeback 已实现并做模块级验证 | 模块级完成，整核 Extended 未完成 |
| 多事务、乱序完成、精确 kill/flush | 并发 shell 与随机回归有覆盖 | 模块级完成 |
| mixed architectural ELF（MIX00-MIX11） | 仓库中只有规划/缺口记录，无实现证据 | 未完成 |
| 标准 CVA6 回归与 benchmark | 通用 Tier2 workflow 有 CoreMark 定义，但当前 AutoISA 证据链未将其作为对照闭环 | 未完成 |
| compute-only / 无隐藏内存副作用 | schema 与 generator 明确拒绝 memory profile/hidden work | 完成 |

## 4. 本轮 Native G5-A 结果

所有用例的软件签名、checksum、CI issue/commit/result 计数均一致，P0 控制组完全相等。结果如下：

| Profile | 模式 | Scalar cycles | AutoISA cycles | Speedup | instret 变化 | AutoISA 诊断 |
|---|---:|---:|---:|---:|---:|---|
| P0 | latency | 333 | 333 | 1.000 | 258 -> 258 | 控制组一致 |
| P1 / D0 | latency | 338 | 462 | 0.732 | 322 -> 322 | issue interval 7.000，inflight HWM 1 |
| P1 / D0 | throughput | 137 | 229 | 0.598 | 162 -> 162 | issue interval 3.312，result latency 5.453，HWM 4 |
| P2 / D1 | latency | 276 | 529 | 0.522 | 386 -> 322 | issue interval 8.031，HWM 1 |
| P2 / D1 | throughput | 206 | 287 | 0.718 | 226 -> 162 | issue interval 4.156，result latency 7.938，HWM 4 |
| P8 / D7 | latency | 406 | 466 | 0.871 | 450 -> 322 | issue interval 7.031，HWM 1 |
| P8 / D7 | throughput | 224 | 229 | 0.978 | 290 -> 162 | issue interval 3.281，result latency 5.453，HWM 4 |

吞吐用例使用四个独立目的寄存器并达到 in-flight HWM 4，证明并发窗口确实被利用。当前瓶颈不是“完全不能并发”，而是 Native CV-X-IF 路径的发射节拍和 issue-to-result 服务延迟。P1 本身没有减少 retired instruction，不适合作为收益代表；P2/P8 虽减少 28.3%/44.1% 指令，仍被接口开销抵消。P8 throughput 已接近 break-even，是下一轮优化的首选标杆。

## 5. 建议的后续顺序

1. **G5-B Native 优化**：以 P8 throughput 为第一标杆，定位并压缩 register/issue/result 握手空泡；目标先达到 P8 `speedup > 1.0`，再验证 P2。P1 保留为“融合但不减指令”的负对照。
2. **G3-E Extended 整核接线**：把 `autoisa_ci_cva6_host_transport` 真正接入 Ariane scoreboard、额外读口/多拍 gather、forwarding 与 pair writeback，使 P3-P7 从 build-only 进入真实 ELF 执行。
3. **G5-C 全 profile 收口**：为 P3-P7 增加 latency/throughput 成对执行，补齐 MIX00-MIX11 和至少一个标准 benchmark A/B；性能判据必须与证据完整性判据分离。
4. **G6**：在功能与收益冻结后，生成 stock/Harness/Harness+CI 三配置的面积、Fmax、功耗和带工具/源/hash 的 release manifest。

在 G5-A 当前结果下，不应把“Native Evidence”设为要求性能改善的强制门禁；它可以作为证据完整性门禁。只有明确加入并满足 speedup 阈值后，才能将其称为 benefit gate。

## 6. 2026-09-10 复验记录

- Python/unit：38/38 PASS；
- source manifest：21 production sources，ABI v1.0，PASS；
- Q00-Q15 evidence audit：16/16 PASS；
- Harness RTL：15/15 testbenches PASS；
- Ariane reset smoke：stock、Native 2R、Native 3R 三配置全部 PASS；
- semantic differential：80,000 vectors PASS（D0-D7 各 10,000）；
- G4 gate：PASS；
- Native G5-A：14/14 executions 与 evidence integrity PASS，`benefit_outcome=REGRESSION`；
- 本机未安装 Verible；SystemVerilog 已通过 Vivado `xvlog/xelab`，GitHub Verible 仍需以远端检查为准。
