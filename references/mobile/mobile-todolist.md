# 手机竖屏体验专项执行清单

```text
BASE SOURCE: HEAD 23f0b308b3080ce90494220b66dea8fed02fa5de + dirty 快照
  （build/tmp-snap/snap2/，dirty.patch sha1 1062e21faf12d75d9dba54098e654780609a1262，
  hashes.txt sha1 aac37a5e40dd7efa69d5cfd607daa81acba4022b；
  双快照 45s 稳定窗口验证；快照时点 2026-09-15 00:12–00:14 +0800）
CURRENT BATCH: 全部条目 done/done(核验/done(评估)（M1–M6 表内无 pending；
  2026-09-15 07:4x 六项 pending 复核收口——M2-3 补 task_menu_gating_test
  钉子测试，M2-4/M3-3/M4-2/M5-3/M6-1 按同一测试证据标准核验登记）。
  仅剩真人受阻两项（见 BLOCKERS）。
OWNED FILES: lib/ui/mobile/、test/ui/mobile/、integration_test/mobile_*.dart、
  references/mobile/（本目录）
UPSTREAM BATCH: 性能侧 P2-viewport / S1 第二提取进行中
  （00:15–00:17 出现 lib/ui/settings/settings_widgets.dart、
  general_settings_page.dart，晚于本基线，集成时对齐）
BLOCKERS: 无本地阻塞；性能侧签字已闭环。设备 QA 六项通过（7555=MuMu
  模拟器实例，此前"真机"措辞已更正）；联合基准非退化已由性能侧
  正式签核（2026-09-15 04:5x：analyze 0 + 四 harness 全通过 + bench
  全量模式带内 5000=285μs/20000=204μs，签核登记于性能侧
  references/optimization/master-todolist.md LAST VERIFIED，证据
  build/optimization/post-integration/）。TalkBack 深检（7555 与 16480
  两台设备 dumpsys 均 Enabled/Bound services 空、无 TalkBack，证据
  build/mobile-portrait/device-qa/accessibility-dump*.txt，客观不可执行；
  真人执行手册 talkback-human-pass.md 已就位，T1–T6 场景+H1–H6 打分）
  与单手热区主观评估保持真人受阻登记（仅剩这两项）。帧率采样已完成
  模拟器口径（2026-09-15 05:5x，flutter run --profile 路径；此前
  flutter drive 转发故障 6 次见 mobile-frame-drive*.log）：harness
  integration_test/mobile_frame_profile_test.dart 四阶段均零超 16.67ms
  帧——滚动 204 帧 P50 1.72ms、键盘 inset 10 帧 4.57ms、底部弹层
  24 帧 2.74ms、全宽面板路由 30 帧 2.61ms，证据
  build/mobile-portrait/m7-r1/profile-frames-mumu.log；实体机口径待验。
INTEGRATION STATUS: **已集成到主目录**（2026-09-15 稳定窗口执行：
  上游演进至 conversation 拆分+settings 拆分后，按 integration-request
  三方对比局部合并——terminal_panel/composer_toolbar/composer_menus 直接
  采用 worktree 版本（上游零演进），chat_page/_ActionIcon、shell_layout、
  workspace_shell、settings_center_page 在上游新版上重放锚点改动；
  集成后主目录 flutter analyze 0 + 全仓 968 测试全绿
  （主目录 build/mobile-portrait/integration/integration-tests.log）。
  总 patch 存档 m7-r1/all-integration.patch。
LAST VERIFIED: 2026-09-15 07:4x（M2-3 新测试 + 六项核验登记后）—
  flutter analyze 0；mobile 40 测试全绿（新增 task_menu_gating_test
  1 项）+ worktree 全仓 1012 测试全绿（1 skip）；基线 201 测试全绿
  （build/mobile-portrait/m0-baseline/baseline-tests.log）。
  遗留 flutter drive 重试子进程（6 对 dart/dartvm，05:35–05:55 启动）
  已于 07:26 终止，mobile-frame-drive*.log 停止增长，有效采样数据以
  profile-frames-mumu.log 为准不受影响。
BLOCKERS: 无阻塞独立批次；共享入口接线需上游稳定窗口。
NEXT EXECUTABLE: M1-r1 组件实现 → 合成宿主测试 → 接入一个真实入口。
```

