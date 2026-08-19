# ADR-0001：冻结 AutoISA Compute-only CI ABI v1.0 与 Layout Schema v2

状态：Accepted  
日期：2026-08-17

## 决策

Canonical ABI 固定为 `autoisa_ci_types_pkg.sv` 中的 v1.0：XLEN=32、最多 6 个源、最多 2 个目的、tag=4、epoch=2、CI ID=8、layout ID=4。Layout 由 `config/layout_profiles_v2.json` 描述，并由 `schemas/layout_profile_v2.schema.json` 约束。

每个 layout 独立声明 32-bit `match/mask`。`layout_id` 仅为 decoder 输出，不占用统一的 instruction 字段。寄存器 namespace、semantic ID、immediate 拼接/符号扩展/scale 和 pair 规则必须全部出现在 descriptor 中。

默认 catalog 只允许 compute-only profile。`AUTOISA_HOST_MEMORY_EXPERIMENTAL` 可在 ABI 中保留，但 enabled catalog 会被 generator 拒绝。

## 原因

手写 decoder 无法可靠证明 layout 不重叠、field 不越界或 6R2W/分散 immediate 可表达，也无法保证 encoder、软件头文件和 RTL 同步。Schema 驱动生成把这些约束变成 G0 自动门禁。

## 结果

生成器输出 RTL decoder、规范化 catalog、冲突报告、Python encoder/decoder、C/assembly helper、bit-budget CSV 和 deterministic manifest。任何 schema/布局冲突都必须报错，不允许静默移动字段。
