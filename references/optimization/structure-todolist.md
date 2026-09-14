# 代码结构优化专项执行清单

状态：待核查 / 进行中 / 已实现待验证 / 通过 / 受阻 / 有依据不适用。

## S0 依赖与所有权盘点（2026-09-14，HEAD 23f0b30 + dirty）

### settings_center_page.dart 职责块（盘点时 5,288 行）

单一 `_SettingsCenterPageState`（74–4818 行区间）集中持有约 25 个领域的状态字段与生命周期：

| 职责域 | 主要字段/方法 | 外部复用边界 |
| --- | --- | --- |
| 更新与关于 | _checking/_updateError/_update/_downloader、_checkUpdate、_startDownload | 已独立（update 包） |
| 远端设置投影 | _remoteSettings（AppSessions 共享或自有）、_ownsRemoteSettings | 语义：路由关闭后 ChatPage 保留已确认投影，不可改所有权 |
| skills/plugins/mcp/subagents/commands 目录 | 各 catalog + workspaceMonitor + scope + selectionGeneration | 各自有独立设置页组件（skills_settings.dart 等） |
| 模型供应商 | _modelProviders、_modelConnectivity、_selectedProviderId、_selectedModelFamily、套餐 entitlement/familyOptions 生成代次 | model_provider_editor.dart 已是独立组件 |
| 浏览器控制/常规/集成终端 | _remotePlatform、_terminalShells、_systemInfoGeneration | 走 remoteSettings 快照 |
| 语音/外观/通知/usage/devices/updates | 已委托独立页面组件（VoiceModelManager、AppearanceSettingsPage、NotificationSettingsPage、内嵌 devices/usage） | 已是目标形态 |

判定：设置中心的问题是「页面内容 + 协调」集中而非缺组件。提取方向=每节内容自包含化（内容 widget 持有自己的生命周期），协调器留待内容全部独立后评估。

### 聊天/协议/外壳（初步，后续批次细化）

- `chat_page.dart`（2,978 行）：订阅、搜索、编辑/fork/反馈、阅读协调、回合分组、变更审查并存；P2 性能批先行测量，S2 结构批按测量结果拆。
- `protocol/conversation.dart`（2,278 行）：外部 import 仅 dart:* + crypto + 协议内模块（已核对）；ConversationState/Subscription/Transport/DTO 同文件。S3 拆分需保 wire 语义。
- `workspace_shell.dart`：导航/来源/面板/聊天实例集中；缓存与生命周期调整归性能批 P4。

## 批次记录

### S1-settings：设置中心独立页面提取

- [x] 首个提取：**更新与关于页**（`lib/ui/settings/update_about_settings_page.dart`，2026-09-14）
  - 原职责：`_SettingsCenterPageState` 的 default 分支内联内容 + `_checking/_updateError/_update/_downloader` 字段 + `_checkUpdate`/`_startDownload` + dispose 释放 downloader + initState 的 updateChannelSettings.load()。
  - 最终 owner：`UpdateAboutSettingsPage`（StatefulWidget）独占更新检查与下载生命周期；设置中心仅保留 section 路由（`_content` default 分支返回该页面）。
  - 行为保持：ListView 松约束左对齐由 Column(crossAxisAlignment: start) 等价复现；文案/控件/复制下载地址 SnackBar/下载进度反馈逐项保留；设置中心 initState 不再预载 updateChannelSettings（由页面自管，Beta 开关读取即时值）。
  - 修改文件：`lib/ui/settings_center_page.dart`、新增 `lib/ui/settings/update_about_settings_page.dart`、新增 `test/ui/settings/update_about_settings_page_test.dart`（2 用例）。
  - 验证：analyze 0；新测试 2 通过；设置行为门 49 通过。证据 `s1-settings-gate.log`。
  - 状态：通过（已实现待 E2 视觉对照，同其余设置页）。