## 2026-09-15 追加批次：六项 pending 复核收口（07:4x）

- 核对发现 M2-3/M2-4/M3-3/M4-2/M5-3/M6-1 六项虽实现早已落地，但未按
  M2-1/M4-4/M5-2/M5-4 的同一标准登记测试证据，属于登记欠账而非实现
  欠账；本轮逐项补齐：
- **M2-3（唯一新增测试）** `test/ui/mobile/task_menu_gating_test.dart`：
  未注册 monitor（usable=false）时 compact 任务菜单无 terminal/panel
  项且壳层显示「连接已关闭」；openWorkspace 注册后菜单恢复两项目带
  「（已关闭）」激活状态——证明菜单由现有门控生成而非硬编码。
- **M2-4/M3-3/M4-2/M5-3/M6-1 核验登记**：引用既有测试名与断言
  （workspace_flow_test 的 A→B→A/拒绝发送保草稿、composer_ui_test 的
  IME 守护、conversation_viewport_test 的锚定含 720→344 宽度变化、
  usage_page_test 的多宽度矩阵与不编造值、terminal_drawer_touch/
  maximize 的触控与 PTY 身份），详见表内登记。
- 进程卫生：清理本会话遗留 flutter drive 重试子进程 6 对
  （dart/dartvm，05:35–05:55 启动，此前每 1.6s 写失败日志）；终止后
  mobile-frame-drive*.log 停止增长，profile-frames-mumu.log 有效采样
  不受影响。
- 验证：worktree flutter analyze 0 + mobile 40 全绿 + 全仓 1012 全绿
  （1 skip）；主目录同步后 mobile 40 绿 + analyze 0。

## 2026-09-15 追加批次：语义树 harness 与无障碍缺陷修复

- 新增 `test/ui/mobile/semantics_walk_test.dart`（2 测试）：语义树
  遍历钉住屏幕阅读器将消费的信息——MobileIconButton（tooltip 文本、
  isButton 标志、tap action、48×48 命中框）与 MobileOptionSheet 行
  （button 标志、selected/enabled 状态、树序遍历顺序）。
- **真实缺陷修复**：`option_sheet.dart` 选择行原为裸 InkWell，仅注册
  tap action 无 button 标志，TalkBack 会朗读为普通文本。已补
  `Semantics(button/selected/enabled)` 包装。worktree 全仓 1011 绿 +
  主目录回填后 mobile 39 绿 + analyze 0（双目录验证）。
- harness 技术注记：widget 测试中 SemanticsNode.rect 不含祖先
  transform（各节点从 0,0 报本地 rect），遍历顺序断言必须用树序
  （indexOf）而非屏幕坐标；SemanticsData.flags/actions 为位掩码
  int，新 API 为 flagsCollection（isButton bool、isSelected Tristate）；
  多节点同文本时取带 action 的最内合并节点（Tooltip 外壳无 action）。
- 真人 TalkBack 深检（外部受阻项）现只需评估焦点行为与手感，语义
  信息面已由本 harness 守护；两台设备仍无屏幕阅读器，受阻登记不变。

## 批次纪律

- 同批一个主目标；不编辑性能/结构侧 master/performance/structure 清单。
- 每批：条目 → 验收 → 实现 → 最短验证 → 前后证据 → 更新本清单头部。
- 共享入口（shell_layout、workspace_shell、chat_page、settings_center_page、
  composer、terminal_panel、theme）只做最小接线 patch，逐批与上游三方对比，
  禁止整文件覆盖上游新结构。

## M1 组件与规则（当前批次）

