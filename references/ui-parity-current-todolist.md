# UI parity 当前执行清单

## 当前状态 / 未完成索引 / 恢复入口

- GLOBAL GOAL：U01–U26 + V/G。二轮 s1（2026-09-13）：U17–U26 十组本地实现全部完成并登记于下文各节——U17 统计来源独立化+状态机、U18 模式家族反推、U19 设置 1024 居中外壳、U20 顶栏贴右、U21 审查先列表后右侧、U22 撤销防重、U23 模型页一体容器、U24 官方多步向导（替代导入弹窗）、U25 下载阶段化反馈+isolate 解压、U26 通知内嵌。版本 0.1.0+11。整体未完成：所有 U17–U26 的真机同态验证（E2）、U24 第一步品牌图资源对照、r5-1、E4。
- LAST VERIFIED：analyze 0 问题；全量 flutter test 通过（含本轮新增 usage_plan_selection 4、usage_page 2、U18/U19/U20/U21/U22/U24/U25/U26 回归更新）。旧"引导=导入弹窗"用例已按 U24 契约替换为向导流程验收。
- RUNNING PACKAGE：0.1.0+11 x64 release 已构建并冻结（SHA256 `0e2a2c364e764a1ea47633e902db68c41a4b3c612a2969acb57a6d1b210ead3c`，签名 CN=ALI2580/OU=Zemote，证书 SHA256 `dd8a74ea…63905`，`build/visual-audit/ui-parity-second-pass-20260913-s1/`）。真机覆盖安装（2026-09-14）：设备原装 debug 签名包，`install -r` 同签名覆盖，三台模拟器（16448/16480/7555）读回 base.apk SHA256 一致 `74a6ada500c106a8595c7f5a3412e14a8c8b8520d065e587929019428b3b5aae`（同源码 0.1.0+11 debug 签名 x64 变体）；arm64 实体机包待设备接入。r5b 前包（`ad80ed…`）已历史化。
- SOURCE：HEAD 9975a68e + dirty + r5/r5b + 二轮 s1 增量（新增 `lib/state/usage_plan_selection.dart`、`lib/ui/onboarding_wizard.dart`、`lib/voice/voice_download_state.dart`、`test/state/usage_plan_selection_test.dart`；改动 `lib/protocol/conversation.dart`、`lib/state/{client_preferences,app_sessions,composer_usage 无改动,composer_controller 无改动}.dart`、`lib/ui/{usage/usage_page,settings_center_page,workspace_shell,shell/shell_layout,notification_settings_page,voice_model_manager,chat_page}.dart`、`lib/ui/composer/{composer_mode_metadata,composer_menus,composer_toolbar}.dart`、`lib/voice/voice_model_store_native.dart`、`lib/voice/voice_model_store_stub.dart`、`lib/update/app_version.dart`、`pubspec.yaml`、`CHANGELOG.md` 及对应测试）；未提交/推送/发布/清数据。实际单代理实施，无子代理。
- r5-1 审查（本轮静态结论）：`setting get` 是 `providerFamilySelection()`（统计来源候选读取）与设置中心共用的 RPC。ROG 源失败模式为源切换窗口内同一 bridge 的 setting channel 请求超时，ALI 即时成功、ROG 会话 RPC 正常——疑点指向源切换后 setting 通道的 scope/订阅恢复，而非协议编解码。需要真实双远端环境复现（切源窗口抓 RPC 时序），本地无法进一步定位；U17 的候选读取已把该失败显示为可重试错误态而非"无套餐"，不影响其余来源。
- 剩余必需条件：E4 真实验证码挑战（需用户）；U17–U26 真机同态验证与录屏（E2，需双设备与官方页面同态）；U24 第一步品牌图（需官方实际版本页面取证）；r5-1（需真实 ROG/ALI 双源）。
- NEXT（更新 2026-09-14）：五项关键流程已对安装后字节（74a6ada5…）真机复走通过——U17 统计 banner/来源切换控件、U21 变更条→文件列表→右侧 Diff、U24 向导（欢迎/步骤导航/门控/Skills 勾选，资源级选择修复后可用）、U26 通知内嵌、U25 下载进度（字节+进度条连续→解压→已启用，取消回退验证通过）。证据：s1-delivery.md 真机专节 + `build/visual-audit/ui-parity-second-pass-20260913-s1/u2*.png`。剩余：E2 官方同态对照 → r5-1 真实复现 → arm64 实体机 → G 最终候选。恢复后第一步=读本清单头部。

## 判定规则
[ ] 待核查/实施中/已实现待验证/受阻；[x] 原始全部适用条件经主代理独立核验；N/A 必须有版本/平台/门控依据。需求原文保留如下。官方固定基线 references/official-web-baseline.json（2026-09-08）；主 bundle SHA256 f5010766237b56c3f0f8e6b110624d282d5375db62e2257846e2fe90e227469c。

## U17 — 使用统计与套餐来源 [已实现待验证]

- 二轮 s1：已实现（见头部 LAST VERIFIED）。本地路径全覆盖：假服务个人/团队/无套餐/失败恢复、第三方模型不污染账户统计、双来源切换无串数据（合成测试）。剩余：真机同源 Pro 统计展示（需真实连接，条件成熟后验证）；官方统计页来源切换控件同态对照（当前为功能性 UsageSwitch，视觉待官方截图对照）。

### 原始验收条件
- 拥有有效个人 Coding Pro 套餐时，进入使用统计不再提示"当前连接暂无可用的编程套餐统计"；区分账号 Pro 标识/Coding Plan 等级/Start 体验/API Key/自定义供应商/统计接口支持。
- 页面区分初始化、读取失败、未登录、不支持统计、真正无套餐、有套餐无数据、正常有数据；失败有原因和重试；缺值不补 0%/100%/假日期。
- 统计来源独立偏好（官方 sidebarUsageCodingPlanProviderPreference 语义），账户统计不随聊天模型切换丢失；模型设置套餐卡、账号菜单统计入口、设置中心统计入口一致使用正确来源。
- 通过条件：同源真实 Pro 正常展示；假服务覆盖个人、团队、体验、无套餐和失败恢复；第三方模型不污染账户统计；双来源快速切换无串数据。

