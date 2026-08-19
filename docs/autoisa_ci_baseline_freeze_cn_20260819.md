# AutoISA CI Harness 基线冻结记录

日期：2026-08-19  
目标配置：CVA6 `cv32a65x`（RV32）  
验证工具：Vivado/XSim 2025.2

## 1. 冻结结论

当前代码可以冻结为 AutoISA compute-only Direct-CI 的程序级集成前基线。
Layout V2 生成、Harness 并发控制、Host transport、原生标量 CV-X-IF bridge
以及 Ariane 整核复位 smoke 已形成可复现闭环。

本基线不宣称已经完成 AutoISA ELF 的取指、退休和架构写回验证。该项是下一阶段
Gate G3 的首要验收条件。

## 2. 当日重新验证结果

| 验证项 | 结果 |
|---|---|
| Layout generator 单元测试 | PASS，10/10 |
| Encoder/decoder 随机 round-trip | PASS，10,000 条 |
| 生产源 manifest | PASS，20 个 RTL 文件，ABI v1.0 |
| Q00-Q15 证据审计 | PASS，16/16 |
| Harness Vivado/XSim 回归 | PASS，15/15 |
| 单引擎随机回归 | PASS，100,000 cycles；accepted 8,872；retired 4,318；killed 4,554 |
| 多引擎随机回归 | PASS，100,000 cycles；accepted 8,760；retired 4,268；killed 4,492 |
| stock Ariane 整核 smoke | PASS，236 项源文件，运行 195 ns |
| AutoISA Ariane 整核 smoke | PASS，236 项源文件，运行 195 ns |

## 3. 冻结范围

- ABI v1.0、Layout V2 catalog/schema、确定性生成器及软硬件生成产物；
- D0-D11 dummy/protocol engine、request/inflight/result queue；
- 单/多 engine concurrent shell、completion credit、kill/flush/backpressure；
- tagged destination map、1-6R operand gather、pair writeback serializer；
- CVA6 Host adapter/transport 和标量原生 CV-X-IF coprocessor；
- 15 项 testbench、两组固定 seed 100k-cycle 回归；
- stock 与 `AUTOISA_CI_CVXIF` Ariane 源码集成和复位 smoke。

## 4. 复现命令

```powershell
python -m unittest tests.autoisa.layout.test_layout_generator -v
python ci/autoisa/check_source_manifest.py
python ci/autoisa/check_q_coverage.py
python ci/autoisa/run_ci.py --vivado D:/apps/HLS/2025.2/Vivado/bin
python ci/autoisa/run_cva6_vivado_smoke.py --vivado D:/apps/HLS/2025.2/Vivado/bin
```

## 5. 已知边界

1. 尚未生成并运行包含 AutoISA 指令的 RV32 bare-metal ELF。
2. 当前 Windows 环境的 `PATH` 中未发现 RISC-V bare-metal GCC 工具链。
3. `issue_read_operands.sv` 的三操作数条件分支仍会在特定配置下产生
   `register_read[2]` 越界 warning；stock 与 AutoISA 路径均可见，应在程序级
   集成阶段单独清零。
4. XSim 会忽略 HPDCache 的部分不受支持 assertion；Harness 专用 assertion
   和随机回归仍是当前协议验证主体。
5. WP8 semantic generator、真实 workload A/B、综合 PPA 和 release manifest
   尚未完成。

## 6. 下一验收门

下一门为最小 D0 AutoISA ELF：复用 CVA6 现有 custom/CV-X-IF 软件测试框架，
验证取指、识别、issue/register、commit、result、GPR 写回和 `tohost` PASS，
同时保留 stock 对照与 RVFI/trace 证据。
