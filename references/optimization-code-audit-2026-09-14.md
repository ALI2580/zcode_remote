# 性能与代码结构专项：源码审计

## 本轮范围与结论

2026-09-14，针对当前工作区进行源码抽查、规模统计、静态分析和重点回归，交付两个专项及一个统筹长程任务的执行 prompt。本轮未实施产品优化，未进行设备性能采样，以下性能条目均为待测候选，不是已经证实的卡顿根因。

当前架构适合渐进优化：纯 Dart 协议、ChangeNotifier 状态、Flutter UI、Kotlin 平台接口已分层，语音 worker、虚拟列表、作用域回归均有基础。主要问题是高频数据路径存在重复工作候选，大页面集中管理过多生命周期和业务操作，以及缺少统一、可比较的性能基线。

## 源码身份与既有工作

- HEAD：`23f0b30`；版本 `0.1.0+11`。
- `lib/`：154 个 Dart 文件，62,047 行（物理行，含注释与空行，不代表复杂度）。
- `test/`：197 个 `*_test.dart` 文件，不能当作测试用例数量。
- 审计开始前已有改动：`README.md`、`lib/ui/{chat_page,code_renderer,file_changes_review_panel,workspace_shell}.dart`、`lib/ui/shell/shell_layout.dart`，另有未跟踪 `docs/`。跟踪文件当时合计 309 行新增、60 行删除。
- 这些 UI 文件恰好与性能候选重叠；后续执行必须重新检查 diff，不能覆盖、撤销或把既有修改算作专项成果。
- `references/ui-parity-current-todolist.md` 已记录 U17–U26，但 SOURCE 仍引用旧 HEAD；验收表的语音同步执行描述也落后于源码。它们提供需求和历史证据，不代表本轮源码已实测通过。E2、r5-1、ARM64 实机等条件按现场重新核对。

## 结构审计

| 文件 | 行数 | 当前职责与拆分方向 |
| --- | ---: | --- |
| `lib/ui/settings_center_page.dart` | 5,288 | 导航/布局、来源切换、目录创建与释放、模型增删改/连接、导入/向导、套餐/更新与页面内容集中。先拆页面内容，再按所有权拆控制器协调；不要只迁成多个 part。 |
| `lib/ui/chat_page.dart` | 2,738 | 订阅、搜索定位、编辑/fork/反馈、阅读协调、回合分组与行渲染、变更审查并存。先建立会话生命周期与渲染边界。 |
| `lib/protocol/conversation.dart` | 2,250 | ConversationTransport、订阅基类/分片恢复、会话索引、ConversationState、DTO 聚集。可保留兼容导出入口，逐层分离纯 Dart 模块。 |
| `lib/state/remote_agent_catalogs.dart` | 1,666 | 多种远端目录集中；先辨别领域差异，再判断哪些解析/作用域辅助逻辑能共享。 |
| `lib/ui/mcp_settings.dart` / `hooks_settings.dart` | 1,649 / 1,513 | 目录与作用域交互复杂；提取已证实重复的展示组件，保留各自提交契约。 |
| `lib/ui/model_provider_editor.dart` | 1,475 | 已存在模型编辑独立组件；设置中心拆分优先复用这一边界。 |
| `lib/ui/workspace_shell.dart` | 1,411 | 导航、来源、面板和聊天实例管理集中；缓存生命周期需先测量再调整。 |

行数用于排查顺序，不作为硬性拆文件指标。特别是 `code_renderer.dart` 的 1,045 行含大量主题数据，不能据此与业务协调器作同等判断。

本轮对 `lib/protocol/` 的直接导入检索未发现 Flutter、`../ui/` 或 `../state/` 引用，且纯 Dart smoke 通过。后续结构专项需要覆盖 export/part/间接依赖的完整边界检查。

## 性能候选与验证要求

以下行号是本次快照定位，实施前按符号重新定位。