## U18 — 交互模式语言 [已实现待验证]

- 二轮 s1：已实现——官方取证：`II` 组件的 provider prop → `zZe` → `FYe[family]`（家族 key=claude/codex/gemini/opencode/glm）；官方发送 payload `jOe` 的 `agent=e.agentProvider??'glm'` 与 configProvider（模型供应商）是不同字段。新增 `familyForModeValues`：从桌面 agent 暴露的 mode 选项集合唯一命中家族字典反推身份（= 从已确认能力取身份，不再依赖 `config['provider']` 字符串包含匹配）；provider 推断降级为 fallback；未知自定义模式保留服务端原文；协议 value 不翻译。glm.plan 英文标签更正为官方 `Plan mode`（mode.label.glm.plan）。回归：`mode family resolves from the exposed mode set (U18)`（glm/claude/codex 集合唯一命中、裸 plan 歧义回退、未知保留原文）；composer_ui/menu/features 37 PASS。剩余：真机中英文切换全链路 + 菜单打开时切语言的 E2 验证。

### 原始验收条件
- 按客户端已配置语言展示中文/英文，支持跟随系统；按钮、菜单行、说明、Tooltip、选中/禁用状态、相关错误同步更新。
- Agent 家族身份从已确认能力/会话元数据取得，不用 `config['provider']` 字符串推断；未知自定义模式保留可靠原文，协议 value 不翻译。
- 已知 Agent × 内置/自定义模型供应商 × 中/英文；菜单打开时切语言；重启持久化；模式切换成功、失败回滚、草稿保留与最终发送值正确。

## U19 — 设置中心右侧面板与内容宽度 [已实现待验证]

- 二轮 s1：已实现——官方取证设置外壳=`h-[min(78vh,720px)] max-w-5xl … rounded-2xl`，内容列=`mx-auto flex w-full max-w-5xl flex-col px-4 py-4 md:px-6`（1024px 居中）。修复 `settings_center_page.dart` 右侧 `Align(topLeft)+maxWidth:864` → `topCenter+1024`，一处根因覆盖全部设置页。回归：`settings right pane uses the full centered official shell width (U19)`（1400px 窗口实测居中 1024，旧 864 左贴消灭）。剩余：真机/平板宽屏截图对照（E2）。

### 原始验收条件
- 修复 `settings_center_page.dart` 的 `Align(topLeft)+maxWidth:864` 与 `shell_layout.dart` 标题 Expanded/操作区 Flexible 组合；不得仅增大某个数字掩盖父约束。
- 设置右侧外壳使用全部可用空间；内部页面按官方居中、限宽或分栏；一次修复所有受影响设置页。
- 通过条件：手机、平板横竖屏、侧栏开关、短/长标题、中英文、100%/140%、系统字体缩放；保存实际 rect。

## U20 — 对话顶栏按钮靠右、聊天与辅助面板几何 [已实现待验证]

- 二轮 s1：已实现——根因=外层 Row 的 `Expanded(标题)+Flexible(操作区)` 平分剩余空间，操作按钮停在约 50% 处留 266px 尾部空白。修复：ellipsis+actions 移入标题 Expanded 内部，标题改 tight `Expanded(Text)`，actions 贴 header 右缘（padding 4）。回归：`header actions anchor to the right edge of the task header`（1180px 实测 last.right=header.right-4±2，标题与操作无重叠）。剩余：长标题/窄屏/系统缩放的 E2 截图对照；聊天正文 864/1280 阅读宽度维持现状（官方 `_5e` 同款断点，另行核对辅助面板开关组合）。

### 原始验收条件
- 顶栏右侧按钮对齐可用顶栏最右边，顺序、间距、溢出策略匹配官方；标题弹性填充中间；操作区不留尾部空白。
- 聊天外壳、顶栏、消息阅读列、Composer 分别核对；官方 864/1280 阅读断点保留有依据部分；辅助面板关闭后无残留占位。

## U21 — 审查先列表，再从右侧打开指定文件 Diff [已实现待验证]

- 二轮 s1：已实现——`_accept` 不再默认选中首个文件；摘要展开只渲染文件行列表（basename+目录+增删计数）与加载/失败反馈，内联 `_FileChangeItem`/`_DiffMessage` 红绿块删除；文件行整行可点 + 行内"审查"按钮同语义（均走 `onOpenReview` → shell `_openFileReview` 右侧面板），无 host 时按钮隐藏（降级）。U05 工具调用内联 diff（conversation_work_rows）未动。回归更新+新增：`file rows and the review button open the same panel path`（行点/按钮同路径、摘要无内联 diff）、`loads review payload`（无默认选中）、trimmed/failures 语义对齐；file_changes 四文件 19 PASS。
- 真机复走（2026-09-14，16480 平板，安装后字节 74a6ada5…）：变更条 tap 展开文件列表 → 文件行点击 → 右侧红绿 Diff 同路径打开，全链通过（`u21-panel.png`）。真机轮修复：row `files` 为空时 build 回退 `review.result.items` 渲染文件行（`chat_page.dart` ConversationChangeSummary），`_loadReview` 完成后 setState 重建——修复前真机展开无文件行。剩余：E2 录屏。

### 原始验收条件
- 摘要展开只呈现文件列表；点击文件 → 右侧打开该文件红绿 Diff；切换文件/返回列表/关闭保持读位。
- 删除摘要自动展开与默认选中首项；保留 U05 工具调用内联 Diff；回合变更不用工作区总 diff 代替。
- 右侧详情有标题/路径、选中状态、关闭/返回、加载、错误、重试；覆盖新增/删除/重命名/二进制/空 Diff/大文件/分页。

## U22 — 修改后审查与撤销入口及完整行为 [已实现待验证]

