# AutoISA CI Harness 第三优先级阶段报告

日期：2026-08-14  
阶段：Host destination ownership 与 CVA6 identity/control 边界  
结论：第三优先级形成独立 RTL 闭环；尚未宣称 CVA6 整核集成完成。

## 1. 今日完成内容

### 1.1 Tagged destination map

新增 `core/autoisa/autoisa_ci_destination_map.sv`，替代只能表达全局 busy bit 的简单预约方式。每个 live entry 保存：

- canonical `tag + epoch`；
- 两个 destination valid/address；
- scalar、pair-serial 或 pair-dual write policy。

已实现：

- 参数化 2/4/8 entries；
- 1W/2W 原子预约；
- CI 对既有 CI destination 的 RAW/WAW 检查；
- 标准 CVA6 指令对 CI destination 的 RAW/WAW 查询；
- lookup 后恢复 destination metadata；
- 精确 `tag+epoch` release；
- stale epoch 不得释放新 owner；
- kill/result release 与同周期 release/reserve replacement；
- flush 原子清空；
- x0 永不预约；
- pair 地址、write policy 和重复 destination 合法性检查；
- occupancy、HWM、reserve/release/conflict/stale/flush counters。

定向测试达到 4 outstanding，数据为：

```text
reserved=7
released=3
conflicts=7
stale_release=2
flush_drop=4
high_watermark=4
PASS
```

### 1.2 CVA6 Host adapter

新增 `core/autoisa/autoisa_ci_cva6_host_adapter.sv`。根据真实 `cv32a65x` 配置，CVA6 scoreboard 为 8 entries，`trans_id` 宽度是 3 bit；canonical AutoISA tag 当前为 4 bit。因此 adapter 使用零扩展把 `trans_id` 映射为 tag，并为每个 trans_id 保存 2-bit epoch。

adapter 已实现：

- Layout v2 decode 到 canonical Host descriptor；
- issue、descriptor transport 和 destination reserve 原子握手；
- unsupported/illegal/identity-busy 显式拒绝；
- CVA6 `trans_id -> tag+epoch`；
- commit/kill 精确映射到 Concurrent Shell 控制接口；
- kill、result terminal 和 flush 后推进 epoch；
- stale/unknown completion 自动 drain，不产生 Host writeback；
- canonical result 与 destination map 重新结合，输出 tagged Host result transaction；
- scalar 与 pair-serial write policy；
- 标准指令 RAW/WAW hazard 可见性；
- Host result backpressure 向 Shell 传播；
- unknown commit 和 stale result 计数。

定向测试数据：

```text
accepted=5
rejected=1
stale_result_drop=2
unknown_commit=1
PASS
```

测试包含 scalar result、scoreboard ID 重用、epoch 递增、旧结果丢弃、kill、pair destination、flush、unsupported instruction 和 unknown commit。

## 2. 真实 CVA6 接口调查结论

已核对：

- `cv32a65x`：`NrScoreboardEntries=8`，所以 `TRANS_ID_BITS=3`；
- 当前 CV-X-IF 默认 `X_DUALWRITE=0`、`X_RFW_WIDTH=XLEN`；
- 默认架构写回是单结果通路，不能直接承载 AutoISA 2W pair；
- 当前 `cvxif_issue_register_commit_if_driver.sv` 注释明确说明 commit/投机行为仍需进一步确认。

因此今日没有把 2W 结果强行接到现有标量 CV-X-IF result 口。当前正确边界是：

```text
CVA6 trans_id / instruction
  -> v2 decode
  -> tagged destination reservation
  -> canonical descriptor
  -> gather（下一阶段）
  -> Concurrent Shell
  -> tagged result
  -> destination lookup
  -> atomic Host result transaction
  -> 1W scalar 或 2W serializer/sidecar（下一阶段）
```

## 3. 回归结果

Vivado/XSim 2025.2 全量执行 12 个 testbench，12/12 PASS。新增两项为：

1. `autoisa_ci_destination_map`
2. `autoisa_ci_cva6_host_adapter`

此前单/双 Engine、queue、inflight、result、kill/flush/tombstone 和两组 100k random 均继续通过。Q00–Q15 自动审计仍为 16/16 PASS，`git diff --check` 无格式错误。

## 4. 新增/修改文件

- `core/autoisa/autoisa_ci_destination_map.sv`
- `core/autoisa/autoisa_ci_cva6_host_adapter.sv`
- `core/autoisa/autoisa_ci_types_pkg.sv`
- `core/autoisa/tb/tb_autoisa_ci_destination_map.sv`
- `core/autoisa/tb/tb_autoisa_ci_cva6_host_adapter.sv`
- 对应两个 `.f` filelist
- `ci/autoisa/run_ci.py`
- `ci/autoisa/Makefile`
- `ci/autoisa/README.md`
- `Bender.yml`

## 5. 完成度边界

已经验证的是独立 Host transport/control RTL，不是 CVA6 architectural completion。目前尚未：

- 将 adapter 实例化到 `core/cva6.sv` 的真实 issue/commit/flush 网络；
- 实现 1–6R、两物理读口的多拍 gather queue；
- 实现 pair result serializer 与真实 scoreboard/writeback/forwarding 修改；
- 运行 custom CI ELF、MIX00–MIX11 或标准 CVA6 smoke regression；
- 完成 full-core elaboration/synthesis/PPA。

## 6. 下一阶段建议顺序

1. 实现参数化 Host descriptor queue 与 1–6R、1/2/3-beat gather。
2. 连接 adapter descriptor output 到 gather，再连接 canonical request 到 Concurrent Shell。
3. 实现 1W 标量 result adapter 和 2W atomic serializer/sidecar。
4. 在 `core/cva6.sv` 中以 feature flag 接入真实 issue、commit、flush、hazard 和 writeback。
5. 增加执行 custom CI 的 architectural ELF 与 MIX tests。

今日按约定在 token 停止线附近结束，不展开未能在本轮完整验证的 gather RTL。
