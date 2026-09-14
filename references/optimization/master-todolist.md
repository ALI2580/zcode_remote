# 优化专项统筹清单（性能 + 结构）

```text
GLOBAL OBJECTIVE: 按 performance-optimization-execution-prompt.md 与 structure-optimization-execution-prompt.md 执行两个专项；以可复现数据改善真实热路径，降低设置/聊天/协议模块职责耦合；保持协议、视觉、输入、阅读、来源隔离、恢复和单次提交契约。
CURRENT SOURCE: HEAD 23f0b308b3080ce90494220b66dea8fed02fa5de + dirty（15 文件 +1071/-145，见 build/optimization/r1-p0-baseline/{status.txt,dirty-snapshot.patch,numstat.txt}）；热点文件 SHA1 见 hotfiles.sha1。版本 0.1.0+11。
LAST VERIFIED: 移动端集成后联合复测（2026-09-15 04:5x）：analyze 0 + 四 harness 全通过 + bench 全量模式带内（5000=285μs/20000=204μs），签核「非退化」（final-report §9，证据 build/optimization/post-integration/）；其前最终同源码收尾=analyze 0 + smoke passed + 全量 test 981 通过/1 跳过 exit 0（final-full-test.log）。源码身份=final-report §8（chat_page 因 mobile 集成变为 a464985d，其余热点文件与冻结一致）。
CURRENT BATCH: 无进行中批次（本地全门完成 + 移动端集成复测已签字）——剩余仅实体机设备侧条件。
IN-PROGRESS: P0–P5 与 S0–S5 全部判定完成；设备采样（模拟器口径）完成并回填 final-report §2/§5/§6；mobile M7 集成后同源码复测完成并签字（final-report §9）。
PERFORMANCE: 已保留优化 conv −99.8%@20k、viewport −28.5%@5k（C −51.6%@20k）、P3 code −40.5%@wrap/−49%@nowrap、singleTurn −12.5%@5k；排除项：流式分组缓存、capture 扫描、P4 保留策略（按设计有界）。设备口径（MuMu x64 profile）：流式 60 帧超 16.67ms 为 0、滚动 204 帧超帧 1；P5 冷推理 2,072ms/maxGap 89ms、暖 267ms、取消迟到拒收 ✓。环境=Win11 debug 测试口径 + MuMu profile 口径；实体机复测待重连。
STRUCTURE: 设置中心 5,288→4,283 行 + lib/ui/settings/ 四文件稳定边界；接口契约见 structure-todolist.md 移动端接入记录。
BLOCKERS: 仅剩实体机复测条件——a094767f 于 2026-09-15 采样时点从 adb 掉线（需物理重连）；模拟器（MuMu x64）已完成 P5 合成链路与 profile 帧率采样并回填报告。mobile M7 集成复测已闭环，无阻塞。
NEXT EXECUTABLE: 等待设备条件→实体机帧率采样与 P5 设备侧（命令见 final-report §7；a094767f 需 USB 插拔或无线配对授权出现在 adb devices）。
COMPLETION GATES: 性能 P0–P4 通过、P5 本地+模拟器设备链路通过（实体机复测待重连）；结构 S0–S5 通过（暂缓项有依据登记）；final-report.md 已交付并含设备实测数据；设备帧率门=模拟器口径完成、实体机口径 pending（外部条件：设备重连）。
```

## 专项清单链接

- [性能专项执行清单](performance-todolist.md)
- [结构专项执行清单](structure-todolist.md)
- 证据目录：`build/optimization/<批次>/`
- 起点审计：[optimization-code-audit-2026-09-14.md](../optimization-code-audit-2026-09-14.md)（历史事实已按当前代码重新核对，不沿用其结论）

## 既有工作保护（2026-09-14 核对）

- dirty diff 与性能候选重叠的文件：`chat_page.dart`(+241/-36)、`code_renderer.dart`(+13/-15)、`workspace_shell.dart`(+5)、`shell_layout.dart`(+13/-5)。本专项修改这些文件前必须重读 diff，不覆盖、不撤销、不把既有改动算作专项成果。
- 未跟踪新功能：`lib/protocol/qr_pairing.dart`、`lib/ui/qr_scan_page.dart`、`lib/ui/onboarding_wizard.dart` 修改、`docs/`、qr/onboarding 测试。归属其他任务。
- UI parity 未完成（不阻塞本专项，但保护其条件）：E2 真机同态、r5-1 ROG 源 setting get、E4 真实验证码、U24 品牌图对照。
- 审计时既有静态问题：`chat_page.dart` 1 warning + 1 info（unnecessary_null_comparison :776、sort_child_properties_last :1934）——处理该文件的批次中收口，不放宽断言。

## 批次索引

| 批次 | 目标 | 状态 | 证据 |
| --- | --- | --- | --- |
| R1-P0/S0 | 基线检查 + 源码身份 + 首个确定性性能场景采样 | 通过 | build/optimization/r1-p0-baseline/ |
| P1-conv | conversation.dart upsert/delta rowId 线性查找 → 算法基准 → 判定 | 通过（−99.8%@20k） | bench-conv-*.log |
| P2-chat | ChatPage 通知→分组→build 链路测量 | 通过（分组缓存测量排除；singleTurn 提升保留 −12.5%@5k） | p2-metrics-*.log |
| P2-viewport | 锚点捕获/indexOf 测量与优化 | 通过（findChildIndexCallback O(1) 化 −28.5%@5k；capture 排除） | p2viewport-*.log |
| S1-settings | 设置中心独立页面提取（更新页 + 共享组件 + 常规页） | 通过（5,288→4,283 行） | s1-settings-gate.log、s1-general-gate.log |
| P3-code | code_renderer 高亮/格式化重复解析测量与优化 | 通过（wrap −40.5%、nowrap −49%、formatCalls→0） | p3code-metrics-*.log、p3code-gate.log |
| P4-shell | workspace_shell 来源页保留/刷新测量 | 通过（测量确认按设计有界：retainedMax=1；测量排除） | p4shell-metrics.log |
| P5-voice | 语音/模型 isolate 复测 | 通过（本地+模拟器设备链路；实体机复测待重连） | p5-known-audio-mumu.log、p5-responsiveness-mumu.log |
| S2-chat | 聊天页拆分（turn_projection + change_summary 提取） | 通过（2,781→2,041 行） | s2-turn-projection-gate.log、s2-changesummary-gate.log |
| S3-protocol | conversation.dart 纯 Dart 分层（state 拆出） | 通过（其余分层有依据暂缓） | conversation_state.dart、smoke+协议门 |
| S5-guard | 结构守护测试 + architecture.md + final-report.md | 通过（3 守护不变量全过；报告含设备实测） | test/structure/boundary_guard_test.dart、architecture.md、final-report.md |
| 设备门 | 实体机帧率 + P5 实体机侧 | pending（外部条件：a094767f 掉线待重连；模拟器口径已完成） | pdevice-frames-mumu.log、p5-*.log |

## 批次纪律

- 同批一个主目标；性能批与结构批不同时改同一热点文件。
- 每批：选定条目 → 可证伪假设与达标规则（实现前登记）→ 保存前态 → 修改 → 最短相关验证 → 前后对照 → 更新清单。
- 保留优化默认门槛：主指标改善 ≥15% 且超测量噪声；非目标路径回退 >5% 需修正或撤回。