- 二轮 s1：核验已存在实现并补强——`_canRewind` 真实门控（非 running、未 reverted、`actions.canRewindFiles==true`）在摘要头部渲染撤销；无门控不渲染无行为按钮；`applyRewind` in-flight 二次点击本地拒绝不重复写（新回归 `a second apply while one is in flight never duplicates the write`）；预检/单次提交/accepted/duplicate 关闭/rejected 保留服务端消息/stale 预检丢弃的合成服务测试已有。真实远端撤销写操作按契约仅用合成服务验证（不写真实远端）。剩余：真机各入口（首发完成/历史/重连）撤销入口一致性 E2。

### 原始验收条件
- 修改回合后在官方对应位置有明确审查/撤销入口；不可执行时按真实门控展示禁用原因。
- 撤销按官方语义：预检 → 范围/冲突 → 确认 → 单次提交 → 等待确认 → 更新摘要；不自行调用 git reset。
- 失败不假成功、重复点击不重复写、旧响应不覆盖当前页面；撤销写操作用可控服务验证。

## U23 — 模型列表、供应商/模型新增编辑删除全部对齐 [已实现待验证]

- 二轮 s1：本轮补充——模型页双卡布局改官方一体式边框容器（twoPane 单边框 + 左列表 240 + 边框分隔 + 右详情，窄屏保留卡片形态）；家族头通用 box 占位图标移除（官方 bundle 无供应商 SVG 资产，品牌行=文字+badge 形态）。r5/r5b 已验证部分保留：智谱组、套餐卡、unplug→pending→行下徽章、新增/编辑表单、保存语义。新增/编辑/删除/测试连接全部有假服务回归（client_settings_test 36 PASS）。
- 真机查看（2026-09-14，16480 平板，安装后字节 74a6ada5…）：一体式边框容器、文字家族头（智谱/自定义供应商）、BigModel 选中态+绿点启用指示、套餐卡（GLM Coding Pro/续费/升级与配额 badge/四格用量）、模型行（能力 badge+测试+编辑）、添加供应商入口全部按官方形态渲染，真实远端数据读取正常（`u23-models.png`）。剩余：r5-1（ROG 源 setting get 失败阻塞真实读取）、官方同态截图对照（E2）、真实挑战（E4）。

### 原始验收条件
- 覆盖全部入口：导航 → 供应商列表 → 切换详情 → 新增供应商 → 配置 → 新增/编辑/删除模型 → 测试连接 → 失败恢复。
- 逐项登记官方外层一体容器、导航分隔、品牌图标、启用指示、选中态、套餐卡、模型行、能力徽标、操作图标、空态。
- 新增/编辑表单：内联/弹窗、字段顺序、校验文案、保存语义（blur/Enter/显式保存）、失败回滚、Composer 目录联动；r5b unplug 结果徽章保留复验。
- 至少内置个人套餐、体验套餐、自定义供应商的列表/详情/新增/编辑状态；可测写路径过假服务；无完整证据不标 U14/U23 通过。

## U24 — 官方完整引导、第一步视觉、下一步流程 [已实现待验证]

- 二轮 s1：已实现——官方取证（`L$t` 欢迎页、`A$t` 步骤序、`M$t` 步骤导航、footer `onBackStep/onNextStep/onBeginMigration`、onboarding.* 双语 i18n 全量）后新建 `lib/ui/onboarding_wizard.dart`：欢迎页（开始使用 ZCode/数据迁移向导/跳过说明）→ 会话 → Skills/MCP/插件/命令（复用 settings-sync detect 全类别扫描与逐项选择）→ AGENTS.md → 代理设置 → 迁移（`onBeginMigration` 单次提交）→ 完成汇总（已导入/已跳过/失败）。步骤导航左栏高亮当前步；返回/继续保持选择。桌面专属步骤（本地会话历史、AGENTS.md 文件、代理设置）按远控门控显示官方空态文案，不冒充可用。设置中心"引导"入口改开向导；旧"引导=导入弹窗"用例按契约删除并以向导流程验收替代（`onboarding nav entry` 更新）。
- 真机复走（2026-09-14，16480 平板，安装后字节 74a6ada5…）：欢迎页 → 数据迁移向导 → 左侧步骤导航高亮 → 会话步骤远控门控文案 → Skills 步骤真实数据（codexCli 6 项）勾选与「已选择 6 项」全链通过（`u24-welcome2/steps2/select-fixed-crop.png`）。真机轮修复：向导复选框原传行级 key 会被控制器 `_selectionIfImportable` 门控拒绝（无法勾选），改用资源级 `setResourceSelection(resourceKeysFor(row), !allSelected)`（`onboarding_wizard.dart`）。剩余：官方第一步品牌图资源取证、E2 同态对照。

### 原始验收条件
- 不得让"引导"直接打开 SettingsImportDialog；官方欢迎页/第一步/下一步/跳过/完成逐步取证（`L$t`、`A$t`、`M$t`、footer、i18n 线索 + 实际版本核定）。
- 第一步左侧图按用户要求定位对应页面与视觉区域，提取真正的 SVG/图片资源，不用占位色块或生成图代替。
- 有状态步骤流：前进后退保持选择；检测中/空/失败/重试；最终预览与显式开始；步骤切换不重复导入；迁移写操作仅由确认触发。
- 通过条件：欢迎/第一步/中间步/最后一步/完成都有证据；至少连续走一遍下一步与返回；旧"引导能打开导入弹窗"用例被替代。

## U25 — 语音模型大小、百分比、动态进度及解压反馈 [已实现待验证]