- [x] 第二提取：**共享设置组件 + 常规页**（2026-09-15）
  - `lib/ui/settings/settings_widgets.dart`（359 行）：settingsCard/settingsRow/remoteSpinner/settingsSwitch/remoteToggle/remoteTogglePatch/saveFailedColumn/RemoteTextSetting——原 settings_center 私有 helper 家族公共化（逐行搬移，语义零改动）；51 处调用点改公共导入。契约：组件不缓冲状态，变更全走 RemoteSettingsController，失败保留已存值+重试。
  - `lib/ui/settings/general_settings_page.dart`（573 行）：`GeneralSettingsPage({preferences, remoteSettings, remoteMonitor})` 独占常规节内容 + win32 集成终端 shell 的 system info 只读生命周期（`_systemInfoGeneration` 代次守卫，旧连接迟到结果不写入新来源）。controller 生命周期仍归设置中心（AppSessions 共享或路由内自有语义不变），页面 dispose 不释放 controller。系统信息加载从「设置中心打开即加载」改为「页面挂载加载」——RPC 延迟且仅在实际查看常规节时发生，页面语义不变。
  - `lib/ui/settings_center_page.dart`：5,288 → 4,283 行（三批累计 −1,005）；`case 'general'` 换为 GeneralSettingsPage；删除 _generalContent/_loadSystemInfo/_integratedShellRow/_selectedShell/_settingsCard/_settingsRow/_remoteSpinner/_settingsSwitch/_remoteToggle/_remoteTogglePatch/_saveFailedColumn/_RemoteTextSetting 及 shell 三字段。
  - 新测试：`test/ui/settings/general_settings_page_test.dart`（2 用例：无远端占位、四卡渲染与 win32 select 隐藏语义）。
  - 验证：analyze 0；新测试 + 更新页测试 4 通过；扩展设置行为门（client/settings_embed/v1_3/connection/mcp/hooks/skills parent scope）52 通过 exit 0。证据 `build/optimization/r1-p0-baseline/s1-general-gate.log`。
  - 状态：通过（已实现待 E2 视觉对照，同其余设置页）。
- [ ] 下一提取候选：browser/indexing 节内容（当前走 _remoteSettingsContent 分支，已复用共享组件）评估其独立成页收益；或转向 S2-chat。待测量批次后定。

### S2-chat：聊天页拆分（2026-09-15）

- 盘点结论（chat_page.dart 2,781 行）：订阅绑定、搜索定位、消息动作、回合分组、行分派、变更摘要并存。搜索定位（_locateSearchSnippet 及高亮调度）与 State/GlobalKey/Toast/视图锚点深度耦合，控制器化需重排回调链（单提交/epoch 语义风险），登记为暂缓；纯投影与自包含组件可安全拆出。
- 提取 1：`lib/ui/conversation/turn_projection.dart`（227 行，纯 Dart 无 Flutter 依赖）——turnDurationMs/turnWorkLabel/formatTurnDuration/turnWorkLabelEnglish/turnDefaultOpen/rowIsActive/conversationTurnGroups(+P2 计数器)/conversationFileChangeSummaryRows/TurnFileChangeStats/turnFileChangeStats。chat_page 经 `export show` 保持外部导入契约（workspace_shell 与 6 个测试文件零改动通过）。
- 提取 2：`lib/ui/conversation/change_summary.dart`（539 行）——ConversationChangeSummary + _RewindFileSection 整体迁移；依赖 FileChangesReviewController/turn_projection/theme，卡片自持 review controller 生命周期（didUpdateWidget 换 scope 时 dispose 旧实例语义原样保留）。
- 规模：chat_page 2,781→2,041 行（-26%）。门：analyze 0；chat_page_logic/row_dispatch/stream_metrics/file_changes/turn_summary×2/side_panel/tool_chat/history 35+34 两轮全过。证据 `s2-turn-projection-gate.log`、`s2-changesummary-gate.log`。
- 状态：通过（首两步提取完成；搜索/消息动作控制器化登记为技术债）。

### S3-protocol：会话协议分层（2026-09-15，第一步）

- 提取：`lib/protocol/conversation_state.dart` —— `ConversationState` + `HistoryPageResult`（快照/delta 应用、rowId 索引、乐观更新）；仅依赖 observable.dart（纯 Dart）。`conversation.dart` 经 `import + export` 兼容（外部导入零改动）。
- 验证：dart analyze protocol 无问题；protocol smoke passed；conversation/history/stream_metrics 门 48 通过。
- 剩余分层（Transport/Subscription/SessionsIndex/DTO 拆文件）：wire 语义与订阅握手代码集中且互引紧密，机械拆文件增加转发层不降低耦合，按 S3 prompt「可保留原文件作为兼容入口」判定当前粒度合理，登记为有依据的暂缓。
- 状态：通过（state 分层落地；其余项给出依据关闭）。

### S5-guard：结构守护与架构说明（2026-09-15）

- `test/structure/boundary_guard_test.dart`（3 不变量）：protocol 纯 Dart（无 flutter/dart:ui/ui/state 依赖，含条件导入与 export/part）；state 不依赖 ui；protocol 无 import 环（DFS）。3 项全过。
- `references/optimization/architecture.md`：分层、所有权、作用域失效、测试入口、技术债，对应实际代码。
- 状态：通过。