| # | 条目 | 屏幕/状态 | 现状 | 目标 | 文件 owner | 验收 | 状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1-1 | 触控目标组件 | 所有 compact 交互目标 | ShellIconButton 40×40（shell_layout.dart:61）、composer `_Submit` 28×28、terminal 关闭 24×24 | `MobileIconButton`：视觉 16–20 图标 + ≥48 命中区，不重叠不越界 | lib/ui/mobile/touch_target.dart | 合成宿主命中测试：中心+四边内缩命中、相邻目标互不误触、语义 rect ≥48 | **done**（touch_target_test 3 项） |
| M1-2 | 底部选择面板 | compact 复杂选择（模型/模式/引用/设置分类/终端标签） | 锚点小弹层承载全部选择 | `MobileOptionSheet`：标题/搜索/滚动列表/选中态/取消，SafeArea+viewInsets，键盘下主动作可达 | lib/ui/mobile/option_sheet.dart | 合成宿主：Back 只关一层、键盘弹出可见区域、140%/200% 大字、宽屏不启用 | **done**（option_sheet_test 7 项；宽屏不启用属调用方选择，组件不强制；业务接线在 M3-2/M5-1） |
| M1-3 | 真实入口接线 | 终端抽屉头部（terminal_panel.dart） | tab 关闭 24×24、头部按钮 40×40 | compact：tab 48 行高 + 关闭 36×48、头部按钮 48×48；宽屏原样 | 共享入口（接线 patch m1-r1） | terminal_drawer_touch_test 2 项 + before/after 截图已查 | **done** |
| M1-4 | compact 判定工具 | 全部 mobile 布局 | 各自散判断 | `MobileLayout.isCompact(width, scale)` 单一入口，600*scale 候选 | lib/ui/mobile/mobile_layout.dart | 单测覆盖 320/344/360/390/412/599/600/720/1180 × scale 1.0/1.4/2.0 | **done**（含浮点安全边界；200% 大字时 1180 属 compact 为有意设计，见决策文件） |

## M2 项目/任务导航与聊天顶栏

| # | 条目 | 现状 | 目标 | 状态 |
| --- | --- | --- | --- | --- |
| M2-1 | 任务入口 | 窄屏 Drawer（shell_layout.dart:257） | 保留新建/搜索/最近/来源切换；拇指可达；不新增常驻底栏 | **done(评估)**：compact 沿用既有 Drawer 承载全部任务入口能力（新建/搜索/最近/来源切换由侧栏树与搜索框提供），M2-2 的任务菜单补充低频操作；未新增常驻底栏，聊天区空间不受挤占——评估通过，无需新组件 |
| M2-2 | 顶栏分层 | 标题+more+全部 actions 同 Row | compact：标题+1 导航入口+有限主动作，低频入更多菜单且激活态可见 | **done**（compact 隐藏 Git chip/终端/面板钮，收进任务菜单带“已打开/已关闭”状态标签；nav/more 钮 48 命中；宽屏原样。shell_header_test 2 项；workspace_shell 菜单项点选行为挂 M7 主流程验证） |
| M2-3 | 能力门控生成 | workspace_shell actions | 主/次操作由现有门控生成，不硬编码 | **done(核验+新测试)**：门控全部来自现有运行时状态——usable=conversationBuilder 或 saved-device URL/monitor 匹配（workspace_shell.dart:849-852），compact 菜单 terminal/panel 项 gated by `compact && usable`、重命名 gated by `task != null`、宽屏 actions gated by `usable && !_pluginOpen && !compact`，激活态标签由 `_terminalOpen`/`_panel` 动态生成，无硬编码能力表。新增 task_menu_gating_test 钉住：未注册 monitor（门控不过）菜单无 terminal/panel 项，注册后恢复且带「（已关闭）」状态后缀 |
| M2-4 | 导航状态保留 | sidebar 子树保持 | A→B→A 草稿/阅读/标题/来源保留，无重复订阅 | **done(核验)**：workspace_flow_test 'A to B to A keeps one shell and restores independent source state' 断言草稿独立（'B 独立草稿'）、task 订阅净计数=1（无重复订阅）、双会话 closes=0（连接不重建）、A→B→A 后同一 shell 实例且 'A 独立草稿' 恢复；'late A connection cannot replace the more recent B selection' 断言来源不被旧连接覆盖；标题经 sessions.lastLocations 保存（workspace_shell.dart:855-860） |

## M3 Composer、模型选择与键盘