- 二轮 s1：已实现——新增 `VoiceDownloadState/VoiceDownloadPhase`（downloading/extracting/verifying）；下载循环按 Content-Length 更新字节与百分比，未知总长显示已下载字节+不定进度条（不卡 0%、不造百分比）；bzip2/tar 解压移入 `Isolate.run`（解压与校验不再阻塞 UI）；解压与校验阶段有独立可见文案；`VoiceModelStore.instance` 共享实例使退出重进恢复进行中进度（同模型重复点击由 `_active` 去重）；管理页事件 250ms 合并节流，进度刷新不再被全目录扫描饿死。回归：字节数/取消/重试/未知总长不定条（voice 全套 16 PASS）。
- 真机复走（2026-09-14，16480 平板，安装后字节 74a6ada5…）：Whisper Tiny `12.0 MB / 112.6 MB` 进度条+字节文案 → 「已下载但未启用」（启用/删除）；SenseVoice `4.4→63.4 MB / 155.5 MB` 连续推进 → 「正在解压模型…」→ 「已启用」（停用/删除）；Zipformer 发起后点取消完整回退「未下载」。UI 不阻塞、多模型状态隔离正确（`u25-*.png`）。剩余：官方资产元数据大小来源核对、E2 连续帧对照。

### 原始验收条件
- 下载前显示可信模型包大小（无可信值显示未知，不硬编码）；下载中显示已下载/总大小、百分比和连续进度条。
- 状态：准备、下载、解压、校验、可用、失败、取消；下载完成 100% ≠ 模型可用；解压/校验有明确反馈且不阻塞 UI。
- 检查 VoiceModelEvents → _refresh 链路的显示饥饿；退出再进恢复进行中状态；重复点击不重复下载；多模型隔离。
- 已知 Content-Length 多段流、未知总长、断网、取消/重试、解压耗时、校验失败、退出重进、切模型全路径验证。

## U26 — 通知与上岛主体内嵌设置右栏 [已实现待验证]

- 二轮 s1：已实现——`NotificationSettingsPage` 增 `embedded`（Column 主体，避免嵌套 ListView 越界；独立页保留 Scaffold/AppBar 供窄屏）；设置中心 `notifications` case 删除 ListTile 二次导航，主体直接进右栏。回归：`notifications body embeds directly in the settings right pane (U26)`（主体控件在右栏、无 AppBar/旧 ListTile、侧栏保持、切页返回挂载保持）。剩余：Android 真机通知权限/上岛行为验收（ColorOS 16 真机条件）。

### 原始验收条件
- 点击设置左栏"通知与上岛"，主体直接呈现在设置右侧内容区，删除 ListTile 二次导航。
- 复用 NotificationSettingsPage 主体支持 embedded，不复制 controller；避免嵌套 Scaffold/AppBar 重复标题。
- 保持通知权限、任务进度、前台服务、系统设置跳转与上岛行为；跳系统设置返回后刷新真实状态。
- 通过条件：控件直接位于右栏、滚动与宽度正确；切页返回状态保留；系统授权返回刷新；无 ColorOS/Android 16 真机时该部分留待真机验收。

## U01 — 侧栏搜索框体与搜索能力 [ ]

- r5更新：U01-A 更正+闭合——实测本地搜索面板本就有遮罩（black54≈0.54），r4"无遮罩"记录系误判；真实差异是强度，官方同页区域实测 ≈0.60，已对齐 `Colors.black 0.6`（command_center.dart）。真机暗色主题复核通过（r5/tablet-search.png）。剩余：E2 其余同态面、片段级真实定位沿用 r3 原生证据。

### 原始通过条件
- 点击侧栏搜索，打开官方对应的搜索框体；核对入口、焦点、关闭、键盘和返回行为。
- 比对搜索范围、数据源、匹配方式、分组、加载、空态及结果选中后的行为；仅把本地过滤框挪进弹窗不算能力对齐。
- 搜索结果跳转遵守 U04 的导航和作用域要求；未知搜索能力先取证，不凭外观补造后端能力。

### 接续与判定

- 历史接续（仅线索，须核验）：| 01 搜索 | 侧栏搜索；`workspace_shell.dart` | 执行提示词 01、官方任务搜索 | 当前为侧栏本地标题过滤；范围/数据源/分组未证明对齐 | 官方搜索框体、数据语义、焦点与第 04 项跳转 | 待实现；未作本轮运行验证 |
- 当前证据：main-search-layerlink-independent.log；main-native-search-layerlink-phone/tablet.log；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：本地实现/合成与原生定位通过；真实来源与官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U02 — 左下角设备切换弹层 [ ]

- r4更新：E1 解除（真实设备切换实测多次，弹层两设备列表/勾选/管理入口真机通过）。剩余：E2 同态对照。

### 原始通过条件
- 以触发按钮为锚点，按真实可用空间确定方向、尺寸和限高滚动，不依赖固定负偏移。
- 少量/多量设备、横竖屏、窄屏、大字号、安全区下均不越界；当前设备、连接状态、分隔和管理入口正确。
- 切换后内容与连接来源一致，旧设备请求不会污染新设备。

### 接续与判定

- 历史接续（仅线索，须核验）：| 02 设备菜单 | 左下角切设备；`workspace_shell.dart` | 提示词 02、官方锚点弹层 | 仍有固定 `Offset(0, -220)` | 锚点定位、数量/方向/字号/安全区不越界 | 待实现；代码已定位 |
- 当前证据：main-u02-search-controls.log；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：本地锚点/来源隔离通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U03 — 平板左侧栏展开/收起过渡 [ ]

- r4更新：E1 解除（真实来源侧栏切换全程无草稿/读位丢失）。剩余：E2 同态对照。

### 原始通过条件
- 按官方依据实现连续的宽度或位移动画，主聊天区域随布局平滑调整。
- 快速反向操作和系统减少动画设置均可用；侧栏切换不丢草稿、不重建会话、不跳阅读位置。
- 通过连续帧、录屏或实际运行判断；两张静态起止图不能证明动画通过。

### 接续与判定

- 历史接续（仅线索，须核验）：| 03 侧栏动画 | 平板开合；`shell/shell_layout.dart` | 提示词 03、官方开合行为 | 当前按 geometry 直接更改布局，未见宽度动画 | 连续动画、反向操作、减少动画、阅读与草稿保持 | 待实现；连续帧未采 |
- 当前证据：main-u01-u04-final.log；main-native-workspace-review.md；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：本地连续动画与状态保持通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U04 — 在当前外壳内切换会话 [ ]

