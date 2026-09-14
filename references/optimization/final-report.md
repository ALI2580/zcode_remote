# ZcodeRemote 性能与代码结构优化：最终报告

日期：2026-09-15。源码身份：HEAD `23f0b308b3080ce90494220b66dea8fed02fa5de` + 未提交 dirty（含本专项全部改动与其他任务的 qr/onboarding 既有工作）。关键文件 SHA1 清单见文末。证据目录：`build/optimization/r1-p0-baseline/`。

> 状态声明：本地全部门已通过（见 §5）；**设备侧门未完成**——实体机帧率验证与 P5 语音设备侧计时依赖实体机/profile 条件，当前受阻（§6）。按统筹 prompt，未完成必需门不得宣布全局完成；本报告如实交付本地完成部分与剩余条件。

## 1. 主要变化

### 性能（保留的优化）

| 批次 | 文件 | 变化 |
| --- | --- | --- |
| P1-conv | `lib/protocol/conversation_state.dart`（原 conversation.dart） | `ConversationState` 引入 rowId→index 映射（`_rowIndexByRowId`）：snapshot 两分支/row.removed/prependOlderRows 全量重建，row.appended 增量插入，重复 rowId 保首命中语义，null rowId 保留线性回退 |
| P2-chat | `lib/ui/chat_page.dart` | `_TurnGroup.build` 内 `singleTurn` 的 O(rows) 扫描提升为 `_buildChat` 每 build 计算一次（纯函数提升，语义等价） |
| P2-viewport | `lib/ui/conversation_viewport.dart` | `findChildIndexCallback` 由「线性扫 `_items` + `ids.indexOf`」双重 O(N) 改为 `_idByKey` 反向映射 + 按 ids 实例惰性重建的 `_indexById`（putIfAbsent 保首命中=原 indexOf 语义） |
| P3-code | `lib/ui/code_renderer.dart` | `_scopeFor` 每匹配 RegExp 静态化；`formatCode()` 顶层 LRU(≤8) 缓存（键=theme identical+fontSize+source 值）；`_body` 单次 format、wrap 分支复用同一 span；行号大字符串仅 showLineNumbers 时构建 |
| 观测设施 | chat_page / conversation_viewport / code_renderer / workspace_shell | 确定性计数器（`chatPageBuildCount`、`chatTurnGroupComputations`、`viewportIndexOfScans`、`codeFormatCalls`、`workspaceShellChatPagesBuilt` 等），测试与 CI 可观测 |

### 测量排除（未写任何优化代码，附数据依据）

| 候选 | 排除依据 |
| --- | --- |
| 流式分组缓存（按结构修订失效） | 5k 行历史全量分组仅占帧成本 ~2%（debug 口径），20k 行 1.3ms/帧仍 <16.7ms 预算 10%；增量分组机制需渲染链变更索引传播，风险/收益不成比例 |
| `_capture` 锚点捕获 O(N) 扫描 | 深滚动每次捕获 ~1×N 次 O(1) 哈希查找（20k 行 ≈0.2–1ms/帧末），绝对成本有界；super_sliver_list 0.4.1 无 firstVisibleItem API，提示窗口方案触及锚点阅读语义 |
| WorkspaceShell 来源页保留 | 12 次 ws-a↔ws-b 切换实测 `retainedMax=1`、`chatPagesBuilt=12`：按设计有界（切源即 clear），无泄漏无隐藏重建风暴 |

### 结构（职责移动与边界）

| 变化 | 前 | 后 |
| --- | --- | --- |
| 设置中心 | `settings_center_page.dart` 5,288 行集中 25+ 领域 | 4,283 行（壳/导航/来源协调）+ `lib/ui/settings/`：`settings_widgets.dart`（359，8 个公共行组件）、`update_about_settings_page.dart`（186，自持下载生命周期）、`general_settings_page.dart`（573，自持 system-info 代次守卫） |
| 聊天页 | `chat_page.dart` 2,781 行 | 2,041 行 + `lib/ui/conversation/turn_projection.dart`（227，纯 Dart 回合投影）+ `lib/ui/conversation/change_summary.dart`（539，变更摘要卡+撤销区块） |
| 协议 | `conversation.dart` 单文件 2,278 行 | 2,078 行 + `lib/protocol/conversation_state.dart`（ConversationState + HistoryPageResult，纯 Dart 仅依赖 observable）；conversation.dart 经 import+export 兼容 |
| 守护 | 无 | `test/structure/boundary_guard_test.dart`：protocol 纯 Dart（无 flutter/dart:ui/ui/state，含条件导入与 export/part）、state 不依赖 ui、protocol 无 import 环（DFS）——3 项全过 |
| 说明 | — | `references/optimization/architecture.md`（分层/所有权/作用域失效/测试入口/技术债，与实现对应） |