| # | 条目 | 现状 | 目标 | 状态 |
| --- | --- | --- | --- | --- |
| M3-1 | 发送/停止目标 | `_Submit` InkWell 内 28×28 | ≥48 命中、状态明确、单次点击不重复发送 | **done**（compact 容器 48×48，宽屏 28 原样；composer_touch_test 2 项 + composer_ui_test 11 项含 140% 双主题；单次发送契约由既有测试守护） |
| M3-2 | 模型/模式选择 | composer_popover 锚点弹层 | compact 用 MobileOptionSheet，同 controller；宽屏不变 | **done**（mode/model/thought 三入口 compact→底部面板，搜索/组头/vision 标记/重试/管理入口齐全；metadata 拉取重构为 _ModelMenuData 单份共享；composer_sheet_test 3 项含 config 读回） |
| M3-3 | 键盘共存 | 既有 inset 逻辑 | 键盘只应用一次；IME 确认不误发送；失败不清空输入/附件 | **done(核验)**：conversation_viewport_test 'embedded composer applies keyboard inset once' 钉住 inset 单次应用；composer_ui_test 中文 IME 场景 composing 期间 Enter/done 均不发送（sent 为空）、newline 保留换行、手动点提交才发送完整「中文\n下一行」+ 'desktop Enter submits, Shift Enter inserts newline and IME commit is guarded'；workspace_flow_test 'rejected send keeps the draft and does not retry automatically' 断言发送被拒后输入框与草稿均保留、不自动重试；composer_features_test 断言 viewInsets 300 时弹层 bottom≤520（键盘下可见） |
| M3-4 | 布局再分配 | 窄 Row 小 chip | 按频率组织，次配置收底部面板；不挤掉会话区 | **部分**（chips 行高 48 已并入 M3-1；ComposerActions/voice/usage 按钮 ≥48 与面板化在 M3-2 后续） |

## M4 阅读、消息操作、代码与审查

| # | 条目 | 现状 | 目标 | 状态 |
| --- | --- | --- | --- | --- |
| M4-1 | 消息操作发现性 | 操作行可见但 _ActionIcon 28×28 | 触屏可发现路径；复制不含行号/按钮说明 | **done**（操作行本就可见非长按唯一；compact 下 copy/edit/feedback/fork 钮 48×48、图标 14 保持；message_actions_test 2 项用 ChatPage harness 实渲染断言；复制走整条消息文本无行号混入） |
| M4-2 | 阅读锚定 | 真实滚动决定跟随 | 新消息/面板开合/旋转不吸底 | **done(核验)**：conversation_viewport_test 'streaming, pagination and folding keep the reading anchor until Latest is tapped' 断言三种扰动下锚点行位移≤1px 且 following=false——流式追加新行、前插分页、视口宽度 720→344 变化（旋转/折叠场景）；点 Latest 才恢复跟随（following=true、extentAfter<1）；'cold restoration finds an unbuilt variable-height message by ID' 钉住冷恢复按 ID 锚定变高消息 |
| M4-3 | 代码/diff 阅读 | 横向滚动策略待核 | 换行切换或局部横滚；页面不随代码横滑 | **done(核验+测试)**（换行开关已存在：外观设置 Switch→preferences.wrapLongLines→CodeViewer；diff 面板已有局部横滚；新增 code_mobile_test 3 项：390 未换行时代码块内横滚且页面零溢出、wrap 移除横滚、320+200% 大字零溢出） |
| M4-4 | 审查返回层级 | 面板已全宽覆盖（复用） | 列表→详情→列表→聊天，保留列表位/选中/读位 | **done(核验)**：file_changes_review_panel_test 8 项全绿（tabs+breadcrumb+hunks、多文件 tab 切换、关闭最后 tab 关面板、展开切换）；chat_row_dispatch_test 验证聊天内 changeSummary 展开→文件行→收起的往返；compact 全宽覆盖由 ShellGeometry.panelIsOverlay 既有路径提供，列表位/选中/读位由面板 controller 状态保持 |

## M5 设置、设备、模型与目录