- r4更新：真实来源壳内切换通过（搜索点结果→正确任务壳内打开→侧栏返回原任务，15:07 复测 8s 加载）；真实双来源实切（ROG↔ALI）目录/模型/账号全量换血零污染。发现的订阅超时缺陷归 U15/r4-1，修复后同一流程真机回归通过。剩余：官方同态连续切换对照（低风险，结构已对照）。

### 原始通过条件
- 宽屏/平板点击侧栏会话时，在当前外壳内更新右侧聊天区，侧栏保持稳定，不为每次点击压入完整新页面。
- 验证 A→B→A、快速切换、同设备跨工作区和跨设备切换：标题、消息、草稿、阅读位置、选中态及数据来源正确。
- 窄屏返回栈单独验证，不能用去掉转场动画掩盖仍然叠加页面的问题。

### 接续与判定

- 历史接续（仅线索，须核验）：| 04 会话切换 | A→B→A；`workspace_shell.dart`、`navigation.dart` | 提示词 04 | `_openTask` 调 `openDeviceWorkspace`，按 task 建整页 route | 宽屏壳内替换，窄屏返回及跨来源迟到隔离 | 待实现；历史切换测试不等于壳内语义通过 |
- 当前证据：main-u01-u04-final.log；main-native-workspace-review.md；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：当前壳导航/隔离通过；真实来源末轮重放受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U05 — 编辑工具内联红绿 diff [ ]

- r4更新：E1 解除（真实任务 U06 变更条实测可见）。剩余：E2 同态对照。

### 原始通过条件
- 编辑操作展开后展示文件路径、真实红删绿增和必要上下文，不能仅展示 old_string/new_string 等参数文本。
- 优先使用已确认的 patch/快照。仅有 old/new 时计算该文本范围的差异，不伪造文件全文、绝对行号或不存在的上下文。
- 覆盖重复文本、多次替换、增加/删除、空文本、换行、截断与大内容；原始参数可折叠保留。
- 复用已有 diff 组件；确认聊天工具行实际接入，不以独立审查面板已有 diff 代替本项。

### 接续与判定

- 历史接续（仅线索，须核验）：| 05 内联 diff | 展开编辑工具；`conversation_work_rows.dart` | 提示词 05、官方 patch | 有增删计数和原始输入详情，未见 old/new 文本 diff | 红删绿增、真实上下文、重复/空文本/截断 | 待实现；代码检查 |
- 当前证据：main-native-workspace-review.md；main-final-tests.log（r3）；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：实际内联diff与边界通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U06 — 回合结束文件变更条 [ ]

- r4更新：真实变更条实测通过（ROG 任务内"3 个文件已更改 +9 -6"+撤销按钮，e1-return-original.png）。剩余：E2 同态对照。

### 原始通过条件
参考图片：

```text
D:\WorkSpace\ZcodeRemote\references\assets\turn-change-summary-reference.png
```

- 折叠态左侧依次为箭头、文件数、绿色新增数、红色删除数；右侧按能力显示撤销，匹配圆角、边框、间距和行高。
- 核对 changeSummary 的生成/接收/行分派，回合结束、历史加载和重连后显示正确且不重复。
- 统计归属对应回合，不用当前工作区总 diff 替代；没有变更时按官方门控处理，不强行每轮生成摘要。
- 展开文件列表、查看差异、错误重试与撤销预检有真实数据链路；撤销写操作使用合成服务验证。

### 接续与判定

- 历史接续（仅线索，须核验）：| 06 回合变更条 | 回合结束/历史/恢复；`chat_page.dart`、`file_changes.dart` | 附图、官方 changeSummary | 已有摘要和独立审查面板；本轮未复核几何/数据门控 | 回合归属、无重复、统计布局、撤销预检 | 已实现待验证；复用 D3.1/D3.2 线索 |
- 当前证据：main-native-workspace-review.md；main-final-tests.log（r3）；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：回合摘要/审查链通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U07 — 语音模型加载与识别卡顿 [x]

- r3主代理终审：适用条件通过。真实AudioRecorder冷暖/preview/stop/cancel与FFI worker；可见预览/取消、停止只追加草稿、换来源拒迟到；最终横屏单/六行旧草稿不溢出。剩余：无。

### 原始通过条件
- 实测冷加载、再次录音、实时预览、停止识别和取消，记录模型、设备、耗时与界面帧停顿。
- 检查同步 FFI 模型初始化和 decode 的执行位置；`async`、Future 或转圈动画本身不能证明 UI 不阻塞。
- 按平台支持将重工作移出 UI 执行路径，界面保持可操作、可取消，反复点击不重复初始化。
- 明确模型复用、释放与内存策略；切会话、退出或取消后旧识别结果不得回填新输入框。

### 接续与判定

- 历史接续（仅线索，须核验）：| 07 语音卡顿 | 冷加载/再次录音/识别/取消；`voice_transcriber_sherpa.dart` | 提示词 07 | async 路径内同步创建 OfflineRecognizer 和 decode | 移出 UI 阻塞路径，帧停顿/耗时实测、可取消与隔离 | 待实现；优先下一批 |
- 当前证据：main-native-mic-review.md；main-native-composer-review.md；main-voice-multiline-keyboard-independent.log；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：适用条件通过。原始条件保留，历史计划文字不覆盖上述终审。

## U08 — 未配置语音模型与错误引导 [x]

- r3主代理终审：适用条件通过。missing/downloaded-disabled/corrupt/permission分类与可见恢复入口；模型管理实际下载Whisper Tiny English后恢复识别，默认零自动发送；稀有失败使用受控测试。剩余：无。

### 原始通过条件
- 未下载、已下载未启用、损坏和麦克风权限拒绝，分别有当前可见的提示与可执行入口。
- 无可用模型时能进入模型管理/下载，不把唯一错误反馈藏在 Tooltip 中；下载由用户操作触发。
- 完成下载/启用或权限处理后可恢复语音输入，默认不自动发送识别文本。

### 接续与判定

