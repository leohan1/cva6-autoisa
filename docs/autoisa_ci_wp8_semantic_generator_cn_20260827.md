# WP8 Semantic Generator（2026-08-27）

## 目标与边界

WP8 将 D0-D7 的纯计算语义从手写 RTL 中抽离为单一 JSON 契约，并从同一份契约生成 RTL engine 与 Python reference model。当前版本只允许无状态、compute-only、XLEN=32 的有向无环数据流；访存、CSR、副作用和隐式状态均不进入本阶段。

## 已实现闭环

1. `config/semantics_v2.json` 描述 D0-D7 的操作数、结果数、立即数使用、延迟和有类型操作 DAG。
2. `scripts/generate_semantics.py` 严格拒绝重复 ID、未知操作、越界操作数、前向/循环引用、未使用节点和非法立即数引用。
3. 生成器确定性地产出规范化 JSON、内容哈希清单、组合 RTL engine 和 Python reference model。
4. 原 `autoisa_ci_dummy_engine` 保留 ready/valid、延迟和 D8-D11 协议压力行为，D0-D7 的结果与延迟改由生成 engine 提供。
5. `run_semantic_diff.py` 使用固定随机种子，对每个语义执行 10,000 个向量；总计 80,000 个，包含零值、全 1、正负边界、互补值和随机溢出。
6. GitHub 独立门禁名称为 `AutoISA G4 / Semantic Differential`，失败时保留生成清单、差分摘要和 Vivado 日志。

## 本地验收

```text
python -m unittest -v tests.autoisa.test_semantic_generator
python ci/autoisa/run_semantic_diff.py --vivado D:/apps/HLS/2025.2/Vivado/bin
```

验收要求：生成器单元测试全部通过，Vivado transcript 出现 `PASS: AutoISA semantic RTL/reference differential (80000 vectors)`，且摘要状态为 `passed`。

## 后续阶段建议

1. 将 `AutoISA G4 / Semantic Differential` 加入分支保护，观察 3-5 次稳定运行后再设为 required。
2. 为生成器加入 signed/unsigned compare、select、显式扩展/截断节点，避免未来依赖 SystemVerilog 隐式类型规则。
3. 把 semantic ID 与 Layout v2 catalog 建立交叉一致性检查，阻止“可解码但无语义”或“有语义但不可达”。
4. 将 reference model 接到程序级 signature oracle，使 G3 同时验证 ELF 可见结果与生成语义。
5. 在完成 D0-D7 稳定期后，再扩展标量 CV-X-IF 可表达的 D/L 组合；访存语义另立契约和隔离门禁。
