# AutoISA CI Harness：CVA6 集成阶段报告

日期：2026-08-16  
工具：Vivado/XSim 2025.2

## 1. 本阶段结论

本阶段完成了两条互补链路：

1. **完整 Direct-CI sidecar transport**：Host adapter、1–6R operand gather、Concurrent Shell、tagged destination map 和 scalar/pair writeback 已形成端到端 RTL 闭环。
2. **真实 CVA6 CV-X-IF 标量接线**：新增使用 CVA6 实际 `cvxif_req_t/cvxif_resp_t` 协议的 coprocessor，并在 `corev_apu/src/ariane.sv` 中加入 `AUTOISA_CI_CVXIF` 编译开关。

因此，目前可以准确表述为：**标量 2R/可选 3R 子集已经到达真实 CV-X-IF 源码集成边界；完整 1–6R 与 2W pair 已完成独立端到端 RTL，但尚未完成 CVA6 整核内部 RF/scoreboard/writeback 结构改造。**

## 2. Direct-CI 端到端数据通路

```text
CVA6 instruction + trans_id
  -> v2 layout decode
  -> tagged destination reservation
  -> queued 1–6R operand gather (2 physical reads/beat)
  -> early-commit replay
  -> multi-engine Concurrent Shell
  -> tagged result + destination lookup
  -> scalar/pair writeback serializer
  -> CVA6-style scalar WB beat
```

新增 `autoisa_ci_cva6_host_transport.sv` 负责上述模块的连接，并解决了一个真实时序问题：CVA6 commit 可能在多拍 gather 完成前到达。transport 现在按 `trans_id + epoch` 保存早到 commit，在 shell request 原子分配时重放。

新增 `autoisa_ci_pair_writeback_serializer.sv` 将 2W pair 结果转换为两个标量写回 beat。第一拍完成后，Host result 与 destination ownership 继续保持；只有第二拍真正握手后才释放目的寄存器，避免中途暴露错误的空闲状态。

## 3. 真实 CV-X-IF 集成

新增 `autoisa_ci_cvxif_coprocessor.sv`，直接使用 CVA6 的 issue request/response、register payload、commit transaction 和 result ready/valid/ID/rd/data/we。

在 `corev_apu/src/ariane.sv` 中定义 `AUTOISA_CI_CVXIF` 时，原 example coprocessor会替换为 AutoISA coprocessor；默认不定义时，原 CVA6 行为不变。

该路径只接受当前 CV-X-IF 能正确承载的 native scalar 指令：

- source 数量不超过 `CVA6Cfg.X_NUM_RS`；
- 只有一个 destination；
- CI ID 被已实现 engine descriptor 支持；
- operand valid、ID 空闲和 shell ready 条件同时成立。

pair 和 4–6R 指令会被明确拒绝，不会错误进入标量 CV-X-IF 写回口。

## 4. Vivado 验证结果

统一回归结果：

```text
15/15 testbenches PASS
Q00–Q15: 16/16 PASS
git diff --check: PASS（只有 LF/CRLF 提示）
```

新增端到端测试覆盖：

- commit 早于 gather/shell allocation；
- L0 2R1W 标量计算；
- L3 2R2W 两拍串行写回与中间 backpressure；
- L5 6R1W，三次双端口 RF gather；
- gather 阶段 kill，不产生 shell allocation/writeback；
- flush 清空 destination、gather 和 commit pending；
- 真实 CV-X-IF issue/register/commit/result 数据往返；
- unsupported 与 pair 指令在标量 CV-X-IF 路径上明确拒绝。

端到端 transport 定向数据：

```text
shell accepted = 3
shell retired  = 3
Host results   = 3
WB beats       = 4  (1 scalar + 2 pair + 1 six-source scalar)
```

原有两组固定种子 100k-cycle regression 继续通过：

```text
single-engine: accepted=8872 retired=4318 killed=4554 orphan=1290
multi-engine : accepted=8760 retired=4268 killed=4492 orphan=1153
```

## 5. 本阶段主要文件

- `core/autoisa/autoisa_ci_cva6_host_transport.sv`
- `core/autoisa/autoisa_ci_pair_writeback_serializer.sv`
- `core/autoisa/autoisa_ci_cvxif_coprocessor.sv`
- `core/autoisa/tb/tb_autoisa_ci_cva6_host_transport.sv`
- `core/autoisa/tb/tb_autoisa_ci_cvxif_coprocessor.sv`
- `corev_apu/src/ariane.sv`
- `Bender.yml`
- `core/Flist.cva6`
- `Flist.ariane`
- `ci/autoisa/run_ci.py`
- `ci/autoisa/Makefile`

## 6. 尚未完成及原因

### 6.1 整核 elaboration 尚未完成

尝试用 Vivado 编译 `core/Flist.cva6` 时，在进入整核 RTL 验证前遇到仓库依赖问题：`core/cache_subsystem/hpdcache` 子模块未初始化，且该通用 filelist 使用了 XSim 不接受的 `-F` 嵌套 filelist 选项。AutoISA 新模块自身及真实 CV-X-IF 类型桥均已通过 `xvlog -> xelab -> xsim`，但不能把这等同于完整 `ariane` top elaboration。

### 6.2 完整 Direct-CI 仍需 CVA6 内部结构改造

1. `issue_read_operands.sv` 当前每条指令只直接提供 2R，定义 `AUTOISA_CI_3R` 时为 3R；还没有供 sidecar 多拍使用的 RF 仲裁端口。
2. CV-X-IF `X_WB` 是单标量写回，scoreboard entry 也只保存一个 `rd`；pair 的第二个 destination 尚无整核 reservation/forwarding/commit 支持。
3. 当前 `cvxif_issue_register_commit_if_driver.sv` 在 issue 握手时立即产生 commit，并固定 `commit_kill=0`；这不是完整的推测执行 commit/kill 语义。
4. Direct-CI destination busy mask 尚未接入标准指令的整核 RAW/WAW stall 网络。

## 7. 下一步优先级

1. 初始化 HPDCache 等依赖，生成 Vivado 兼容的 cv32a65x source list，完成带 `AUTOISA_CI_CVXIF` 的 `ariane` top elaboration。
2. 编写最小 custom-CI ELF，在 CVA6 testharness 中验证 fetch/decode/issue/register/result/architectural GPR writeback。
3. 将真实 commit/kill 从 commit stage 接到 Direct-CI transport，而不是沿用 issue-time commit。
4. 为 gather 增加 RF read arbitration，并把 destination busy mask 接入标准 scoreboard hazard。
5. 扩展 scoreboard/writeback/forwarding，使 pair 第二目的寄存器获得完整架构支持。

## 8. 完成度边界

本阶段已经完成“真实 CV-X-IF 标量源码接线 + 完整 sidecar RTL 闭环”，但尚不能宣称“完整 AutoISA 1–6R/2W 已在 CVA6 上运行程序”。后者必须以整核 elaboration、custom ELF 和 architectural state 检查为完成证据。