- 历史接续（仅线索，须核验）：| 08 无语音模型 | 未下载/未启用/损坏/权限拒绝；`voice_input_button.dart` | 提示词 08 | 错误主要在 Tooltip/语义标签；缺可见模型管理入口 | 当前可见提示、主动下载入口、恢复输入 | 待实现；与 07 同模块 |
- 当前证据：main-native-mic-review.md；main-final-tests.log（r3）；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：适用条件通过。原始条件保留，历史计划文字不覆盖上述终审。

## U09 — 交互模式菜单 [ ]

- r4更新：真实来源模式/模型菜单随会话与项目联动实测（Full access/Plan mode、火山方舟与商汤 TokenPlan 按任务切换）。剩余：E2 同态对照。

### 原始通过条件
- 核对每个模式对应的左侧图标、标签、说明、顺序、选中/禁用态和弹层定位、尺寸。
- 触发按钮有图标不代表弹层每一行已对齐；不得全部模式共用一个无依据的图标。
- 切换行为、失败回滚、草稿保留及实际发送配置一致。

### 接续与判定

- 历史接续（仅线索，须核验）：| 09 交互模式 | Composer 模式弹层；`composer_toolbar.dart` | 提示词 09、官方模式目录 | 触发图标按模式不同；弹层行无逐模式图标 | 图标/排序/说明/禁用/锚点与失败回滚 | 已实现待验证；差异待修 |
- 当前证据：main-native-workspace-review.md；main-final-tests.log（r3）；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：模式内容/行为通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U10 — 模型切换菜单 [ ]

- r4更新：真实双来源模型目录切换实测（ROG/ALI 候选与当前值随源切换即时更换）。剩余：E2 同态对照。

### 原始通过条件
- 核对供应商分组、排序、筛选、标签、选中态、锚点，以及官方实际存在且远控适用的搜索/置顶等能力。
- 模型与思考档联动，切换来源后候选和当前值及时同步；失败时保留已确认状态。
- 同时验证“菜单显示的值”和“最终发送的配置”，缺协议依据时不猜。

### 接续与判定

- 历史接续（仅线索，须核验）：| 10 模型菜单 | Composer 模型弹层；`composer_toolbar.dart` | 提示词 10、官方模型目录 | 已供应商分组；排序、搜索/置顶门控待比对 | 有依据能力、思考联动、来源隔离 | 已实现待验证；不推定未知能力 |
- 当前证据：main-global-settings-fixtures-independent.log；main-native-workspace-review.md；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：模型目录/发送联动通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U11 — 底部终端抽屉 [ ]

- r4更新：E1 解除（真实来源连接稳定）。剩余：E2 同态对照。

### 原始通过条件
- 对齐主区域底部抽屉、终端标签、会话名称、活动态、新建/关闭、尺寸与键盘挤压行为。
- 验证输出滚动、输入、中文 IME、resize、连接恢复和终端生命周期；避免错误放入右侧面板。
- 功能使用实际协议实现，写操作用合成服务验证，不能用静态输出框替代终端。

### 接续与判定

- 历史接续（仅线索，须核验）：| 11 底部终端 | 开合/标签/输入/恢复；`terminal_panel.dart`、shell | 提示词 11、官方底部抽屉 | 已有抽屉与合成测试；本轮未复验全部交互 | IME/resize/滚动/恢复与真实只读边界 | 已实现待验证；复用 G1.2 线索 |
- 当前证据：main-native-terminal-ime-phone-replay.log；main-native-workspace-review.md；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：终端/中文IME/生命周期通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U12 — 右侧面板功能与布局 [ ]

- r4更新：E1 解除。剩余：E2 同态对照。

### 原始通过条件
- 枚举官方可访问的页签、工具入口、内容层级、宽度及开合行为，逐项核对真实能力。
- 验证审查、摘要或辅助聊天等实际存在的面板，与主聊天、底部终端之间保持正确独立性。
- 窄屏覆盖、返回、焦点和阅读状态正确，不能以空壳占位通过。

### 接续与判定

- 历史接续（仅线索，须核验）：| 12 右侧面板 | 主辅聊天/审查/摘要；shell、review panel | 提示词 12、官方可访问面板 | 已有主辅/审查/摘要，完整目录与门控待逐一核对 | 工具实际能力、独立性、宽度及窄屏覆盖 | 已实现待验证；页面覆盖未闭合 |
- 当前证据：main-native-workspace-review.md；main-final-tests.log（r3）；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：真实主辅/审查/摘要面板通过；官方同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U13 — 设置中心设备管理与使用统计 [x]

- r4更新：真实设置导航复测通过（真实常规/模型/MCP 页加载）。统计真实数据同态归 V/E2。

### 原始通过条件
- 当前需求按“点击设置左栏后，内容直接展示在设置中心右侧”执行，不只放一个按钮再打开独立页面。
- 宽屏保留设置导航；窄屏合理适配；返回后保留设置选择与浏览位置，设备和工作区数据不串。
- 如用户明确修正为独立页面，以其新说明覆盖本项，记录需求变化，不维护无必要的两套流程。

### 接续与判定

- 历史接续（仅线索，须核验）：| 13 设置设备/统计 | 设置左栏→右内容；`settings_center_page.dart` | 提示词明确内嵌要求 | 两页仍只有“管理设备/打开用量页”再跳转 | 设置内直接展示、选择/浏览保持、数据隔离 | 待实现；代码已定位 |
- 当前证据：main-u13-navigation-final.log；main-global-settings-fixtures-independent.log；main-native-settings-review.md；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：本项内嵌与导航条件通过。原始条件保留，历史计划文字不覆盖上述终审。

## U14 — 模型设置页面 [ ]