## 边界守护（已并入 S5，见上）


- 协议层依赖检查、architecture.md：待 S1–S4 完成后统一产出。

## 移动端并行任务接入记录（2026-09-15，按协作规则登记）

### 当前拥有的文件（性能/结构任务，本 checkout）

- 协议/索引/缓存/通知/生命周期：`lib/protocol/conversation.dart`（ConversationState rowId 索引，公共 API 未变）、`lib/ui/conversation_viewport.dart`（内部 O(1) 映射，公共 API 未变）、`lib/ui/chat_page.dart`（测量计数器 + singleTurn 提升，ChatPage 公共 API 未变）。
- 架构拆分（新边界，移动端请接入新文件，勿把旧巨型页面内容复制回移）：`lib/ui/settings/settings_widgets.dart`、`lib/ui/settings/general_settings_page.dart`、`lib/ui/settings/update_about_settings_page.dart`。
- 测量工具：`tooling/bench_conversation_state.dart`、`test/ui/chat_stream_metrics_test.dart`、`test/ui/viewport_metrics_test.dart`（顶层的 `chatPageBuildCount`/`chatTurnGroupComputations`/`viewportChildIndexProbeCalls` 等为确定性测量计数器，产品语义无关）。

### 稳定接口与契约（移动端可直接使用）

1. `settings_widgets.dart`（公共展示组件）：`settingsCard` / `settingsRow` / `remoteSpinner` / `settingsSwitch` / `remoteToggle` / `remoteTogglePatch` / `saveFailedColumn` / `RemoteTextSetting`。契约：组件不缓冲状态，变更全部经 `RemoteSettingsController`（`setting.update`/`updatePatch`）；保存失败保留已存值并显示重试行；`RemoteTextSetting` 的未保存编辑不会被后台 refresh 覆盖。移动端改触控尺寸/密度时改这些组件即可全设置页生效，勿在各页重写。
2. `general_settings_page.dart`：`GeneralSettingsPage({preferences, remoteSettings, remoteMonitor})`。controller owner=调用方（设置中心继续持有 RemoteSettingsController 生命周期，AppSessions 共享或路由内自有语义不变）；页面仅自有 system info 生成代次守卫（`_systemInfoGeneration`，防旧连接迟到结果写入新来源）；页面 dispose 不释放 controller。win32 集成终端 shell 行按 `systemService.listIntegratedTerminalShells` 失败降级语义保留。
3. `update_about_settings_page.dart`：`UpdateAboutSettingsPage()`。自持 `UpdateDownloader` 生命周期（dispose 释放）+ `updateChannelSettings.load()`；Beta 开关持久化走 shared_preferences。
4. 三个页面均为「section 内容 widget」形态：返回松约束左对齐 Column，由设置中心 ListView 内嵌（`embedded` 语义与 AppearanceSettingsPage/NotificationSettingsPage 一致）；移动端竖屏换容器时替换设置中心的 section 分发即可，页面内容组件保持稳定。

### 稳定批次源码身份（analyze 0 问题，全测试门通过，未提交）

- HEAD `23f0b308b3080ce90494220b66dea8fed02fa5de` + dirty（上轮 15 文件 +1071/−145 基础上，新增本专项对 conversation/chat_page/conversation_viewport/settings_center 的修改与新文件）。
- 关键文件 SHA1：settings_widgets `1289df28…`、general_settings_page `5bd4f2bc…`、update_about_settings_page `cf7bc8b0…`、settings_center_page `13f68bc3…`、conversation_viewport `3d857fea…`、chat_page `57e97585…`、conversation `716ad4c3…`。

### 下一批计划（恢复入口）

- 完成 S1-general 收尾：settings_center_page 的 `case 'general'` 换为 `GeneralSettingsPage`，删除已迁出的 `_generalContent/_loadSystemInfo/_integratedShellRow/_selectedShell/_settingsCard/_settingsRow/_remoteSpinner/_settingsSwitch/_remoteToggle/_remoteTogglePatch/_saveFailedColumn/_RemoteTextSetting` 及 shell 三字段，剩余 51 处私有调用点改为公共导入；门=analyze 0 + 设置行为门 + general 页新测试。
- 之后按 master 清单：P3-code → P4-shell → S2-chat/S3-protocol → P5-voice → S5-guard → 联合验收。