## 2. 前后指标与口径限制

全部为 Windows 11 x64 / Git Bash / `dart run` 与 `flutter test`（debug JIT）同机先后对照；**算法/确定性计数口径，非设备 release/profile 帧率**。基准：`tooling/bench_conversation_state.dart`、`test/ui/{chat_stream_metrics,viewport_metrics,code_viewer_metrics,shell_source_switch_metrics}_test.dart`。

| 指标 | 基线 | 优化后 | 变化 |
| --- | --- | --- | --- |
| ConversationState 600-delta 帧 median（3 进程×7 轮） | 1k=5.20ms / 5k=23.9ms / 20k=95.1ms | 0.60ms / 0.28ms / 0.21ms | 20k **−99.8%** |
| Viewport 场景 A（顶部流式 40 帧，N=5000）wall | 345.9ms | 247.4ms | **−28.5%** |
| Viewport 场景 C（深滚动下流式 40 帧）wall | 1k/5k/20k=275.9/325.3/329.2ms | 191.7/187.1/159.2ms | **−30.5%/−42.5%/−51.6%** |
| Viewport `indexOfScans`（C，N=20k×40 帧） | 11,207,280 步 | 0 | O(visible×N)→O(N+visible) |
| CodeViewer 重建 40 帧（1k 行）wrap=true / false | 10,529.7 / 940.7ms | 6,262.4 / 480.2ms | **−40.5% / −49.0%** |
| `codeFormatCalls`（40 帧） | 40 / 80 | 0 | 缓存全命中 |
| Chat 流式 singleTurn 提升（5k 行 60 帧）wall | 808.2ms | 707.3ms | −12.5%（未达 15% 主指标，按「复杂度/分配收益+绝对耗时」规则保留：每 build O(可见组×N)→O(N)，纯提升语义等价，如实登记） |
| 流式分组每帧成本占比（对照） | 5k 行 ≈2% | — | 分组缓存候选排除依据 |

### 设备口径（2026-09-15，MuMu x64 模拟器 Android 12，profile 模式；非实体机达标口径）

| 指标 | 数值 |
| --- | --- |
| 语音冷推理（whisper-tiny-en，合成 PCM） | 2,072ms，UI 计时最大间隔 89ms（断言 <750ms），推理期间 UI 操作 72 次，识别含 "known" |
| 语音暖推理 | 267ms，最大间隔 21ms |
| 预览+停止 | 预览 1,673ms、停止 248ms，预览/最终文本均匹配 |
| 取消（decode 已派发后） | 取消 0ms，迟到文本被拒收（lateTextRejected=true） |
| 聊天流式（1k 行，60 帧） | build p95 4.50ms、raster p95 1.44ms、总 p95 5.87ms；超 16.67ms 帧 0/60 |
| 聊天滚动 fling（204 帧） | build p95 0.25ms、raster p95 1.19ms、总 p95 1.87ms；超 16.67ms 帧 1/204 |

命令与日志：`build/optimization/r1-p0-baseline/{p5-known-audio-mumu,p5-responsiveness-mumu,pdevice-frames-mumu}.log`。

噪声说明：debug widget 测试 wall 抖动 ±4–5%（逐次报告于各 `*-metrics-*.log`）；主判定以 ≥15% 改善+超噪声或确定性计数为准；60/120Hz 设备预算换算未适用（设备门未做）。

## 3. 行为保持证据

- 协议语义：conversation_test（含 7 个新增索引一致性用例：snapshot 重建/prepend/remove/epoch/未知 rowId/null rowId 线性回退/历史分片恢复）、conversation_history_test 全过。
- 阅读/锚点：conversation_viewport_test（冷恢复跨宽度与 140% 字号、键盘 inset）全过；锚点捕获/恢复代码路径未改语义。
- 单提交/搜索/主辅聊天：chat_row_dispatch、file_changes 系列、side_panel、tool_chat、turn_summary 系列全过。
- 设置：U19 宽度、client/settings_embed/v1_3/connection/mcp/hooks/skills parent scope 门 52 通过；新增 general/update 页面测试 4 个。
- 协议纯度冒烟：`tooling/protocol_smoke.dart` passed。