- r5更新：U14-A 已实现+真机验证——官方 bundle 取证（js-65 i18n+js-1 EL/OL 静态目录/`$Kt` 分组与 `oqt` 选中逻辑），实现：provider 列表按 id 分组（智谱组品牌行 BigModel/Z.ai/ZAPI，域过滤 providerFamilyDomain；builtin 家族 id 不再泄漏进自定义列表）、家族详情（品牌头+已启用胶囊+连接方式下拉短标签/徽章/团队明细行+官方升级黑胶囊 150% 配额+套餐卡）、套餐卡按官方布局重写（start-plan=今日余额逐模型行/剩余%/进度条/重置日/`126,741,605 / 300,000,000` 分组数字+过期时间含时刻；coding-plan=5h/1w/工具/MCP 瓷贴并修正为剩余百分比——原实现误用已用百分比）、模型行 视觉/500K 徽标、家族行删除按钮隐藏。真机 ALI 数据全对齐（智谱组/7 家自定义与官方逐行一致/GLM Coding Pro 卡/4 瓷贴/模型标签，r5/tablet-models*.png）；体验套餐卡真机数据被 r5-1 阻塞（widget 测试已过）。剩余：r5-1、E4、同态其余字段（OAuth 登录/购买流程为桌面门控，未实现不冒充）。

### 原始通过条件
- 对照官方逐字段、逐操作检查供应商列表/详情、连接方式、模型条目、默认配置、增删编辑和连接测试等适用能力。
- 核实显示门控、读取与保存协议、校验、错误/回滚、持久化及 Composer 目录联动。
- 已有功能优先修复和补验；缺字段/动作证据明确记录，不直接宣称平台不支持。

### 接续与判定

- 历史接续（仅线索，须核验）：| 14 模型设置 | 供应商列表/详情/保存/测试；settings、model catalog | 官方设置目录、E1.2/E1.3 | 已有双栏和协议实现；逐字段/操作/回滚尚未本轮复核 | 门控/数据/增改删/连接测试/Composer 联动 | 已实现待验证；复用历史证据再补缺项 |
- 当前证据：u14/main-review.md；u14-captcha/main-review.md；main-native-settings-review.md；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：本地字段/操作/联动通过；真实挑战与同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U15 — 连接中断感知与恢复 [ ]

- r5更新：U15-A 已实现+双端真机验证——`ConnectionBannerState` 新增 kicked 态，标题"已被其他设备接管"+官方说明文案+重新连接入口（不出现取消恢复），设备目录/设备切换弹层同步显示"已被接管"短标签。真机互踢两方向取证：平板抢 ROG→手机横幅+历史保留+一键恢复；手机重连→平板横幅同样式（r5/phone-kicked.png、tablet-kicked.png、phone-reconnect.png、tablet-back.png）。回归测试 `relay kick shows the official takeover reason and reconnect`。剩余：r5-1（源切换后 setting get 失败，属本条目监控范围）、E3 部分双设备互踢长稳、真实休眠条件项、E4。

### 原始通过条件
- 追踪 relay→bridge→工作区/会话→当前页面的状态传播，区分首次连接、正常、中断、自动恢复、失败、配对失效和主动断开。
- 中断后聊天、设置等受影响页面有可见提示，保留历史和草稿；不能以设备对象存在、monitor 相同或 socket 连接成功表示业务已恢复。
- 自动重连显示准确进行中状态；需要操作时提供重试/重新连接/重新配对等对应入口，防重复点击，失败后保留原因和下一步。
- 复用现有恢复机制，不并行抢连；主动断开不应自动复活；握手、订阅和状态同步完成后再恢复远端操作。
- 故障注入覆盖短暂断网、持续失败、心跳超时、远端断开、配对失效、前后台、重连中切来源和重复重试。已受理但回执不明的消息/命令查状态，不自动补发。
- 记录提示出现、变化和消失的时机。合成通过后，有条件时验证真实网络切换与休眠；不擅自结束真实远端进程制造故障。
- 优先核验已有第 15 项修改和安装证据，针对实际不满意的行为补复现、定位和修复，不先把已有实现全部推倒。

### 接续与判定

- 历史接续（仅线索，须核验）：| 15 连接提示与恢复 | relay→bridge→monitor→聊天/设置；连接模块 | 提示词 15、冻结官方连接实现 | 已补分层状态与固定可见 banner、凭据失效/取消/重试、bridge 同步后恢复可用；保留草稿/历史/表单，阻止断线写入与旧代回调 | 合成与 loopback 通过；真实设备网络切换/休眠、匹配新源码的 QA 安装与官方同态视觉仍待验证 | 已实现待验证（本批源码/合成验收通过）；主代理记录 `build/ui-parity-15-20260912/main-review.md`，截图 `main-captures/` |
- 当前证据：main-native-workspace-review.md；main-final-tests.log（r3）；tablet-product-launch.png（r3）；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：故障/恢复本地及部分真实通过；配对恢复受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U16 — 设置中心全部适用页面与触发行为 [ ]

- r5更新：U16-A 已实现+真机验证——官方"引导"入口取证（`settings.onboarding`=重开引导弹窗/`settingsSync.dialog` 全类别导入），实现：宽屏左栏数据与统计组虚线火箭 CTA 行（非 section，不改变当前页）；紧凑模式下拉追加"引导"项点击即弹窗；导入控制器升级为多类别（detect 一次携带 skills/commands/plugins/mcpServers 全列表，逐类别 root 行+跨类别选择合并为一次 importSelected）。真机 ALI 弹出"导入设置"含真实扫描（claudeCode·技能 4/codexCli·技能 6、来源/目标/方式、0/11），r5/tablet-onboarding.png。剩余：官方同态弹窗逐控件对照、其余页面 E2 同态、E4。

### 原始通过条件
- 枚举官方目录与本地导航，包括常规、外观、模型、插件、技能、MCP、子智能体、命令、钩子、记忆、浏览器、索引库，以及设备、统计、语音、通知等本地入口；其他当前可见页面一并登记。
- 每个页面建立控件覆盖表：入口/门控、初态、触发操作、应出现的页面/面板/弹窗或修改、数据作用域、调用、成功/失败反馈、重新进入的结果、视觉证据和状态。
- 所有按钮、开关、下拉、行点击、菜单、链接和表单均有归属。重点检查跳页方式、立即保存/显式提交、默认值、校验、取消、关闭、删除确认、加载/空态和禁用原因。
- 不能以“可点击”“返回成功”“样式相似”替代动作真正生效；保存类验证持久化及联动，纯动作类验证实际结果。
- 逐页验收视觉与行为，U13/U14 使用更具体条件；本地扩展按需求验证并明确标注，不能冒充官方已有页面。

