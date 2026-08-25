# AutoISA 整核告警收口与 G4 计划

日期：2026-08-25
基线：`autoisa-rtl-capability-v1`
目标配置：CVA6 `cv32a65x`，Vivado/XSim 2025.2

## 1. 整核告警收口结论

`issue_read_operands.sv` 在 2R 配置下曾引用两位 `register_read` 向量的
`register_read[2]`。运行时常量条件不能阻止展开器分析越界选择，因此 stock 和
AutoISA 整核展开各产生一个 `VRFC 10-3705` warning。

修复将 2R/3R 的第三源寄存器读取标志放入 elaboration-time generate 分支：3R
配置读取真实 bit 2，2R 配置使用常量 1，保持原控制语义且不再形成非法选择。

整核 smoke 同时加入告警分类门禁：

- `xvlog`、`xelab`、`xsim` 中任何未知 warning 均失败；
- 只允许 XSim 对 HPDCache/AXI 已知不支持 assertion 的精确消息；
- 只允许 HPDCache 在 0ns 复位初始化时的 `unique case` 消息；同一消息在 0ns
  之后出现会失败；
- 不使用全局 warning suppression，不修改第三方 HPDCache RTL。
- 同一分类器接入 reset smoke 和 G3 程序 ELF，GitHub 必需门禁会阻止告警回归。

验证结果：

| 路径 | xvlog actionable | xelab actionable | xsim actionable | smoke |
|---|---:|---:|---:|---|
| stock CVA6 | 0 | 0 | 0 | PASS，195 ns |
| AutoISA CV-X-IF | 0 | 0 | 0 | PASS，195 ns |
| AutoISA CV-X-IF 3R | 0 | 0 | 0 | PASS，195 ns |

XSim 工具限制仍被透明计数：每条路径 xelab 21 条、xsim 0ns 18 条。它们不应表述为
“原始日志零 warning”，准确结论是“项目可行动告警清零，工具限制已隔离并设门禁”。

## 2. G4 目标与边界

G4 的目标是把 typed semantic catalog 变成单一数据源，确定性生成：

1. 可执行的位向量参考模型；
2. 生产 SystemVerilog semantic engine；
3. 软件可见的 semantic ID/常量；
4. 规范化 catalog、差分结果和生成 manifest；
5. 复用 G3 整核 ELF 通路的程序级语义证据。

G4 不负责应用收益、PPA 或编译器自动识别；这些分别属于 G5/G6 或后续编译器工作。
D8-D11 是 ready/valid、latency、backpressure、fault 协议测试，也不应伪装成 typed
compute semantics。

## 3. 语义契约

现有 `ci_semantic_v1.schema.json` 的 `expression` 是自由字符串，不能作为安全生成输入。
G4 新增 v2 typed CDFG schema，保留 v1 不做静默破坏。v2 最低要求：

- 节点有稳定 ID、明确 opcode、输入边和结果节点；
- 每条边是显式宽度的 bit-vector，并明确 signed/unsigned 解释；
- 默认 RV32 结果按模 `2^32` 截断；乘法、扩展、截断和移位规则无隐式语言语义；
- shift amount 明确掩码规则，算术右移必须显式 signed；
- 图必须无环、全部节点可达、输入/输出数量与 layout 一致；
- opcode 使用白名单；禁止 memory、CSR、PC、控制流、随机数、隐藏状态和未定义行为；
- semantic ID、名称唯一，引用的 layout/backend 必须存在且有能力承载其 R/W 数量。

首批 opcode 建议为 `add/sub/mul_lo/xor/and/or/shl/lshr/ashr/select` 以及显式
`zext/sext/trunc`。除法、饱和、浮点和有状态算子延后，避免第一阶段语义膨胀。

## 4. 实施步骤

### G4.0：契约冻结

- 新增 semantic v2 schema 和 ADR；
- 给出 D0、D1、D7 三个正例与 cycle、越界宽度、非法 opcode、隐藏状态等负例；
- 固定 RV32 位精确语义和版本迁移规则。

验收：schema 正负测试通过，v1/v2 版本不能混读。

### G4.1：解析、验证与规范化 IR

- 实现 `generate_semantics.py` 的 parser/validator；
- 拓扑排序并输出规范化 typed CDFG；
- 稳定排序、SHA-256 和逐产物 manifest；
- 重复生成必须逐字节一致。

验收：非法输入在写任何产物前失败；确定性测试通过。

### G4.2：参考模型

- 从同一 IR 生成 Python 位向量 evaluator；
- 覆盖零、全 1、最高位、正负边界、溢出、最大 shift 等固定向量；
- 加入固定 seed 随机向量。

验收：每个语义至少 10,000 个随机向量，边界向量全部 bit-exact。

### G4.3：SystemVerilog engine 生成

- 先生成组合 D0/D1/D7 engine，并接入现有 descriptor/multi-engine cluster；
- 保持现有 request/tag/epoch/result、commit/kill 和 backpressure 协议不变；
- 生成代码不得手工编辑，源 manifest 必须检查其哈希。

验收：Verible、源 manifest、15 项 Harness 和两个 100k random 回归全部通过。

### G4.4：RTL/reference 差分门禁

- 同一组向量同时驱动生成 RTL 与 Python evaluator；
- 比较每个结果位、status、目标数量和 tag/epoch；
- 做最小 mutation test，证明换 opcode、删截断或改 signedness 会被门禁发现。

验收：D0/D1/D7 零差异；注入错误必定失败。通过后再扩展 D2-D6。

### G4.5：整核程序级语义闭环

- 复用 G3 的 CVA6/CV-X-IF ELF、signature 和 trace 机制；
- 一个程序连续执行 D0、D1、D7，包含 RAW 链、back-to-back、边界值和溢出；
- 软件 signature 分别记录每个 case，错误写回、漏提交或重复发射必须失败。

验收：生成参考值、RTL 结果和软件 signature 三方一致，原 G3 继续通过。

### G4.6：正式门禁与文档

- 新增稳定 required-check：`AutoISA G4 / Semantic Differential`；
- 保存 normalized catalog、manifest、seed、差分摘要、ELF/signature/trace；
- 将生成漂移、非确定性、差分、整核程序错误任一项设为阻断。

## 5. 推荐提交顺序

1. `schema + ADR + negative tests`；
2. `validator + normalized IR + manifest`；
3. `Python reference evaluator`；
4. `generated SV for D0/D1/D7`；
5. `RTL/reference differential gate`；
6. `multi-semantic ELF/signature gate`；
7. `D2-D6 expansion`。

每个提交都应可单独审查和回退，不把 schema、生成器、RTL 接线和 CI 工作流压成一次大改。

## 6. G4 完成判据

只有同时满足以下条件才宣布 G4 通过：

- typed schema/IR 能拒绝所有已定义非法类；
- 生成结果确定且 manifest 可复查；
- D0-D7 不再依赖手写公式作为生产实现；
- Python 与 RTL 的边界/随机差分为零；
- D0/D1/D7 整核 ELF signature 与参考模型一致；
- G0、G3、Verible、整核可行动告警门禁和既有 CI 全部保持绿色；
- 注入至少三类语义错误时门禁能够失败。

达到 G4 只证明“语义生成可信且进入整核程序闭环”，不能据此宣称性能收益或 PPA 达标。
