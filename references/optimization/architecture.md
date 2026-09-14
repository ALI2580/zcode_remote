# ZcodeRemote 架构说明（优化专项后）

更新：2026-09-15。本文对应工作区实际代码（HEAD 23f0b30 + 未提交优化改动，关键 SHA1 见 structure-todolist.md「移动端并行任务接入记录」），不是理想目录图。

## 分层与依赖方向

```text
lib/protocol  纯 Dart（仅 dart:* + crypto/crypto 生态）
lib/state     业务状态与异步协调（ChangeNotifier/ValueNotifier；依赖 protocol）
lib/ui        渲染与交互（依赖 state、protocol；经 MethodChannel/条件导入触达平台）
lib/voice     语音 worker/model store（Isolate 边界）
lib/update    版本/通道/下载
android/      Kotlin 平台能力（MainActivity、AttachmentPicker、TaskProgressService）
```

不变量由 `test/structure/boundary_guard_test.dart` 守护：
1. `lib/protocol/**` 不得 import Flutter、`dart:ui`、`lib/ui`、`lib/state`（import/export/part、相对与 package 路径均检查）。
2. `lib/state/**` 不得 import `lib/ui`（依赖方向 ui→state）。
3. `lib/protocol/**` 自身无 import 环。

## 模块职责与资源所有权

### protocol/

- `conversation.dart`：ConversationTransport（RPC facade/订阅握手/分片恢复/重同步）、ConversationSubscription（订阅基类）、SessionsIndexState/Subscription、WorkspacePrep、ConfigOption/SlashCommand/SessionEntry 等 DTO、`_LogicalFrameAssembly` 帧组装。经 `export 'conversation_state.dart'` 保持既有导入入口稳定。
- `conversation_state.dart`：`ConversationState`（快照/delta 应用、`HistoryPageResult`、行号→索引映射 `_rowIndexByRowId`）。所有权：订阅持有 state 生命周期；`rows` 公共可读，**只允许经 ConversationState 方法变更**（索引不变量）。历史分片 `loadOlder` 的 cursor/epoch 语义在此层。
- 其余：`relay_client`/`rpc_transport`/`ipc_codec`/`channel_client`（bridge/RPC 栈）、`qr_pairing`（配对）、`device_info*`（条件导入样板）、`file_changes`/`entitlement`/`plan_reset`/`git` 等领域 DTO。

### state/

- `app_sessions.dart`：AppSessions/DeviceSession（设备/工作区/会话作用域；`remoteSettingsForMonitor` 共享 RemoteSettingsController 所有权）、WorkspaceMonitor。
- `conversation_history.dart`：历史分页投影（stale/applied 契约，迟到的旧分页不写新游标）。
- `remote_settings.dart`：RemoteSettingsController（setting.update/updatePatch 的保存状态机；保存失败保留已存值+重试）。
- `conversation_view_state.dart`：阅读锚点/following/展开态（真实手势才改变 following）。
- `client_preferences.dart`：语言/字号等客户端偏好 + `uiText`。
- `composer_*`、`mcp_catalog`、`skills_catalog`、`plugin_catalog`、`model_provider_catalog`、`coding_plan_upgrade`、`usage_*`、`recovery_journal`：各自领域目录/队列/统计，作用域键含真实维度。

### ui/

- `app.dart` / `home_page.dart` / `navigation.dart`：路由与目录。
- `workspace_shell.dart`：导航/侧栏/终端/主辅面板/来源页保留。`_chatPages` Offstage 缓存**按设计有界**（切源即 clear，`workspaceShellChatPagesBuilt/RetainedPagesMax` 计数器可观测）。
- `chat_page.dart`（2,041 行）：会话订阅绑定、搜索定位（GlobalKey/RenderBox 高亮留在 UI）、消息动作（编辑/fork/反馈）、行分派。纯投影与变更摘要卡已拆出（见下）。
- `conversation/turn_projection.dart`：回合分组/工作标签/时长/折叠规则的**纯 Dart 函数**（`conversationTurnGroups` 等，含 P2 计数器）。chat_page `export` 保持既有导入。
- `conversation/change_summary.dart`：`ConversationChangeSummary` 变更摘要卡 + 撤销区块（依赖 `FileChangesReviewController`，controller 生命周期归卡片状态）。
- `conversation_viewport.dart`：SuperListView 虚拟化 + 锚点捕获/恢复；`_idByKey/_indexById` O(1) 子项定位；`_capture` 线性扫描为已知有界成本（见 performance-todolist P2-viewport）。
- `code_renderer.dart`：代码/diff 渲染；`formatCode()` LRU(≤8) 缓存、行号 painter 字段比较跳过重绘。
- `settings/`：`settings_center_page.dart`（壳/导航/来源协调，4,283 行）+ `settings_widgets.dart`（共享行组件，controller 持变更）+ `general_settings_page.dart` / `update_about_settings_page.dart`（自包含页面，自持下载器/system-info 生命周期）+ 其余既有独立设置页。
- `mobile/`：手机竖屏专项边界（并行任务，独立 worktree）。

### 作用域与失效

连接代次/logEpoch/会话 ID 在 protocol 层校验（早到帧缓冲、旧代次丢弃、gap→resync）；`RemoteSettingsController`/`SkillsCatalog` 等 catalog 由 AppSessions 按设备+工作区共享，借用方 dispose 不释放共享实例；`GeneralSettingsPage._loadSystemInfo` 的 `_systemInfoGeneration` 防旧连接迟到结果写入新来源；`ConversationViewState` 按 device+workspace+session 存于 `sessions.conversationViewStates`。

## 测试入口

- 协议：`test/protocol/`、`test/state/conversation_history_test.dart`、`tooling/protocol_smoke.dart`（纯 Dart 冒烟）。
- 结构守护：`test/structure/boundary_guard_test.dart`。
- 性能基准/计数：`tooling/bench_conversation_state.dart`、`test/ui/chat_stream_metrics_test.dart`、`test/ui/viewport_metrics_test.dart`、`test/ui/code_viewer_metrics_test.dart`、`test/ui/shell_source_switch_metrics_test.dart`（P2/P3/P4 的确定性计数器定义于被测文件顶部）。
- 渲染/交互：`test/ui/`（含 settings/、conversation 相关回归）。

## 技术债与已知边界

1. `chat_page.dart` 仍集中订阅绑定+搜索+消息动作；搜索域与 State/GlobalKey 深耦合，控制器化需要重排回调（已登记未做）。
2. `conversation.dart` 仍同文件承载 Transport/Subscription/SessionsIndex/DTO；state 已拆出，其余分层未动（wire 语义风险大于收益，未做）。
3. `_capture` 锚点捕获为 O(首可视行 index) 线性扫描；super_sliver_list 0.4.1 无 O(1) 可见项 API（升级包未授权）。
4. 设备帧率与 P5 语音设备侧计时未验证（实体机/profile 条件待满足）。
5. 流式分组缓存、`CodeSyntaxHighlighter.format` 原语正则扫描：经测量排除/保留原状，依据见 performance-todolist。