### 接续与判定

- 历史接续（仅线索，须核验）：| 16 全部设置页 | 下表页面覆盖索引；settings、官方 catalog | 提示词 16，`official-settings-catalog.json` | 历史结构/locale 证据不能关闭逐控件行为验收 | 每页控件初态→操作→结果/作用域→反馈→重入、视觉另判 | 待核查；只建覆盖归属，本批不展开各页 |
- 当前证据：references/ui-parity-settings-control-coverage.md；main-native-settings-review.md；main-runtime-integration-after.log；总体身份和外部恢复入口见 `resume/main-final-audit.md`。
- 当前判定：全部适用页面本地行为/渲染通过；官方逐页同态受阻。原始条件保留，历史计划文字不覆盖上述终审。

## U16 页面与控件覆盖索引
| 页面/本地入口 | 官方对应与门控 | 本轮差异/后续覆盖归属 |
| --- | --- | --- |
| 常规 general | 官方 general，部分字段 win32/远控门控 | 远端开关/代理/终端字段、表单保存/失败/重入；本地设置分开 |
| 外观 appearance | 官方 appearance；本地主题/字号扩展 | 下拉/开关/预览、保存与全应用联动 |
| 模型 modelProvider | 官方 modelProvider；按供应商能力 | 列表/详情/模型编辑/连接方式/测试/增删/保存；第 14 项 |
| 浏览器 browser | 官方 browser；browser-use 插件门控 | 开关实际插件操作、失败与重入 |
| 记忆 memory | 官方 memory | 设置/编辑/清理等实际可用操作、持久化 |
| 子智能体 subagents | 官方 subagents | 搜索/作用域/行/弹层/编辑入口逐控件 |
| 插件 plugins | 官方 plugin；远控支持范围 | 搜索/行/启停/配置/刷新/商店及回流 |
| MCP mcp | 官方 mcp | 搜索/状态/启停/配置/测试等实际可用入口 |
| 技能 skills | 官方 skill | 搜索/行/启停/来源/详情或管理入口 |
| 命令 commands | 官方 commands | 搜索/新建/编辑/删除确认、错误与重入 |
| 钩子 hooks | 官方 hooks | 搜索/模式/开关/列表与新会话生效语义 |
| 索引库 indexing | 官方 indexing | 开关/目录/刷新及实际索引动作 |
| 设备 devices | 本地扩展，无官方同名页假设 | 第 13 项，设备行/添加/编辑/连接/移除/取消 |
| 统计 usage | 官方 usage；按账户/套餐能力 | 第 13 项，来源/tab/范围/刷新/明细/空态 |
| 语音 voice | 本地扩展 | 下载/启用/删除/错误/取消；第 07/08 项 |
| 通知 notifications | 本地扩展/Android 能力 | 开关/权限/系统入口/失败/持久化 |
| 更新 updates | 本地扩展 | 检查/下载/取消/安装/失败与重入 |
| 自动化 automations、电脑控制 computerUse | 官方 catalog 存在，本地未列同名导航 | 远控门控与适用动作待取证，不能直接判“不支持” |
每页须补入口/门控、全部控件 ID、初态/数据、操作/调用、结果、保存/取消、错误/重入、作用域、官方与本地视觉、主代理判定；索引存在不代表控件验收。

## V — 联合视觉与交互 [ ]
- 按契约第 30 节覆盖受影响手机/平板/横竖、主辅面板、深浅、中英、100/140%、键盘/加载/失败/空态。动画连续过程、性能实际运行。逐场景复用或补证，官方同态与合成证据区分。
- r4新增同态素材：官方/本地搜索面板、任务视图、被踢屏、模型设置、MCP（official/ 目录）；搜索遮罩差异登记于 U01。

## G — 最终综合验收与交付 [ ]
- 按契约第 51 节：最终源码 analyze、完整测试、protocol smoke；联合恢复与关键行为；视觉缺口；最终产品 package/version/ABI/signature/hash、覆盖安装/读回/实际路径，冻结与 CHANGELOG/交付记录增量同步。
- r4 修复包未冻结为最终候选；G 需在 U14 智谱套餐卡等闭合后重建并全量复验。

## 停止条件审计

- 二轮 s1 按契约停止条件 B 暂停：U17–U26 十组本地可执行实现+回归+静态取证已全部完成（本文件各节+s1-delivery.md）；analyze 0、全量 946 PASS/1 skip、protocol smoke passed、0.1.0+11 x64 release 冻结。剩余均为真实外部条件：双端覆盖安装读回与关键流程复走（需设备）、E2 官方同态对照与录屏（需官方页面同态）、U24 第一步品牌图资源（需官方实际版本页面）、r5-1 真实双源复现、E4 验证码挑战（需用户）。恢复入口：本清单头部 → 各节"剩余" → s1-delivery.md。

- 真机验证轮（2026-09-14）：设备接入后完成 0.1.0+11 三台模拟器覆盖安装（同签名 debug x64 变体，读回 base.apk SHA256 `74a6ada5…b5aae` 三台一致）并对安装后字节复走五项关键流程全部通过：U17 统计 banner/来源控件、U21 变更条→文件列表→右侧 Diff、U24 向导全链（资源级选择修复）、U26 通知内嵌、U25 下载进度/解压/取消。真机轮发现并修复两处缺陷：U21 row files 空时回退 review.result.items（chat_page.dart）、U24 复选框改资源级 setResourceSelection（onboarding_wizard.dart）；两处修复均随真机验证确认生效。剩余恢复为外部条件：E2 官方同态对照、U24 品牌图取证、r5-1 真实双源、E4 验证码、arm64 实体机覆盖安装。



