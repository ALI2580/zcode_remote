# mobile-portrait 集成请求（integration-request）

批次：M1-r1、M3-1-r1、M3-2-r1、M2-2-r1、M4-1-r1、M5-1-r1、M6-2-r1（终端最大化）、
M7-r1（本地验收矩阵），2026-09-15。
源 worktree：`D:/WorkSpace/ZcodeRemote-mobile`，分支 `codex/mobile-portrait-ux`。

## Base

- HEAD 23f0b308b3080ce90494220b66dea8fed02fa5de + dirty 快照
  （dirty.patch sha1 `1062e21f…`，双快照 45s 稳定窗口验证）。
- 上游在本批次期间继续推进（S1 第二提取出现 `lib/ui/settings/settings_widgets.dart`、
  `general_settings_page.dart`，晚于本基线）；集成时需对齐最新上游。

## 本批新增文件（mobile 专属，无上游冲突）

| 文件 | 说明 |
| --- | --- |
| `lib/ui/mobile/mobile_layout.dart` | `MobileLayout.isCompact(width, textScaler)`，600*scale compact 候选判定 |
| `lib/ui/mobile/touch_target.dart` | `MobileIconButton`：视觉 18 图标 + ≥48 命中区 |
| `lib/ui/mobile/option_sheet.dart` | `showMobileOptionSheet` / `MobileOptionSheet`：compact 底部选择面板（标题/搜索/列表/选中态/取消，SafeArea+viewInsets） |
| `test/ui/mobile/mobile_layout_test.dart` | 判定边界（含浮点安全边界、200% 大字阈值放大） |
| `test/ui/mobile/touch_target_test.dart` | 命中 ≥48、相邻不重叠/不误触、边缘命中、200% 大字 |
| `test/ui/mobile/option_sheet_test.dart` | 选项回传、一次 Back 只关一层、搜索过滤、键盘 inset 可达、200% 无溢出、禁用项不回值 |
| `test/ui/mobile/terminal_drawer_touch_test.dart` | 接入点行为：compact 48 命中 + 关闭仅作用当前 tab + 宽屏 24×24 保持 |
| `test/ui/mobile/terminal_drawer_capture_test.dart` | 390 宽抽屉截图（ZCODE_UI_CAPTURE_DIR） |
| `test/ui/mobile/composer_touch_test.dart` | M3-1 接入点行为：compact 容器下 submit/chips ≥48 行且不重叠；宽屏 28 保持 |
| `test/ui/mobile/composer_sheet_test.dart` | M3-2 接入点行为：compact 面板打开/搜索/选项写回 config、宽屏仍走锚点弹层 |
| `test/ui/mobile/shell_header_test.dart` | M2-2 接入点行为：compact 顶栏 nav/more 48 命中（MobileIconButton），宽屏 40 保持 |
| `test/ui/mobile/message_actions_test.dart` | M4-1 接入点行为：ChatPage 实渲染，compact 消息 Copy 钮 ≥48、宽屏 28 |
| `test/ui/mobile/settings_sections_test.dart` | M5-1 接入点行为：列表入口/选项进详情/PopScope 回列表不退出设置、深链接直达、宽屏无列表 |

## 共享入口接线（需逐批对接）

