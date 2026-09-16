# AutoISA Direct-CI Extended G3E 前置闭环报告

日期：2026-09-14

## 1. 结论

P3-P7 的 Extended 跨层前置闭环已经完成。冻结 workload、Layout encoder/decoder 和生成 Semantic reference 的同一组输入，已经实际穿过：

```text
P3-P7 frozen encoding + generated oracle
  -> Direct-CI Extended decode
  -> destination ownership / RAW-WAW visibility
  -> 1-6R, two-physical-lane operand gather
  -> concurrent shell + generated semantic engine
  -> scalar/pair writeback serializer
  -> architectural GPR model
  -> generated reference comparison
```

本门禁明确记录 `whole_core_integrated=false`。它证明接入 CVA6 前的跨层契约已经闭合，不代表 scoreboard、真实寄存器堆或 commit/writeback 已接入整核。

## 2. 覆盖结果

| Profile | Layout/Semantic | 读/写 | 结果 |
|---|---|---:|---|
| P3 | L2/D2 | 4R1W | 29 |
| P4 | L3/D3 | 2R2W | 29, 13 |
| P5 | L4/D4 | 4R2W | 0xfffffff5, 29 |
| P6 | L5/D5 | 6R1W | 21 |
| P7 | L6/D6 | 6R2W | 68, 28 |

汇总证据：5 个 transaction、2 个 scalar result、3 个 pair result、8 个写回 beat；所有 destination 在写回完成前保持 ownership，标准指令视角的 RAW/WAW hazard 均可见。

执行入口：

```text
python ci/autoisa/run_g3e_preclosure.py
make -C ci/autoisa g3e-preclosure
```

机器可读结果位于 `ci/autoisa/build/g3e_preclosure_summary.json`；reference provenance 位于 `generated/g3e/generation_manifest.json`。

## 3. 已冻结的整核接入边界

下一阶段只能复用现有 `autoisa_ci_cva6_host_transport`，不再另建第二套 Extended transport。CVA6 接线点已核对如下：

| 责任 | CVA6 现有信号/位置 | 尚需实现 |
|---|---|---|
| 原始指令与 identity | `orig_instr_id_issue`、scoreboard `trans_id` | Extended recognition 后与正常 issue ack 原子化 |
| 多拍读寄存器 | `issue_read_operands.sv` 内 GPR read ports | 增加可停顿仲裁；gather 占用时不得破坏普通指令读 |
| 标准指令 RAW/WAW | `issue_read_operands.sv` 的 `stall_raw` 与 scoreboard forwarding | 将 `destination_busy_mask` 纳入 hazard 判定 |
| Extended result | `trans_id_ex_id/wbdata_ex_id/wt_valid_ex_id` | 增加独立 WB source 或安全仲裁，使第一结果回填 scoreboard |
| pair 第二目的 | scoreboard entry 当前只有一个 `rd` | 增加第二 destination ownership、forwarding 和架构写回；不得借用单 `rd` 静默覆盖 |
| flush/kill | `flush_ctrl_id/ex`、scoreboard cancelled/branch resolution | 定义并验证精确 identity kill，不得继续使用测试中的无条件 early commit |
| architectural commit | `commit_instr_id_commit`、`commit_ack_commit_id` | 避免“结果等待 commit、commit 又等待 result”的环形依赖 |

其中 commit/kill 时点是整核接入前必须先定下的协议决策。当前 shell 只有在 completion 与 commit 两者都到达后才输出 result；而 CVA6 scoreboard 通常要先收到 result 才能进入 architectural commit。因此不能简单把 `commit_ack_commit_id` 直接接到 shell commit，否则可能形成死锁。下一阶段应从“指令不再可被分支恢复路径杀死”的事件产生 shell commit，并保留 architectural retirement 作为独立概念。

## 4. 完成标准边界

G3E 整核闭环仍需同时满足：

1. P3-P7 ELF 在真实 Ariane 上执行；
2. 真实 RF 仲裁提供 1-6R 数据并覆盖 forwarding；
3. 标准指令对两个 Extended destination 的 RAW/WAW 正确停顿；
4. branch/exception/flush 可精确 kill；
5. 1W/2W 最终 GPR 状态与生成 reference 一致；
6. stock、Native 和 Extended feature-off/on 构建均无回归。

达到上述六项前，只能称为 G3E pre-closure PASS，不能称为 Extended whole-core PASS。

## 5. 本地复验记录

2026-09-14 的本地稳定性复验结果：

- G3E 专项门禁：PASS；
- Python contract/oracle 测试：40/40 PASS；
- RTL 统一回归：16/16 PASS，其中包含 G3E pre-closure 与真实 CV-X-IF scalar bridge；
- source manifest：21 个 production source、ABI v1.0 PASS；
- Q00-Q15：16/16 PASS；
- `git diff --check`：无 whitespace error（仅 Windows LF/CRLF 转换提示）。

以上结果全部来自本地工作树，未提交或上传 GitHub。
