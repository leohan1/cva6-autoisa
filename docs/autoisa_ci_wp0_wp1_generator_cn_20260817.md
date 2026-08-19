# AutoISA CI Harness WP0/WP1 Generator 阶段报告

日期：2026-08-17  
范围：WP0 ABI/Schema 冻结、WP1 Layout V2 自动生成、G0 验收

## 1. 本阶段结论

WP0/WP1 已形成可执行闭环。现在不再手工维护 Layout V2 decoder，而是以一个 JSON catalog 作为布局编码的单一数据源；生成器先拒绝非法配置，再自动输出 RTL、软件编码器、C/汇编常量、规范化 JSON、冲突报告、位预算和确定性哈希。普通 AutoISA CI 默认先重新生成 Layout V2，因此 catalog 与集成 RTL 不一致时不能被静默带入回归。

G0 验收结果为通过：8 个启用布局、6R2W、分散立即数、正负校验、确定性生成、10,000 条随机 encoder/decoder round-trip 以及 Vivado decoder smoke 均通过。生成 RTL随后通过 15/15 Harness 回归，并通过 236 个源文件组成的 CVA6/Ariane 整核编译、展开与复位 smoke。

## 2. 设计方法

### 2.1 单一数据源

布局统一写在 `config/layout_profiles_v2.json`。每个 layout 明确声明：

- `id`、名称、启用状态和 compute-only 属性；
- 32-bit `match/mask`；
- 1–6 个 source、1–2 个 destination；
- GPR32、GPR16、RVC8 或 derived-pair 命名空间；
- 每个逻辑字段到指令位的 slice 映射；
- fixed/encoded semantic ID；
- 可选立即数的位宽、符号、缩放和分散 slices；
- pair destination 的非零、偶数和上界约束；
- backend 路由。

这使“布局是什么”与“如何生成 RTL/软件工具”分离。修改布局时只改 catalog，再由同一生成器同步所有消费者。

### 2.2 先验证、后生成

`scripts/generate_layout_decoder.py` 在写产物前检查：

1. schema 版本、XLEN、layout ID/名称唯一性；
2. match 不能在 mask 之外置位；
3. 默认启用项必须是 compute-only；
4. source/destination 数量与声明一致；
5. namespace 位宽、slice 范围和完整覆盖正确；
6. payload 字段之间、payload 与识别位之间不能重叠；
7. GPR destination 必须拒绝 x0；
8. derived pair 必须具有有界约束；
9. 任意两个启用 layout 的 match/mask 不得相交。

因此 out-of-range、width mismatch、字段重叠、layout 重叠和误启用 memory profile 都会在 RTL 生成前失败。

### 2.3 确定性生成

catalog 先按稳定顺序规范化，再计算 SHA-256。每个生成文件也写入独立哈希，保存到 `generation_manifest.json`。同一输入重复生成必须得到逐字节相同的产物；测试还确认仓库中集成的 `autoisa_ci_layout_decoder_v2.sv` 与生成副本完全一致。

## 3. 数据流

```text
layout_profiles_v2.json
          |
          v
  结构/语义/冲突检查 ------非法------> 构建失败并给出字段级原因
          |
        合法
          v
  规范化 + SHA-256
          |
          +--> autoisa_ci_layout_decoder.sv --> core/autoisa/...decoder_v2.sv
          +--> autoisa_ci_encode.py
          +--> autoisa_ci_encoding.h / .S
          +--> layout_profiles.normalized.json
          +--> layout_overlap_report.json
          +--> layout_bit_budget.csv
          +--> generation_manifest.json
```

运行时，生成 decoder 对 `instr_i` 做并行 match/mask 识别，命中后按 catalog slices 提取寄存器编号、semantic ID 和立即数，填入 canonical host descriptor；derived destination、符号扩展、pair 约束和 x0 检查也由生成逻辑完成。后续 operand gather、engine dispatch、commit/kill 和 writeback 仍复用现有 Harness 数据通路。

## 4. 当前布局与位预算