| 文件 | 改动 | Patch |
| --- | --- | --- |
| `lib/ui/terminal_panel.dart` | 仅 `_TerminalDrawerState.build` 头部两按钮与 `_TerminalTab`：compact 分支换 `MobileIconButton`、tab minHeight 48、关闭钮 36×48（宽屏代码路径原样保留，含 24×24 原始分支） | `build/mobile-portrait/m1-r1/terminal-panel-integration.patch`（sha1 `018b7cc0…`，base 文件 sha1 `176d91be…`） |
| `lib/ui/composer/composer_toolbar.dart` | `ComposerToolbar.build` 增加 `touch`（`MobileLayout.isCompact(queryWidth, …)`，用 composer 容器宽，不动 384/576/672 断点）；三处 `_Chip` 传 `compact`（minHeight 48/minWidth 44、padding 8）；`_Submit` 传 `compact`（48×48、图标 18）；宽屏路径参数默认 false，原尺寸原样 | `build/mobile-portrait/m3-1-r1/composer-toolbar-integration.patch`（sha1 `9019a081…`，base 文件 sha1 `f7b458b4…`） |
| `lib/ui/composer/composer_menus.dart` | 新增 `showComposerModeSheet`/`showComposerModelSheet`/`composerManageModelsSentinel`；桌面锚点菜单的 metadata 拉取状态提取为 `_ModelMenuData`（`_ModelMenu` 改为薄包装，桌面行为与 key 不变）；`MobileOptionSheet` 扩展 `optionsBuilder`/`sectionHeader`/`trailingIcon`（option_sheet.dart，mobile 专属文件） | `build/mobile-portrait/m3-2-r1/composer-sheet-integration.patch`（sha1 `f3bdf0fc…`） |
| `lib/ui/shell/shell_layout.dart` | build 内 `compact` 判定；导航钮与 more 钮 compact 时用 `MobileIconButton`（48 命中），宽屏 `ShellIconButton` 原样 | `build/mobile-portrait/m2-2-r1/shell-header-integration.patch`（sha1 `c55d7d0c…`，与 workspace_shell 同 patch） |
| `lib/ui/workspace_shell.dart` | compact 时顶栏 actions（Git chip、终端、工作面板钮）收进任务菜单，菜单项带“已打开/已关闭”激活态标签并处理 `terminal`/`panel` 动作；`_showTaskMenu` 加 `compact`/`usable` 参数；宽屏 actions 原样 | 同上 patch |
| `lib/ui/chat_page.dart` | `_ActionIcon` build 加 compact 分支（48×48，图标 14 不变）；消息操作行可见性逻辑未动；宽屏 28×28 原样 | `build/mobile-portrait/m4-1-r1/chat-actions-integration.patch`（sha1 `b59141f8…`） |
| `lib/ui/settings_center_page.dart` | 窄屏分类列表→详情：新增 `_narrowListMode` 状态（initialSection=='general' 默认兜底时列表优先，深链接直达详情），PopScope 包 Scaffold（详情态拦截 Back 回列表）、AppBar 标题随模式、窄屏 dropdown 被列表替换；宽屏两栏原样 | `build/mobile-portrait/m5-1-r1/settings-sections-integration.patch`（sha1 `95c6a2aa…`） |
| `lib/ui/shell/shell_layout.dart`（M6-2 增量） | `WorkspaceShellLayout` 新增 `bottomPanelFullHeight` 参数：true 时终端抽屉占满 body（含 1px 边框补偿），默认 false 原样 | `build/mobile-portrait/m6-2-r1/terminal-maximize-integration.patch` |
| `lib/ui/terminal_panel.dart`（M6-2 增量） | `TerminalDrawer` 新增 `maximized`/`onToggleMaximize`；compact 头部新增最大化/恢复钮；PTY 生命周期未动 | 同上 |
| `lib/ui/workspace_shell.dart`（M6-2 增量） | 新增 `_terminalMaximized` 状态并传入 drawer/layout | 同上 |
| `test/ui/v2_visual_test.dart` `test/ui/workspace_flow_test.dart` | 视觉捕获/流程测试的面板、终端开关改为双路径（宽屏头部钮 / compact 任务菜单 key `task-menu-panel`、`task-menu-terminal`） | `build/mobile-portrait/m7-r1/all-integration.patch`（全量 diff，sha1 `86bd096b…`） |

理由：审计点名 terminal 标签关闭 24×24（`terminal_panel.dart` 原约 538 行）是手机
最痛触控点之一；终端抽屉 compact 全宽场景低冲突。

接入后应测：`test/ui/mobile/`（24 项）、`terminal_drawer_constraints_test`、
`terminal_keyboard_test`、`terminal_drawer_touch_test`、`composer_ui_test`
（344–1180 五形状 × 140% × 双主题）、`chat_row_dispatch_test`、
`client_settings_test`、`official_detail_test`；宽屏 1180 抽屉头部、Composer
工具行与顶栏应与改动前逐像素一致（宽屏分支未改，仅 compact 分支新增）。

## 冲突与风险

- `terminal_panel.dart` 上游若同样修改（性能/结构侧当前批次未列入该文件），
  三方对比时只需保留“compact 分支 + import 两行”，其余以上游为准。
- `composer_toolbar.dart` 是性能侧 P2-chat 相邻文件（chat_page 内嵌 Composer）；
  本批只加了 `touch` 局部变量、两处构造参数与两个分支，三方合并按行对齐即可。
- `composer_menus.dart` 的 `_ModelMenu`→`_ModelMenuData`+`_ModelMenuBody` 重构
  触及桌面锚点菜单结构，集成时需确认上游未同时重构该文件；桌面行为由
  composer_sheet_test 宽屏用例与 composer_ui_test 守护。