| 优先级 | 代码事实 | 待验证影响与正确优化边界 |
| --- | --- | --- |
| P1 | `conversation.dart:1993,2017`：upsert/delta 使用 `rows.indexWhere`。 | 单次查找随已加载行数增长。测 1k/5k/20k 行与固定 delta 序列；如果使用 rowId 索引，必须覆盖 snapshot、prepend、remove、epoch、未知 ID 与恢复重建。 |
| P1 | `chat_page.dart:886` 状态通知触发 setState；`:1046` build 调 `conversationTurnGroups`；`:130` 分组遍历全部 rows。 | 流式消息下可能重复全量分组和分配。区分通知次数、实际 build 次数及耗时；Flutter 可能合并同帧 setState，不能按通知数直接推算重建数。缓存不能仅依赖 List identity，因为 rows 可原位修改。 |
| P1 | `conversation_viewport.dart:51` 锚点捕获遍历 ids；`:96,162` 使用 indexOf；`:151` 已用 SuperListView.builder。 | 已有虚拟化，重点测可见项定位、key 查找、prepend 与可变高度。不可把它重新包装成“首次引入虚拟列表”。 |
| P1 | `code_renderer.dart:551` 在 `_body` 创建 highlighter，调用 format 并 split 行数。 | 大代码/diff、持续文本更新可能反复解析；采 CPU/分配与 UI/raster 帧耗时。缓存需有容量/字节上限，并覆盖文本、主题、字号、语言等真实影响维度；保持复制/选择和辅助功能。 |
| P2 | `workspace_shell.dart:833–837` 按 device/workspace 来源保留 ChatPage，再以 Offstage 展示。 | 静态代码不能证明泄漏，也不是每个 task 永久缓存。测来源切换、隐藏页面监听/布局活动、内存与资源释放；评估 suspend/有界保留时保留草稿、阅读与重连契约。 |
| P2 | `workspace_shell.dart:256` 多来源变化走统一刷新；设置中心同时管理多类请求。 | 测刷新频率、重复 RPC、隐藏页活动及热切换耗时。不能用跨来源全局缓存或合并写请求减少调用。 |
| P2 | 语音已在 `voice_transcriber_worker.dart` 使用 Isolate.spawn；模型解压和哈希已在 `voice_model_store_native.dart` 使用 Isolate.run。 | 优先复用现有优化，继续测音频传递/预览、冷暖识别、取消回执、解压峰值内存。异步移出 UI 不等于内存问题已经消除。 |

语音已有 `integration_test/voice_responsiveness_review_test.dart` 和 `voice_native_mic_review_test.dart` 的计时/FrameTiming 采集；本轮检索未发现聊天、diff 等场景统一的前后对照性能套件。需扩展已有入口，而非宣称整个仓库没有性能测试。

## 本轮验证

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| `flutter analyze --no-pub` | 退出 1：1 warning、1 info | `build/optimization-audit-20260914/analyze.log` |
| 5 个重点测试文件 | 51 项通过，退出 0 | `build/optimization-audit-20260914/focused-tests.log` |
| `dart run tooling/protocol_smoke.dart` | passed，退出 0 | `build/optimization-audit-20260914/protocol-smoke.log` |

静态问题：`chat_page.dart:776:19` unnecessary_null_comparison；`:1934:21` sort_child_properties_last。属于审计时既有工作区状态，本轮未修改。

重点测试为 `test/protocol/conversation_test.dart`、`test/state/conversation_history_test.dart`、`test/ui/conversation_viewport_test.dart`、`test/ui/code_renderer_test.dart`、`test/voice/voice_transcriber_lifecycle_test.dart`。未跑全量测试、Android 构建、真机帧率/内存测试，因此不宣称全仓验收、性能提升或 Android 可用性已经通过。

## 使用入口

1. [性能优化专项 prompt](performance-optimization-execution-prompt.md)：单独执行性能测量与优化。
2. [代码结构优化专项 prompt](structure-optimization-execution-prompt.md)：单独执行保行为重构。
3. [统筹长程任务 prompt](optimization-long-running-prompt.md)：推荐的统一入口，按依赖交替推进两个专项，避免共享热点文件交叉修改。

三份 prompt 已可用于后续实施；本轮没有创建新的 Codex 任务或启动后台自动执行。
