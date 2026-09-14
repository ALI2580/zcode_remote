# 性能侧联合非退化签字复测请求

状态：**已完成签核**（2026-09-15 04:5x，性能侧签核「非退化」，登记于其 master-todolist.md LAST VERIFIED）
发起：mobile-portrait-ux 专项（2026-09-15）
请求对象：性能与代码结构优化任务 owner

## 请求事项

对手机竖屏专项集成到主目录后的联合基准做正式复核并签字，确认性能侧
收益未被回退。mobile 侧只请求"复核 + 签字登记"，不要求性能侧改代码。

## 已备数据（mobile 侧集成后自测）

- 证据：`build/mobile-portrait/integration/joint-bench-conv.log`（主目录，
  2026-09-15 04:17，`dart run tooling/bench_conversation_state.dart`）。
- 集成后 3 轮 median：

| rows | 3 轮 median (μs) | 性能侧冻结基准范围 (μs) |
| --- | --- | --- |
| 5000 | 288 / 309 / 311 | 272–310 |
| 20000 | 209 / 225 / 210 | 209–217 |

全部 3 轮落在冻结范围或其自然抖动带内，判定本地非退化。
（冻结基准以性能侧自己清单中的基准表为准，上表为 mobile 侧摘录。）

## 性能侧一键复测步骤

主目录（D:/WorkSpace/ZcodeRemote）空闲时执行，勿与 Flutter/Gradle 并发：

```bash
# 预热轮（1000/5000/20000 全量）
dart run tooling/bench_conversation_state.dart
# 计时轮 ×3（5000/20000）
dart run tooling/bench_conversation_state.dart 5000 20000
dart run tooling/bench_conversation_state.dart 5000 20000
dart run tooling/bench_conversation_state.dart 5000 20000
```

判定：各尺寸 median 与冻结基准范围重叠（±自然抖动）→ 非退化通过；
超出冻结上限 15% 以上 → 回滚会商（集成 patch 见
`build/mobile-portrait/m7-r1/all-integration.patch`，可按文件局部回退）。

## 签字方式

由性能侧在其自有记录/清单中登记结论（mobile 侧不代写性能侧清单）。
登记后请知会 mobile 侧任一会话，或直接在
`references/mobile/integration-request.md` 性能交接条目下补一行结论，
mobile 侧将回填 `references/mobile/mobile-todolist.md` BLOCKERS 与
final-report §7 完成本项闭环。

## 另两项外部依赖（非性能侧，供知会）

TalkBack 深检与单手热区主观评估需真人在装有屏幕阅读器的实体设备执行；
两台可用设备（7555 MuMu 模拟器、16480 vivo 投屏）均无屏幕阅读器服务
（dumpsys 证据：`build/mobile-portrait/device-qa/accessibility-dump*.txt`），
与性能侧无关，保持独立受阻登记。
