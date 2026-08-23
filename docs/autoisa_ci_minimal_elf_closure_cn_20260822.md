# AutoISA 最小 ELF 闭环记录

日期：2026-08-22

最小 D0 ELF 已在 `cv32a65x` Ariane 上完成程序级闭环：从 `0x80000000`
真实取指，经 CV-X-IF 发射和提交到 AutoISA，返回 42 并写回 `x5`。软件分支
校验写回值后，向非缓存地址 `0x10000000` 写入 `tohost=1`。

## 一键复现

```powershell
python ci/autoisa/run_autoisa_elf_smoke.py --vivado D:/apps/HLS/2025.2/Vivado/bin
```

也可以运行：

```powershell
make -C ci/autoisa elf-smoke VIVADO=D:/apps/HLS/2025.2/Vivado/bin
```

流程自动完成工具链检查、ELF/HEX 生成、完整 Ariane 设计编译、展开和 XSim
执行。生成物保存在 Git 忽略的 `ci/autoisa/build/`。

## 通过判据

testbench 同时要求 D0 只发射一次、至少观察到一次提交、只返回一次、返回值为
42，且软件最终写出 `tohost=1`。2026-08-22 的 Vivado/XSim 2025.2 结果：

```text
DATA: cycles=94 autoisa_issue=1 commit=1 result=1 last_result=42 tohost=1
PASS: minimal AutoISA D0 ELF architectural closure
```

## 关键文件

- `tests/autoisa/software/minimal_d0.S`：最小 D0 程序；
- `tests/autoisa/software/minimal_d0.ld`：入口和 `tohost` 地址布局；
- `ci/autoisa/check_riscv_toolchain.py`：ELF、binary、64 位内存 HEX 生成与检查；
- `core/autoisa/tb/tb_autoisa_ci_ariane_elf.sv`：轻量 AXI 内存与闭环判据；
- `ci/autoisa/run_autoisa_elf_smoke.py`：一键门禁入口。

## 已知边界

这是最小程序级正向闭环，不代表全部指令、异常、中断或复杂工作负载覆盖。XSim
仍报告 HPDCache 断言支持限制以及 `issue_read_operands.sv` 的既有数组边界告警；
本次运行没有编译、展开或仿真错误。

## G3 提交门禁

程序级闭环现已由 `ci/autoisa/run_g3_gate.py` 固化为阻断式 G3 门禁。门禁依次
执行 Layout G0、一致的生产源清单检查和最小 ELF 闭环；任一步失败都会停止并
返回非零状态，同时写出 `ci/autoisa/build/g3_gate_summary.json`。

GitHub 工作流 `.github/workflows/autoisa-program-gate.yml` 在 PR、目标开发分支
push 和手动触发时运行，检查名固定为 `AutoISA G3 / Minimal ELF`。它使用带
`autoisa-vivado` 标签的 Windows x64 自托管 runner，并保留 30 天日志和 ELF
证据。仓库分支规则应将这个固定检查名设为 required，才能在 GitHub 服务端禁止
绕过失败结果合并。