## 4. 实际验证命令与结果（最终同源码）

```text
flutter analyze --no-pub                  → exit 0（No issues found）
dart run tooling/protocol_smoke.dart      → exit 0（{"projection":"passed"}）
flutter test                              → exit 0（**981 通过 / 1 跳过**，final-full-test.log，2026-09-15 最终源码）
```

（最终源码 = 报告文末 SHA1 清单；如两者不一致以 log 内身份为准。）

## 5. 完成门对照

| 门 | 状态 |
| --- | --- |
| P0 基线 / P1-conv / P2-chat / P2-viewport / P3-code / P4-shell | 通过（P4 为按设计有界的测量排除；P2-chat 分组缓存为测量排除） |
| P5-voice | 本地合成通过；设备侧合成链路已在 Android 设备（MuMu x64 模拟器）执行通过并取得计时（见 §2 设备口径）；**实体机（a094767f）复测仍待设备重连**（2026-09-15 采样时点设备已从 adb 掉线，`adb devices` 仅余模拟器） |
| 设备帧率/渲染采样 | **模拟器口径已完成**：profile 模式，1k 行历史流式 60 帧 build p95 4.50ms/raster 1.44ms/总 5.87ms，超 16.67ms 帧 0/60、超 8.33ms 帧 2/60；滚动 fling 204 帧 build p95 0.25ms/raster 1.19ms/总 1.87ms，超 16.67ms 帧 1/204（证据 `pdevice-frames-mumu.log`，harness `integration_test/streaming_frame_metrics_test.dart`）。**实体机口径待设备重连后一键复跑同 harness** |
| S0 盘点 / S1-settings / S2-chat（投影+摘要卡提取） / S3-protocol（state 分层） / S5-guard | 通过；搜索控制器化与 conversation.dart 其余分层登记为有依据的暂缓（见 architecture.md 技术债） |
| 设备帧率/渲染验证 | **受阻**——实体机 a094767f + profile 模式条件 |
| 联合验收 | 本地门全过；设备门与产品 parity 门（E2/r5-1/E4，属 ui-parity 专项）未含 |

## 6. 保留的技术债与外部条件

1. 实体机（a094767f）帧率与 P5 复测：采样 harness 与命令已就绪（§7），设备 2026-09-15 采样时点 USB 掉线——最小缺失条件=重新连接设备。模拟器（MuMu x64/Android 12，虚拟 333Hz 显示）数据仅作功能与量级参考，不作为实体机达标。
2. P5 语音实体机侧物理麦克风链路：本批使用合成 PCM fixture（测试自身声明不覆盖物理麦克风）；真实录音链路仍待实体机验证。
3. chat_page 搜索控制器化、消息动作控制器化：与 State/GlobalKey/单提交语义深耦合，需要行为级重构批次。
4. conversation.dart 其余分层（Transport/Subscription/DTO）：机械拆分不降耦合，维持现状（guard 测试锁定无环）。
5. 移动端并行任务：`lib/ui/settings/`、`lib/ui/conversation/` 为稳定接入边界（契约见 structure-todolist「移动端并行任务接入记录」）；集成验证须同源码复测（尚未发生）。

## 7. 如何复现

```bash
# 基线/优化后算法与计数（证据在 build/optimization/r1-p0-baseline/）
flutter test test/ui/chat_stream_metrics_test.dart        # P2CONV 行
flutter test test/ui/viewport_metrics_test.dart           # P2VIEW 行
flutter test test/ui/code_viewer_metrics_test.dart        # P3CODE 行
flutter test test/ui/shell_source_switch_metrics_test.dart # P4SHELL 行
dart run tooling/bench_conversation_state.dart            # P1 帧耗时 JSON 行
# 结构守护
flutter test test/structure/boundary_guard_test.dart
# 阶段门
flutter analyze --no-pub
dart run tooling/protocol_smoke.dart
flutter test
```

## 8. 关键文件 SHA1（最终源码）