| ID | Layout | 识别位 | 源位 | 目的位 | 语义位 | 立即数位 | 自由位 |
|---:|---|---:|---:|---:|---:|---:|---:|
| 0 | L_2R1W_GPR32 | 10 | 10 | 5 | 7 | 0 | 0 |
| 1 | L_3R1W_GPR32 | 10 | 15 | 5 | 2 | 0 | 0 |
| 2 | L_4R1W_GPR8 | 10 | 12 | 3 | 5 | 0 | 2 |
| 3 | L_2R2W_PAIR | 10 | 10 | 5 | 7 | 0 | 0 |
| 4 | L_4R2W_GPR8 | 12 | 12 | 6 | 0 | 0 | 2 |
| 5 | L_6R1W_GPR8 | 11 | 18 | 3 | 0 | 0 | 0 |
| 6 | L_6R2W_GPR8 | 8 | 18 | 6 | 0 | 0 | 0 |
| 7 | L_2R1W_IMM | 7 | 10 | 5 | 0 | 10 | 0 |

L6 证明 32-bit 指令内可承载 6R2W：7-bit custom opcode 加 1 个保留识别位，剩余 24 位正好容纳六个 RVC8 source 和两个 RVC8 destination。L7 使用 custom-0，并将 signed imm10 分散为 `instr[31:25]` 与 `instr[14:12]`，覆盖 WP1 对 scattered immediate 的要求。

## 5. 文件构成

### 输入与契约

- `config/layout_profiles_v2.json`：Layout V2 唯一输入 catalog。
- `schemas/layout_profile_v2.schema.json`：布局结构 schema。
- `schemas/ci_semantic_v1.schema.json`：后续语义描述契约。
- `docs/adr/0001-autoisa-ci-abi-layout-v2.md`：ABI v1.0 / Layout schema v2 决策记录。

### 生成器与产物

- `scripts/generate_layout_decoder.py`：验证与生成主程序。
- `generated/layout/`：规范化 catalog、RTL、Python encoder/decoder、C header、assembly constants、冲突报告、位预算和 manifest。
- `core/autoisa/autoisa_ci_layout_decoder_v2.sv`：写入生产源目录的生成 decoder；文件头标记 DO NOT EDIT。

### 测试与 CI

- `tests/autoisa/layout/test_layout_generator.py`：10 项 G0 测试和 10,000 条随机 round-trip。
- `ci/autoisa/run_wp0_wp1.py`：WP0/WP1 独立验收入口。
- `ci/autoisa/run_ci.py`：常规全回归入口，默认先生成 Layout V2。
- `ci/autoisa/Makefile`：提供 `wp0-wp1` 目标。

## 6. 验证数据

| 验证项 | 结果 |
|---|---|
| catalog 正例与负例 | PASS，10/10 单元测试 |
| layout overlap | PASS，无重叠 |
| 6R2W | PASS |
| scattered signed imm10 | PASS |
| 确定性生成 | PASS |
| Python encoder/decoder round-trip | PASS，10,000 条 |
| Vivado Layout/Harness smoke | PASS |
| Harness 全回归 | PASS，15/15；含两组 100k 随机测试 |
| source manifest / Q00–Q15 coverage | PASS |
| CVA6/Ariane 整核 smoke | PASS，236 个源文件，195 ns 完成 |

## 7. 已完成边界与未完成项

已完成的是 WP0/WP1：布局 ABI/schema、合法性检查、decoder/encoder 等产物生成、G0 测试和 CI 接入。`ci_semantic_v1.schema.json` 只冻结了语义输入的基本格式；把 semantic JSON 自动生成为执行引擎、参考模型或编译器内建函数属于后续 WP8，不在本阶段完成范围内。

推荐后续顺序：

1. 将 generator/G0 作为提交门禁，确保生成文件变更可审查；
2. 增加编译软件侧的真实 `.insn`/ELF smoke，而不只验证 Python 编码；
3. 开展 WP8 semantic generator 与 RTL/reference differential test；
4. 再进入 benefit A/B、PPA 和 workload 评估，避免用 dummy semantics 代替应用收益证据。

## 8. 常用命令

```powershell
python scripts/generate_layout_decoder.py
python ci/autoisa/run_wp0_wp1.py --vivado D:/apps/HLS/2025.2/Vivado/bin
python ci/autoisa/run_ci.py --vivado D:/apps/HLS/2025.2/Vivado/bin
```

结论：WP0/WP1 已从“手写 decoder 原型”升级为“schema/catalog 驱动、可拒绝错误、可复现、软硬件共同生成并纳入 Vivado/CVA6 回归”的基础设施，可以作为后续语义生成和真实 workload 验证的稳定入口。
