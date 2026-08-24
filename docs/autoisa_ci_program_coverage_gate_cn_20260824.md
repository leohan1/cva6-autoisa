# AutoISA 扩展程序级门禁（2026-08-24）

## 结论

G3 在保留最小 D0 软件基线的同时，新增并执行
`tests/autoisa/software/program_coverage.S`。扩展 ELF 在真实 `cv32a65x`
Ariane 层级上通过取指、CV-X-IF issue/register/commit/result、GPR 写回、
异常处理、AXI signature 和 `tohost` 完成程序级闭环。

验证命令：

```text
python ci/autoisa/run_g3_gate.py --vivado D:/apps/HLS/2025.2/Vivado/bin
```

## 覆盖矩阵

| 场景 | 程序/门禁证据 |
|---|---|
| 连续多条 AutoISA | 11 条被接受指令；issue、commit、result 必须均严格等于 11 |
| RAW 依赖链 | 连续 `D0 x10 <- x6+x7`、`x11 <- x10+x7`、`x12 <- x11+x10`，结果必须为 3、5、8 |
| 边界操作数 | `0+0=0`、`0xffffffff+1=0`、`0xffffffff+0xffffffff=0xfffffffe` |
| back-to-back / result 背压 | D10 发射后 testbench 强制 `result_ready=0`；payload 至少稳定 4 周期 |
| 非法路径 | L0/D0 使用 `rd=x0`，必须产生 illegal-instruction trap |
| unsupported 路径 | L0/D12 必须被 CV-X-IF 拒绝并产生 illegal-instruction trap |
| engine fault | L0/D11 返回 `ENGINE_FAULT`、禁止写回，目的寄存器 sentinel 必须保持 |
| 更多标量 D/L | L0/D0、D8、D9、D10、D11，以及带立即数的 L7/D7 |
| 软件 signature | 21 个 32-bit 字记录魔数、版本、状态、覆盖位图、陷阱和实际结果 |

`cv32a65x` 的 `X_NUM_RS=2`，因此 3R、4R、6R 和双目的布局不伪装成
标量 CV-X-IF 覆盖，继续由 Direct-CI 扩展通路的 RTL 门禁负责。

## 阻断判据

testbench 使用独立协议记分板，不依赖软件自报成功：

- 每个预期目的寄存器只能 issue 和 result 一次，重复发射/重复结果立即失败；
- transaction ID 必须经历 accepted → committed → result，漏提交或无主结果立即失败；
- OK result 的 status、data、rd、we 必须与参考值一致；
- D11 必须为 fault 且 `we=0`；
- 背压期间完整 result payload 必须稳定；
- 两条失败路径必须恰好产生两次拒绝和两次软件 trap；
- 21 字 signature、`tohost=1` 和协议计数必须同时匹配才允许 PASS。

## 扩展测试发现并修复的问题

首次 result 背压运行发现 CVA6 可能将同一事务的 commit 电平保持两个周期。
原桥接层会把保持电平重复转发给 shell。现在桥接层按 transaction ID 记录
commit 状态，只转发首个合法 commit；独立 CV-X-IF testbench 也加入了 commit
额外保持一周期的回归用例。

测试还观察到通用 CVA6 寄存器文件在“提交写入与普通 store 同周期读取”时可能
读取旧值。该问题不属于 AutoISA 计算或 CV-X-IF writeback 结果错误；扩展程序在
软件可见的稳定点写入 signature，避免把通用核时序问题误归因到本门禁。该 hazard
应作为后续 CVA6 通用旁路任务单独修复和验证。
