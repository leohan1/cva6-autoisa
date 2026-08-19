# AutoISA Compute-only CI Harness 第一阶段完成报告

日期：2026-08-17  
工具：Vivado/XSim 2025.2  
目标配置：CVA6 `cv32a65x`

## 1. 第一阶段目标与完成状态

| 任务 | 状态 | 完成结果 |
|---|---|---|
| 固定 ABI/配置版本 | 完成 | `autoisa_ci_types_pkg.sv` 固定为 ABI v1.0，版本值为 `0x0001_0000` |
| 统一 AutoISA 源清单 | 完成 | 新增 `core/autoisa/autoisa_ci_sources.f`，列出 20 个生产 RTL 文件及固定编译顺序 |
| 清理构建基线 | 完成 | `.gitignore` 只忽略 Vivado/XSim 可重建产物；源代码、脚本和测试日志目录结构不被误删 |
| 补齐整核依赖 | 完成 | 初始化仓库锁定版本的 CVFPU、HPDCache 及 CVFPU 递归子模块 |
| 生成 Vivado 兼容文件表 | 完成 | 新增生成器，递归展开 `-F/-f`、环境变量和 include 目录，得到 236 项平坦文件表 |
| stock CVA6 编译/展开/smoke | 完成 | 无外接协处理器的 stock 对照组通过 xvlog、xelab，并运行 195 ns，打印 PASS |
| AutoISA CV-X-IF 整核编译/展开/smoke | 完成 | `AUTOISA_CI_CVXIF` 配置通过 xvlog、xelab，并运行 195 ns，打印 PASS |
| Harness 全量回归 | 完成 | 15/15 测试通过；两个 100k-cycle 随机回归通过 |

## 2. 本阶段新增或修改的关键文件

- `core/autoisa/autoisa_ci_types_pkg.sv`：ABI v1.0 数字版本常量。
- `core/autoisa/autoisa_ci_sources.f`：唯一的 AutoISA 生产 RTL 清单。
- `core/autoisa/tb/tb_autoisa_ci_ariane_smoke.sv`：带真实 `cv32a65x` 参数的 Ariane reset smoke top。
- `ci/autoisa/check_source_manifest.py`：检查清单内文件缺失和重复。
- `ci/autoisa/prepare_vivado_filelist.py`：把 CVA6/HPDCache 嵌套文件表转换成 Vivado 可接受的平坦文件表。
- `ci/autoisa/run_cva6_vivado_smoke.py`：一条命令复现 stock 与 AutoISA 整核 smoke。
- `.gitignore`：隔离 `.Xil`、`xsim.dir`、WDB/PB 和 `ci/autoisa/build` 等生成物。

## 3. 验证结果

### 3.1 整核结果

| 配置 | xvlog | xelab | xsim | 结果 |
|---|---:|---:|---:|---|
| stock CVA6（`CoproType=NONE` 对照） | PASS | PASS | 195 ns | PASS |
| `AUTOISA_CI_CVXIF` | PASS | PASS | 195 ns | PASS |

AutoISA 整核展开日志明确包含：`autoisa_ci_layout_decoder_v2`、`autoisa_ci_engine_descriptor`、请求/在途/结果队列、multi-engine cluster、concurrent shell、`autoisa_ci_cvxif_coprocessor` 和 `ariane`。这证明它们不只是独立 testbench 可编译，而是已经进入真实 Ariane 层级。

### 3.2 Harness 回归

- 功能/协议 testbench：15/15 PASS。
- 单引擎随机回归：100,000 cycles，accepted 8,872，retired 4,318，killed 4,554。
- 多引擎随机回归：100,000 cycles，accepted 8,760，retired 4,268，killed 4,492。
- Host transport：1–6R gather、early commit、pair writeback、kill、flush 全部 PASS。
- 原生 CV-X-IF bridge：issue/register/commit/result 全路径 PASS。

## 4. 可复现命令

在仓库根目录执行：

```powershell
python ci/autoisa/check_source_manifest.py
python ci/autoisa/run_cva6_vivado_smoke.py --vivado D:/apps/HLS/2025.2/Vivado/bin
python ci/autoisa/run_ci.py --vivado D:/apps/HLS/2025.2/Vivado/bin
```

生成的详细日志位于 `ci/autoisa/build/` 和 `ci/autoisa/logs/`。

## 5. 已知问题与边界

1. 未修改的 `cv32a65x` 默认 `COPRO_EXAMPLE` 在 Vivado 2025.2 的 `compressed_instr_decoder` 代码生成阶段触发 `EXCEPTION_ACCESS_VIOLATION`。同一份 RTL已完成静态展开；切换到无协处理器 stock 对照或 AutoISA 路径后均可完整生成 snapshot 和运行。因此它被判定为 XSim/example-coprocessor 组合的工具问题，而不是 AutoISA 整核接线失败。可用 `--exact-stock-example` 独立复现。
2. XSim 对 HPDCache 的部分 SystemVerilog Assertions 不支持并会忽略；这不影响本次 smoke，但后续协议验证应继续依靠专用 Harness assertions，并补充 Verilator/Questa 或正式工具验证。
3. `issue_read_operands.sv:625` 报告一次对 `register_read[2]` 的越界 warning。它同时出现在 stock 和 AutoISA 展开中，属于现有 CVA6 配置/生成分支警告；下一阶段应单独确认并清零。
4. 本阶段 smoke 验证 reset、时钟和完整层级可运行，尚未让 CVA6 执行包含 AutoISA 指令的 ELF。程序级执行是第二阶段的首要任务。

## 6. 下一阶段入口

1. 制作最小裸机 ELF：普通 RISC-V 指令 + 一条或多条 AutoISA 自定义指令。
2. 将程序装入 CVA6 testharness memory，验证真实取指、识别、issue/register/commit/result/writeback。
3. 增加 RVFI/trace 观测点，比较 stock 与 AutoISA 的退休结果。
4. 处理 `register_read[2]` warning，并把整核 smoke 接入自动 CI 门禁。
5. 在程序级闭环后再进行综合、时序和资源评估。