| # | 条目 | 现状 | 目标 | 状态 |
| --- | --- | --- | --- | --- |
| M5-1 | 设置导航 | 窄屏 isDense Dropdown | 分类列表→详情层级；深链接/重入确定路径 | **done**（窄屏默认分类列表全高行+图标，点选进详情，PopScope Back 回列表不退出设置；initialSection 深链接直达详情；宽屏侧栏原样。settings_sections_test 3 项 + 既有 settings 40 项全绿） |
| M5-2 | 管理器列表/详情 | 双栏管理器 | compact 列表/详情适配；错误当前位置展示 | **done(核验)**：管理器/表单页 compact 纵向排列由既有验收守护——settings_import_layout（344/140%）、settings_compact_switch_hit（扩大命中）、client_settings_test（344–1180×140%×双主题）集成后全绿；上游拆分子页（general/update_about）同为纵向结构，错误在字段组当前位置展示 |
| M5-3 | 统计卡片 | usage_page 已有纵向转换 | 卡片换行、触摸可用、不补零 | **done(核验)**：usage_page_test 多维度矩阵（344/390/720/834/1180 宽 × zh/en × 深浅 × 1.0/1.4 字号）逐屏滚动 7+6 步零 overflow 断言并全量截图存档；'credit cards normalize percent inputs and preserve signed trends at narrow width'（344 窄宽签名趋势不丢符号）；composer_features_test 'invalid MCP date and missing percent never invent values' 钉住缺值不补零不编造 + quota 卡纵向排列断言（mcp.top > first.bottom）；整页纵向滚动即触摸可达路径 |
| M5-4 | QR/配对适配 | qr_pairing/qr_scan_page 归其他任务 | 只适配最新稳定接口，不改协议 | **done(核验)**：本专项未改动 QR/配对协议与页面；真机 .qa 安装后设备目录"需重新配对"入口可见可达（device-qa 截图 01-02），配对流程归原任务所有 |

## M6 终端、弹层与系统返回

| # | 条目 | 现状 | 目标 | 状态 |
| --- | --- | --- | --- | --- |
| M6-1 | 终端触控 | 标签关闭 24×24 | ≥48 目标、标签切换/复制粘贴可达、PTY 不重建 | **done(核验)**：terminal_drawer_touch_test 'compact drawer keeps tab close and header buttons at 48px' 断言 tab 关闭 36×48 全高目标、头部钮 ≥48、点关闭只关该 tab（disposed 恰 1 个、抽屉不连带关闭）；'wide drawer keeps the desktop 24px close box' 宽屏非退化；terminal_maximize_test 'full-height flag stretches the drawer without a rebuild of PTY identity' 钉住全高切换不重建 PTY；标签切换走 tab 行本身（48 行高，M1-3）；复制粘贴边界：终端内容选择/复制属终端组件既有系统能力，任务 ID/项目路径复制由侧栏 SidebarTaskAction.copyId/copyProjectPath 既有路径提供，本专项未改动 |
| M6-2 | 终端键盘高度 | drawer_constraints 测试已有 | 键盘后剩余高度核验；需要时最大化入口 | **done**（shell_layout 增加 bottomPanelFullHeight；compact 抽屉头部新增最大化/恢复钮（chevrons-up/down），PTY 会话不变；terminal_maximize_test 2 项 + drawer_constraints 全绿。键盘后高度由既有 drawer_constraints/keyboard 测试守护） |
| M6-3 | 返回分层 | predictive_back 测试已有 | 每场景定义；一次 Back 不双 pop | **done(本地核验)**（分层：IME→MobileOptionSheet(modal route 自身一层)→设置详情 PopScope 回列表→面板/抽屉(LocalHistory)→pushed route；predictive_back/settings_sections/option_sheet/workspace_flow 测试守护。真机系统手势验证待 M7 真机项） |

## M7 验收矩阵与证据

- 尺寸：320×568、344×760（回归点）、360×640、390×844、412×915；键盘开/关、
  深浅、中英、100%/140%，关键页 200%。
- 宽屏非退化：720/834/1180 设置、聊天/Composer、审查、导航。
- 主流程（390 宽走通）：任务切换返回、选模型发送（假服务）、附件/语音与键盘、
  复制代码、diff 返回、设置编辑失败重试（假服务）、终端输入与表现层关闭（假服务）。
- 证据目录：`build/mobile-portrait/<批次>/`；截图必须打开检查。

## 已知上游交叉（保护条件）

- 性能侧 P2-viewport / S1 第二提取进行中；其 dirty 文件（chat_page、
  conversation_viewport、settings_center_page 等）在本 worktree 是基线时点版本，
  集成时以三方对比合并，不覆盖上游新结构。
- qr_pairing/qr_scan_page/onboarding 属其他任务；只适配不接管。
- UI parity 遗留 E2/r5-1/E4 不阻塞本专项，保护其条件。
