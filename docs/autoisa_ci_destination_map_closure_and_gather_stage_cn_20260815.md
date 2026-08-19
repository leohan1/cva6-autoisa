# AutoISA CI Harness 阶段报告：Destination Map 收口与 1–6R Gather 初版

日期：2026-08-15  
工具：Vivado/XSim 2025.2

## 1. 阶段结论

第三优先级 **Host Tagged Destination Map** 已按需求逐项收口。完成该项后，已进入下一阶段并完成可独立验证的 **1–6R Operand Gather RTL 初版**。全量 13 个 testbench 全部通过，原 Q00–Q15 审计保持 16/16 PASS。

当前结论只覆盖独立 Host transport RTL；尚未将 Host adapter、gather、Concurrent Shell 和 `core/cva6.sv` 串成整核通路。

## 2. Host Tagged Destination Map 完成项

| MD 要求 | 实现与证据 | 状态 |
|---|---|---|
| 每个 outstanding 保存 tag、epoch、两个 destination、write policy | 2/4/8-entry tagged table | PASS |
| 至少 4 outstanding | 定向测试 HWM=4 | PASS |
| 1W/2W 原子预约 | scalar、pair-serial、pair-dual policy 检查 | PASS |
| CI↔CI RAW/WAW | CI source/destination 对 busy mask 查询 | PASS |
| CI destination→标准指令 RAW/WAW | 标准指令 source/destination 查询输出 | PASS |
| 标准指令 destination→CI RAW/WAW | 新增 `standard_pending_write_mask_i` | PASS |
| kill/result 精确释放 | `tag+epoch` release | PASS |
| flush 清空 | occupancy/busy mask 原子归零 | PASS |
| stale result 不释放新 epoch | stale lookup/release 与 ID 重用测试 | PASS |
| x0 永不占用 | 非法预约拒绝和 assertion | PASS |
| pair 原子性 | 地址、重复目的、policy 合法性检查 | PASS |

更新后 destination-map 数据：

```text
reserved=7 released=3 conflicts=9 stale_release=2 flush_drop=4 hwm=4
PASS
```

## 3. 1–6R Operand Gather 初版

新增 `core/autoisa/autoisa_ci_operand_gather.sv`，结构为：

```text
Host descriptor
  -> depth-4 age-ordered pending table
  -> active metadata snapshot
  -> two physical RF read addresses per beat
  -> 1/2/3 gather beats
  -> canonical autoisa_ci_req_t
  -> ready/valid output
```

已实现：

- 连续 1–6 个逻辑 source；
- 1–2R/3–4R/5–6R 分别使用 1/2/3 beat；
- 始终只暴露两个物理 RF read address；
- 深度 1/2/4/8 参数约束，默认 pending depth=4；
- descriptor 的 tag、epoch、ci_id、immediate snapshot；
- 4-descriptor burst，HWM=4；
- queued、active、output 三阶段 kill；
- flush 清空 pending、partial operands 和 output；
- canonical request 在下游 backpressure 时保持稳定；
- accepted/emitted/beat/killed/flush counters；
- 非连续或空 source mask 显式判 illegal。

定向测试数据：

```text
accepted=15 emitted=11 gather_beats=20 killed=2 flush_drop=2 hwm=4
PASS
```

其中 20 个 beat 与场景严格相符：1–6R 基本测试 12 beat、四条 2R burst 4 beat、6R queued-kill 保留项 3 beat、active-kill 前部分采集 1 beat。

## 4. 回归

- Vivado `xvlog -> xelab -> xsim`：13/13 PASS。
- Q00–Q15 自动审计：16/16 PASS。
- 单/双 Engine 100k fixed-seed regression：继续 PASS。
- `git diff --check`：无错误；仅存在仓库原有 Windows LF/CRLF 提示。

## 5. 主要文件

- `core/autoisa/autoisa_ci_destination_map.sv`
- `core/autoisa/autoisa_ci_cva6_host_adapter.sv`
- `core/autoisa/autoisa_ci_operand_gather.sv`
- `core/autoisa/tb/tb_autoisa_ci_destination_map.sv`
- `core/autoisa/tb/tb_autoisa_ci_cva6_host_adapter.sv`
- `core/autoisa/tb/tb_autoisa_ci_operand_gather.sv`
- `ci/autoisa/run_ci.py`
- `ci/autoisa/Makefile`
- `ci/autoisa/README.md`
- `Bender.yml`

## 6. 下一步与边界

下一步应建立 Host 端到端 transport test/top：

1. Host adapter descriptor output 接 operand gather；
2. gather canonical request 接 multi-engine Concurrent Shell；
3. Shell commit/kill/result 接回 Host adapter；
4. 增加 pair writeback serializer；
5. 之后再通过 feature flag 接入 `core/cva6.sv`。

今天按用户给定的 67% 截止线停止。未完成项不得表述为 CVA6 整核集成完成。