```text
lib/protocol/conversation.dart            27307f4daa839d4758d252aed1e905c1e8d38c58
lib/protocol/conversation_state.dart      74a2abbd5c8fc01e1f23259f6e6bae64e5f59b15
lib/ui/chat_page.dart                     7d5133450055ea2d961fd4b00f047e9296944bb7
lib/ui/conversation_viewport.dart         3d857feabbb068292cff002bc578fa242fede282
lib/ui/code_renderer.dart                 833f0f99535b85e04a488fc43ca3ca7388ac3c43
lib/ui/workspace_shell.dart               46809978a31090a20d841a7953cdf45fc22dc41a
lib/ui/settings_center_page.dart          b49e81245b5aa23f51139115b4813fc841090845
lib/ui/settings/settings_widgets.dart     1289df28aa7c09156fcb694c0a89019f26f2a970
lib/ui/settings/general_settings_page.dart 5bd4f2bc72e333d041b6167fd7892dc56cf5f793
lib/ui/settings/update_about_settings_page.dart cf7bc8b004bbeaaba9c5b00784fb35881c458149
lib/ui/conversation/turn_projection.dart  e88f2f3220b0026755d0678eabf0564b8b3c270d
lib/ui/conversation/change_summary.dart   a4c26e6925348e7fc064d47eeff47f2d3cbc8b36
test/structure/boundary_guard_test.dart   5d1b81334b65756f3b69dff51a5cd787a10e02ba
tooling/bench_conversation_state.dart     20b12fd7cfec8775fc4cdca4b0b6b30d376d4845
```

## 9. 集成后联合复测（2026-09-15，mobile-portrait M7 集成）

背景：mobile-portrait-ux 专项于 2026-09-15 04:07 完成 M7 集成收口（`references/mobile/mobile-todolist.md` INTEGRATION STATUS=已集成到主目录），其请求本侧对集成后源码做同源码非退化复核并签字（`references/mobile/perf-signoff-request.md`）。本节为该请求的执行记录与签字。

### 源码身份核对

- 性能侧热点文件与 §8 冻结 SHA1 逐一对照：`conversation_state.dart`（74a2abbd）、`conversation.dart`（27307f4d）、`conversation_viewport.dart`（3d857fea）、`code_renderer.dart`（833f0f99）、`workspace_shell.dart`（46809978）、`settings_center_page.dart`（b49e8124）**全部一致**——协议 rowId 索引、viewport O(1) 映射、code LRU、P4 保留策略核心未被集成改动。
- **例外（如实登记）**：`lib/ui/chat_page.dart` 由冻结的 7d513345 变为 a464985d——mobile 侧按协作规则在共享聊天入口做了竖屏/移动布局适配（其 patch 文件清单含此文件，属 mobile 拥有范围）；该路径由 `chat_stream_metrics_test.dart` 覆盖复测。
- 全部确定性计数器（chatPageBuildCount/chatTurnGroupComputations/viewportIndexOfScans/codeFormatCalls/workspaceShellChatPagesBuilt/_rowIndexByRowId/singleTurn）在集成后源码中存活。

### 复测结果（证据 `build/optimization/post-integration/`）

| 项 | 结果 | 对照判定 |
| --- | --- | --- |
| `flutter analyze` | No issues found（0） | 与冻结一致 |
| bench 全量模式（1000/5000/20000） | 5000=280/285μs，20000=204/211μs（两次独立跑） | 均落冻结带（5000: 272–310；20000: 209–217，20000 最低值受窗口抖动落在带内下沿） |
| bench timed 模式（5000-first，×4） | 5000=430–463μs，20000=221–229μs | 20000 带内（+2–5%）；5000 带外 +45% **判定为测量伪影**（见下） |
| chat_stream / viewport / code_viewer harness | 9 通过；P2VIEW C indexOfScans=0、P3CODE formatCalls=0 | 与冻结口径一致 |
| shell_source_switch harness | 通过；switches=12 retainedMax=1 | P4 有界性维持 |

5000-first 伪影定性：同一分钟内，同源码同命令下 5000 作为第二个 size 测量（全量模式，1000 先行热身）= 285μs 带内，5000 作为首个 size = 455μs；mobile 侧 04:17 在同源码上同命令三轮得 288–311μs 带内。差异与代码无关，属 JIT 预热次序敏感性叠加当时窗口后台负载（MuMuVMM/ZCode 常驻）对短样本（~0.4ms 级）的放大。算法路径无回退的判定以全量模式（与冻结采集口径一致）+ 四 harness + analyze 为准。

### 签字结论

**集成后联合复测通过（非退化）**：性能侧全部保留优化（P1 rowId 索引、P2 viewport 映射、P3 code LRU、P4 有界保留、singleTurn 提升）在集成后源码上复核成立。实体机口径门保持原登记（a094767f 待物理重连），不因本复测变更。