- `workspace_shell.dart` 顶栏 actions 的 compact 折叠在组装侧完成（非 shell 内部
  溢出菜单），上游 P4-shell 若改同段需三方对比；compact 菜单项点选行为
  （终端/面板开关）挂 M7 主流程验证。
- `chat_page.dart` 是性能侧 P2-chat/S2-chat 主战场；本批只改 `_ActionIcon.build`
  单组件尺寸分支与一个 import，集成时按行对齐。
- Composer 触控放大阈值最终为：容器宽 ≥312 且竖屏（h≥w）且 isCompact；
  344 老回归点与横屏键盘验收（voice_preview）均已守护，全量 962 测试绿。
- 全量集成 patch（含全部 mobile 改动 vs 基线）：
  `build/mobile-portrait/m7-r1/all-integration.patch`。
- **性能侧联合复测交接**：本地已执行 `tooling/bench_conversation_state.dart`
  集成后 3 轮并与冻结基准对比（范围完全重叠，无非退化）——
  `build/mobile-portrait/integration/joint-bench-conv.log`。
  请性能侧复核该数据并完成聊天/代码/来源关键基准的正式签字复测；
  一键复测步骤与判定标准见同目录 `perf-signoff-request.md`。
  **结论（2026-09-15 04:5x）：性能侧已复核并签核「非退化」**
  （analyze 0 + 四 harness 全通过 + bench 全量模式带内 5000=285μs/20000=204μs，
  证据 build/optimization/post-integration/，登记于其 master-todolist
  LAST VERIFIED）——本项外部依赖闭环。
- 真机 QA 期间修复的两处过期断言（上游演进所致，非 mobile 回归）：
  `integration_test/task_management_test.dart` 写调用过滤补 `args.isNotEmpty`
  （conversation 拆分新增无参 get）；`integration_test/usage_statistics_test.dart`
  文案"应用统计"→"应用用量"（usage 页改名）。集成后真机 QA：task_management、
  usage_statistics、d2_4_rotation_isolation、streaming_frame_metrics、
  terminal_input_ime（Trime 自动化组词）全部通过。
- `settings_center_page.dart` 是结构侧 S1 重构主战场（上游已拆
  general/update_about 子页）；本批改动集中在 build 窄屏分支与 initState 一行，
  集成时若上游已重写导航结构，需按其最新结构重排 compact 分支（本批语义：
  列表优先、PopScope 分层、深链接直达）。
- 既有 `client_settings_test`（initialSection 直达）不受列表默认影响，已验证全绿。
- `MobileOptionSheet` 已随 M3-2 接线接入业务（composer 模式/模型选择
  `showComposerModeSheet`/`showComposerModelSheet` 与 toolbar 引用选择，
  共 3 处）；2026-09-15 语义批次为其选择行补 Semantics(button/selected/
  enabled)，行为面无变化（仅语义标志），composer_sheet/option_sheet
  测试与全仓回归均绿。
- compact 判定用窗口宽减 padding 替代容器宽仅在终端抽屉（全宽 bottomPanel）
  场景使用；Composer 接线使用其容器宽（queryWidth），符合不变量 6。
  后续接入其它容器时必须改用 LayoutBuilder 约束。

## 已测

- worktree 独立：`flutter analyze` 0 问题；mobile 19 + 回归（composer_ui、
  drawer constraints、terminal_keyboard、predictive_back）全绿
  （`build/mobile-portrait/m3-1-r1/final-tests.log`、
  `build/mobile-portrait/m1-r1/final-tests.log`）。
- 基线（未含本批）201 项协议/UI 测试全绿（`build/mobile-portrait/m0-baseline/`）。
- 截图 before/after 390（`m1-r1/captures/`），已打开人工检查。

## 状态

**待集成**（工作区独立通过 ≠ 已集成）。集成窗口需与性能/结构侧协调，
写回主目录前先对齐 `settings_center_page.dart`、`chat_page.dart` 等上游新批次。
- **2026-09-15 语义 harness 批次回填**：`lib/ui/mobile/option_sheet.dart`
  补 Semantics(button/selected/enabled)（真实无障碍缺陷修复）+
  新增 `test/ui/mobile/semantics_walk_test.dart`（2 测试）。worktree
  全仓 1011 绿 + analyze 0；主目录直接回填（该文件上游零演进，
  diff 仅为 Semantics 包装），回填后主目录 mobile 39 绿 + analyze 0。
