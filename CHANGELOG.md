# Changelog

## [0.1.0+11]

### 二轮官方体验修复（U17–U26，2026-09-13）

- U17 使用统计来源独立化：官方 `sidebarUsageCodingPlanProviderPreference` 语义落地——统计页 Coding Plan 来源改为客户端持久偏好与候选切换（Z.ai/BigModel），不再被聊天模型供应商绑定；页面区分加载/候选读取失败（可重试）/未连接（官方 billing banner）/`no_plan`/`not_authenticated`/`not_configured`/正常数据，失败不再伪装成"暂无套餐"。
- U19 设置中心右侧改官方 `max-w-5xl`（1024）居中外壳，移除左对齐 864 上限。
- U20 顶栏操作按钮贴右缘：修复标题 `Expanded` 与操作区 `Flexible` 平分剩余空间导致的尾部空白。
- U26 通知与上岛主体内嵌设置右栏，删除二次导航；独立页保留窄屏路由。
- U18 交互模式文案按桌面 Agent 暴露的模式集合反推家族（官方 `FYe` 键序），自定义供应商不再回退英文；GLM 计划模式英文对齐官方 `Plan mode`。
- U21 回合文件变更摘要展开仅列文件，点击行/审查按钮统一从右侧面板打开指定文件红绿 Diff，不再默认内联展开。
- U22 撤销入口保持真实 `canRewindFiles` 门控，补 in-flight 二次提交本地拒绝回归。
- U23 模型设置两卡布局改为官方一体式边框容器（列表+内部分隔+详情），移除家族头占位 box 图标。
- U24 引导入口改为官方多步骤向导（欢迎页/分类步骤/迁移/完成汇总），不再直接弹导入对话框；桌面专属步骤按远控门控显示说明。
- U25 语音模型下载分阶段反馈（下载字节/百分比、解压、校验），未知总长显示已下载字节与不定进度条；bzip2 解压移出 UI isolate；模型存储共享实例，退出重进不丢进度。

## [0.1.0+10]

### r4（2026-09-13 下午，真实来源恢复与订阅泄漏修复）

- 修复会话订阅退订失败被静默吞掉导致的注册泄漏：同一连接返回先前会话时 `subscribeConversationV4` 永远等不到 ack（60s 超时，源切换后必现）。现在退订失败会登记泄漏的 subscriptionId，下次订阅同会话前先补发退订；会话加载失败的重试按钮增加进行中反馈。
- 真实来源验证恢复：ROG 原始长任务重放（搜索→壳内打开→返回）、模型/MCP 只读设置真实数据、ROG↔ALI 双来源实切隔离、被官方页抢占后的重连恢复，均已在覆盖安装的修复包上实测通过。
- 官方同态对照新登记差距：模型设置缺内置智谱供应商组与套餐卡（余额/过期/升级）、设置缺"引导"入口、被踢原因未透出、搜索面板缺背景遮罩。详见 `references/ui-parity-current-todolist.md` 与 `build/visual-audit/ui-global-20260913-resume/r4-delivery.md`。

### 官方 UI 对齐与交互修复（U01–U16，2026-09-13 候选）

- 搜索接入已确认的数据源与任务定位；设备菜单按触发器和可用空间定位；侧栏连续动画与当前外壳内切换会话保留草稿、阅读位置和来源隔离。
- 聊天编辑工具显示真实范围的内联红绿 diff，回合摘要采用 turnHeader.fileChanges 并正确处理零变更、缓存、文件审查和撤销门控；代码主题、行号、换行、字号与全文复制共享实际渲染链。
- 修正底部终端在横屏键盘下的高度、重复避让与释放；主辅聊天、审查/摘要面板和模型/模式目录保持独立状态并消费设置刷新。
- 离线语音初始化与识别工作移出 UI 执行路径，补充模型/权限错误入口、录音状态、真实识别预览和取消，停止后仅写入草稿，取消或切换来源后拒绝迟到结果。
- 设置中心设备与统计内嵌；统一导航、宽窄布局和双语文案。模型设置补齐官方字段、提交时机、连接测试和本地 CAPTCHA adapter；插件、技能、MCP、命令、钩子和子智能体按来源及能力执行已确认协议，写后读回并刷新已有和后续 Composer 目录。
- 修复插件 workspace 继承与配置增量、详情失败重试、命令表单独立目标、钩子整表并发与工作区信任、统计页返回后的 tab/range/滚动保持。
- 修复真实目录中不可见的设置图标与 MCP 五项列表固定高度裁切；搜索按选中片段翻阅历史并定位实际正文，保留回合手动折叠，拒绝错误历史代次的无界重试。

r3本地检查与可执行原生验收已完成，按契约50B保留全局未完成；有效配对、官方同态及真实验证码仍待外部条件。最终源码、回归、原生验证及恢复步骤见 `references/ui-parity-current-todolist.md` 和 `build/visual-audit/ui-global-20260912-resume/main-final-audit.md`。本条不改变版本号、不执行发布。

### D3.2（第三十九批，官方撤销弹窗对照，阶段 d32-rewind-copy）

- 撤销确认弹窗说明行文案对齐官方（「已被其他进程修改」）；官方真实弹窗（可安全撤销/不能安全撤销分组+撤销文件按钮）逐项对照一致。

### D3.3（第三十三批，官方终端结构修复，阶段 d33-terminal-drawer）

- 终端由侧工作面板 tab 迁出为官方结构的主区域底部抽屉（shell_layout 新增 bottomPanel 槽位）；顶栏新增独立「切换终端」按钮（square-terminal，更正旧「侧面板切换」判定）。
- 新增 TerminalDrawer 官方 chrome：终端标签栏（shellLabel ?? 终端 N 命名、活动 tab 尾随 X、新建、抽屉关闭）；预测返回 LocalHistoryEntry、Ctrl+J 与命令中心 toggleTerminal/addTerminalTab 接线；控制键+输入框保留为触屏客户端扩展。
- 真机验证抽屉打开→terminal channel 真实 create/数据流→dispose 全链（平板 ROG-STRIX）。

### D3.1（第三十四批，changeSummary 官方对齐，阶段 d31-summary-official）

- 撤销按钮迁至摘要卡头部行右侧（官方位置；canRewindFiles/rewindOpen 门控不变）。
- 文件行改官方结构：文件类型图标（新增 Lucide file/file-text/file-code/file-image）+ 名称/目录拆分；官方品牌文件图标以 Lucide 近似记录。

### D3.1（第三十五批，审查面板，阶段 d31-review-panel）

- 「审查」→独立 diff 面板+切文件：FileChangesReviewPanel（文件 tab 栏+活动 X+面包屑+±计数+unified hunks+loading/error/retry+binary/裁剪消息）、FileChangesReviewHost InheritedWidget、shell `_WorkPanel.review` 持有控制器（行虚拟化回收安全）；共享 FileChangesHunksView 组件化；无 host 场景保留内联选择式 diff 回退。

### D3.4（第二十五批，第七轮取证附录二）

- permissionUpdates 项解析：addRules + behavior(allow/deny/ask) + rules[{toolName, ruleContent?}]，respond_permission 全字段闭合。
- workspace_task_list_invalidated 严格 schema；钩子复审 decision 枚举别名跨 chunk 未定义，如实记录。

### D2/D3.4（第二十七批，规则 24 合成实现，阶段 v13-goal-verification-row）

- goal_verification 合成流行渲染落地（GoalVerificationRow：四状态+通过细分+reason/nextAction/迭代号，separator 形态，双 wire 形态识别），挂入会话行分派。
- task_snapshot_invalidated 具名处理（WorkspaceMonitor.handleTaskSnapshotInvalidated：标记→重同步→清除，重复通知合并）。
- 合成测试 10 用例；标记「已实现待真实验证」（视觉与真实流待桌面会话）。

### D3.4（第二十四批，第六轮取证附录）

- respond_permission.response 解析完成：decision allow/deny/escalate/modify + reason/modifiedInput/permissionUpdates。
- taskCommand union 四成员确认（send_prompt/enqueue/promote/cancel，accepted|running|failed 状态基座）；goal_verification 完整 schema（synthetic 流行，dc={nextAction?,passed,reason}）。

### D3.4（第二十三批，取证）

- 官方 client-command union 七成员 schema 全解析（respond_permission/respond_elicitation/respond_workspace_hook_review/send_prompt/enqueue·promote·cancel_task_command）与流通知类型（goal_verification/task_snapshot_invalidated 等）。
- 本地覆盖对照落档：resolveInteraction 与钩子四命令覆盖 respond_* 族；inputRouting/服务端队列覆盖 task_command 族；goal_verification 渲染待真实流取证。

### 设置中心（V1.3 第二十一批，阶段 v13-hooks-plan-locale-official）

- 套餐卡用量 tile 标签官方化（5h 用量/1w 用量）；钩子行 matcher 空显示「匹配全部」；钩子列表补官方「Hook 配置变更将在新会话中生效。」提示。
- 钩子写链路经官方 qXt（saveHooks 全量数组写）交叉验证，实现逐字段一致。

### 设置中心（V1.3 第二十批，阶段 v13-commands-locale-official）

- 命令表单对齐官方全规格：标题+描述行、可选标签、四字段官方占位符、校验文案拆分（长度/字符/提示词必填）。
- 删除确认改官方文案（删除命令 + 确定要删除命令「{name}」吗？此操作无法撤销。），保留两步确认语义。
- 命令行分组标签本地化（用户命令/插件命令）；搁置 wire 重取证九项判定记录（agentSource=zcodeAgent 等）。

### 设置中心（V1.3 第十九批，阶段 v13-empty-cards-official）

- 钩子/插件/子智能体/命令/技能五节空态改为官方组合：标题+描述+按钮整体居中于整行宽虚线卡内（新增 _OfficialEmptyCard）。
- 目录页 chrome 新建按钮移到刷新右侧并改为实心样式（官方位置/样式）；命令节计数去「项」、空态改官方文案+实心新建。
- 修正钩子空态描述错字（以往任务→以在任务）；浏览器注释卡改官方左对齐。
- 浏览器数据按钮平台门控取证记录（官方 web 为 stub、本地无平台服务走门控隐藏分支）。
 · 侧栏同步与辅助功能（2026-09-09）

- 置顶/归档列表记录读取起始修订号，忽略旧请求，防止确认后的成员状态被旧索引覆盖。
- 长按抬起后打开任务菜单，修复原生连续操作失效，保留辅助功能长按动作。
- Markdown 使用 SelectionArea 与 Text.rich，修复可选链接在 Android 辅助功能重注册后导致空树，保留跨段落选择复制。
- 368 项测试、静态检查、153 张渲染、双 MuMu 原生流程和覆盖安装通过；183 文件源码与 APK 已归档。完整待办和开发规范见 references/v2-progress-todolist-2026-09-09.md。

## 0.1.0+9 · 额度自动维护阶段（2026-09-09）

- 接入可见额度界面共享轮询、前台恢复、自动机会申请、外部重置完成及历史已读；来源/重连/迟到和旧额度查询保护贯通。
- 按官方时序显示自动处理/完成状态，并在同一来源的多个视图间去重完成动效；减少动画设置有效。
- 新增本地启动级额度只读验收模式，用同一 APK 核查真实桌面数据；全部额度写操作在合成服务验收。
- 363 项测试、静态检查、双 MuMu 原生额度/统计及覆盖安装通过。实际辅助功能树问题继续排查；完整证据见 references/v2-maintenance-acceptance-2026-09-09.md。

## 0.1.0+8 · 使用统计阶段（2026-09-09）

- Composer“更多”接入完整使用统计页面；应用累计与近 7/30 天数据分别读取，套餐统计按供应商/组织/项目隔离。
- 新增累计活动、52 周热力图、模型/工具趋势、积分及分段明细、固定 7 天健康度和模型用量环图；复用独立 MCP 和重置对话框。
- Android 返回 IANA 时区；修正页面首次读取触发底层 Composer 构建期更新，以及窄屏大字号更新时间溢出。
- 当前阶段最终构建/验收信息见 references/v2-statistics-acceptance-2026-09-09.md；全局 Goal 继续推进。


本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added
- **插件节官方 chrome 对齐（2026-09-12）**：插件节重写为官方 chrome（计数/搜索/已安装/刷新）+官方空态三行卡（浏览插件按钮联动插件市场），行保留已验证 setPluginEnabled toggle；MCP 节官方行差异（stdio 描述/启停）因 wire 未捕获记录不实现。阶段 `v13-plugins-official` 双端同哈希。
- **钩子节官方空态对齐（2026-09-12）**：新建按钮移至「已安装」行右侧；空态卡改官方三行结构（尚未安装钩子/描述/内建新建按钮）。阶段 `v13-hooks-official` 双端同哈希。
- **常规语言徽章与外观描述行对齐（2026-09-12）**：语言徽章改官方「中文简体」；外观节七行补官方描述（界面主题/界面字号/代码字号/浅色·深色代码主题/显示行号/长行自动换行），`_row` 支持可选描述行。阶段 `v13-appearance-desc` 双端同哈希。
- **套餐卡官方日期行与剩余额度卡组（2026-09-12）**：供应商详情套餐摘要卡接入只读 getEntitlementSnapshot（EHt 续费优先/同年省年份日期行；5 小时/每周/工具调用/ZCode MCP 额度卡，百分比+重置日期，缺值 --）；管理/解绑 wire 未捕获不实现。阶段 `v13-provider-plan-card` 双端同哈希。
- **供应商详情套餐摘要卡（2026-09-12）**：详情卡连接方式下方按 E2.1 只读 pricing 渲染订阅产品摘要（标题+升级入口+权益），无订阅不渲染；阶段 `v13-provider-plan` 双端同哈希。
- **模型设置官方双栏重排（2026-09-12）**：按官方截图重建——左栏供应商列表（智谱/自定义供应商分组、行 icon+名称+状态点、选中态、添加供应商）；右栏选中详情卡（名称+已启用 badge+连接方式下拉+操作与删除错误行）+「模型列表」组+添加模型；无 provider 时右栏回退既有 family 连接方式列表；写链路与 E1.3 prep 失效不变。阶段 `v13-provider-twopane` 双端同哈希。
- **常规节官方 locale 全量校对（2026-09-12）**：从落盘 IntlProvider 中文块逐键校对——修复交互行为下拉直接显示原始值 `queue/guide`（改队列/引导），对齐提问自动继续/完整保留模型 I/O/显示思考过程/显示待办/分组探索工具/分组终端命令/分组文件更改/自动归档旧任务/归档保留时长九组标签并补官方描述行、继承系统终端 Profile 与增强 Find 和 Grep 描述、HTTP 代理三输入描述与 placeholder 官方全文；写链路不变。阶段 `v13-locale-batch9` 双端同哈希。
- **子智能体节官方分组重建（2026-09-12）**：按 js-1 `$5`/`YJt` 分组判定实现内置/插件/已安装三分组、「内置子智能体 N 项」标题、工具 badge（空 tools=全部工具，否则 N 个工具）、计数语义修正（已安装只算 user 行）、搜索过滤作用全部分组；「继承默认」下拉与「新建」无 wire 不实现。阶段 `v13-subagents-batch10` 双端同哈希。
- **账户菜单官方远控结构（2026-09-12）**：移除登录 TODO 占位（官方远控菜单无登录入口，OAuth 为桌面本地服务）；「登出」对齐官方「断开连接/Disconnect」并落地真实行为 `sessions.disconnect`（断开当前远端会话并返回设备页），含行为回归。阶段 `e21-disconnect` 双端同哈希。
- **命令文件新建/编辑/删除（2026-09-12）**：官方远控命令页有新建入口且 `writeCommandFile`/`updateCommandFile`/`deleteCommandFile` wire 在落盘 bundle 明文——CommandsCatalog 三写方法（in-flight 去重、写代次防迟到、成功 list 权威回读、失败保留旧值重试）+ 官方校验表单（name 1-50 `[a-zA-Z0-9_-]`、prompt 必填、空可选省键、重名错误识别、编辑态按官方只要求 prompt）+ 两步删除确认。阶段 `e12-commands-crud`（269 文件）双端同哈希；四批全量 602/602、analyze 0、smoke 通过。
- **设置中心常规节官方结构（2026-09-12）**：按官方四卡结构重建——界面语言+语言徽章、终端卡（继承系统终端 Profile/终端字体/集成终端 Shell（win32 门控，systemService 只读探测）/增强 Find 和 Grep）、HTTP 代理卡（代理/例外/CA 证书，独立保存）、行为卡（交互行为/自动处理提问/模型 IO/显示推理/显示任务清单/工具分组三键）、归档卡；新增 11+5 个 settingService 远端字段解析与逐键 update 保存（trim+dirty+Enter+成功回同步+失败保留重试）。官方无独立「对话」节，相关开关并入常规；钩子节自动处理提问同迁。
- **记忆/索引库/浏览器控制节官方重建（2026-09-12）**：记忆节官方卡片+虚线桌面端提示卡；索引库节官方「代码库」组与官方标签；浏览器控制开关改经 pluginManagement 驱动 browser-use@zcode-plugins-official（与插件管理同一验证写链路），桌面专属「允许不安全证书」按官方 isDesktop 门控移出远控 UI。
- **目录页官方骨架（2026-09-12）**：新增 `_catalogChrome` 共享骨架（作用域 pill+计数+本地搜索+「已安装 N」+刷新+虚线空态卡），子智能体/命令/技能/MCP 四节重建；插件节内联已安装插件行（复用 setPluginEnabled）。无验证 wire 的新建/继承默认/启停按钮一律不实现。
- **钩子管理列表页（2026-09-12）**：更正第三批检索遗漏——官方 `hooksService.loadHooks/saveHooks`（全列表保存）与 hook 行模型在落盘 bundle 内完整可得；钩子节重建为官方管理列表（作用域/计数/搜索/已安装/刷新 + 虚线空态卡 + 行级启用开关），插件来源行按官方 editable 投影保持只读；新建/编辑表单字段已取证留下一增量。
- **钩子新建/编辑/删除表单（2026-09-12）**：`_HookFormDialog` 按 js-1 WXt/UXt/GXt 语义落地——事件固定 7 项（默认 PreToolUse）、类型 process（默认）/command、matcher、命令必填、process 参数每行一个 / command 异步+Shell、高级组（状态信息/超时默认 60/自定义 JSON 对象校验，解析错与对象错分开提示，非法禁存）；空可选字段省键、类型切换摘除不适用键、编辑经 spread 保留 id/location/enabled；删除两步确认走整表 saveHooks，保存失败保留表单可重试，成功经 loadHooks 权威回读后关闭；操作行 Wrap 布局修复确认删除态 22px 溢出。client_settings 28/28、全量 600/600、analyze 0、smoke 通过；阶段 `v13-hooks-form`（APK 67a24f6b…）双端同哈希。
- **F3.2 最终恢复复验（2026-09-12）**：最终代码双端 `.qa` 冷重启阅读恢复 seed/verify 通过（row 450/offset -84，2 页分页，无 conversation command），证据 `build/artifacts/f3.2-final-*-2026-09-12.log`。
- **Command Center 首版**：顶栏 shell 支持官方四 tab 命令面板和 `Ctrl+K`；覆盖 `>`/`#`/`@` 前缀、最近任务、最近文件、新任务、打开工作区、设置、侧栏/终端与添加终端标签；tab 图标和任务相对时间按官方面板对齐。
- **Git 分支只读入口**：顶栏 `GitBranchChip` 仅 Git 仓库显示 branch/dirty/ahead/behind；纯 Dart `GitClient` 只调用 `git.refresh`，失败保留旧值。
- **消息操作行**：用户消息显示 Copy + Edit（entityId 门控），Edit 填充 Composer 可直接修改重发；最新完成助手正文显示 Copy/Fork，Fork 处理 accepted/duplicate、失败、迟到响应和新会话切换；远控下 Feedback 可见性以官方 kX 行为为准（后扩展为可见的 Like/Dislike）。
- **队列编辑与重排**：待发队列支持编辑文本（editQueueItem）和上移/下移（reorderQueueItem），均受 canEditQueue + dispatch.state==queued 门控。
- **工具卡增强**：展开态显示输出截断指示、文件路径芯片和 URL 芯片；思考行流式状态显示单行截断预览。
- **远控设置导航框架**：设置中心添加 modelProvider/plugins/skills/mcp/hooks/usage 占位节，远端 RPC 接入后填充。
- **远控设置只读读取**：新增 `RemoteSettingsController` 读取 `setting/get`，按设备 + 工作区隔离并保护迟到响应；设置中心先填充 modelProvider 与 hooks 当前值，错误可重试，plugins 接入现有隔离插件管理，skills 只读读取 `skills/list`，MCP 只读读取 workspace server statuses。真实远端写入仍未授权。
- **Subagents/Commands 目录**：按官方 `subagentsService.list` / `commandsService.list` 新增设置目录，覆盖加载、空态、失败重试、迟到响应和设备/工作区隔离；命令启停按官方 `setCommandEnabled(command)` 实现，成功后回读，失败保留原值。
- **账户菜单扩展**：添加 Usage/Upgrade（需账户）/Login（未认证）/Logout（已认证）入口。
- **升级套餐只读页**：Upgrade 菜单读取当前 coding-plan family 与官方套餐价格、权益，支持加载、空数据、错误重试；购买提交暂未接线。
- **账户变更缓存保护**：补齐账户变更后额度、来源与引用候选缓存统一失效的本地回归。
- **交互重连保护**：同任务重建订阅后，旧控制器迟到响应不再移除或污染新的交互请求。
- **Hook 审查横幅刷新修复**：本地忽略 Hook 审查请求后横幅立即消失，并补 UI 回归。
- **Hook admission 数据源**：按官方 snapshot 字段显示“N 个工作区 Hook 待审核”，去审核打开 Hooks 设置并主动拉取审查内容；忽略按会话和 bundle 隔离。
- **后台任务取消**：运行中的 Bash/子智能体按官方 `backgroundWorks` 显示和取消，携带 workId、可取消门控、在飞去重与失败恢复。
- **官方视觉配对素材恢复取证**：远控官方连接重新可用，官方会话/账户菜单/用量/设置页面按 1180 宽截图留证，最终配对随 G 阶段构建执行。
- **模型供应商只读目录**：设置中心模型设置节新增官方 model-provider 目录只读展示（供应商与模型行、上下文窗口、推理级别），失败可重试且密钥不外显。
- **模型行编辑**：供应商目录支持添加、编辑、删除模型；保存走官方整包 provider save，成功后权威回读，失败保留旧目录且密钥不外显。
- **自定义供应商删除**：官方 `model-provider` delete 仅开放给自定义供应商；确认后删除、权威回读并刷新 Composer prepared options，失败保留旧目录且不外显密钥。
- **自定义供应商新建**：官方 custom endpoint 表单支持名称/Base URL/API Key/API 格式和初始模型；失败保留表单可重试，成功权威回读并刷新 Composer prepared options。
- **供应商展示顺序**：读取官方 providerIds 顺序并支持上移/下移；保存失败回滚，成功权威回读并刷新 Composer prepared options。
- **Skill 工具行官方形态**：技能调用行显示官方 `skill.name`/`qualifiedName` 与 sparkles 图标，与官方工具卡一致。
- **后台任务与协调器工具行**：TaskOutput/BashOutput 等显示官方 taskId 标识，协调器响应行按官方消息形态渲染。
- **助手消息反馈**：最新完成回复支持 Like/Dislike（乐观更新、再点清除、失败回滚），与官方远控行为一致。
- **套餐来源边界**：无有效订阅的团队产品不再回退到个人余额或猜测团队额度，来源状态明确不可用。
- **双远端恢复隔离**：相同工作区和任务 ID 下，一端重连只处理本端状态，不再影响另一端草稿和配置。
- **附件条状态回归**：覆盖附件上传进度、失败重试入口、文件大小展示和文本预览弹窗。
- **上下文来源排序**：补齐来源条同量时的官方顺序和未知来源末位排序回归。
- **工具详情状态回归**：覆盖截断输出、多条文件路径/链接 chip 与 URL fragment 保留。
- **文件审查错误恢复**：修复展开失败 future 未消费的问题，错误状态和重试后恢复差分已回归覆盖。
- **语音按钮状态刷新**：修复语音输入准备、录音、识别和错误状态不随控制器变化的问题。
- **升级页状态回归**：补齐 Upgrade 只读页加载中、空套餐和无购买入口的渲染验证。
- **账户变更统计保护**：确认账户变更后用量统计缓存也会清空并重新读取。
- **更新下载器**：`UpdateDownloader` 支持下载进度、取消、自动重试和 MD5 校验；设置页接入下载按钮和进度条。
- **语音模型目录迁移**：从旧 Zemote 迁移 6 模型目录（SenseVoice/Zipformer/FireRed/Whisper/Qwen3-ASR/FunASR）和事件通知。
- **离线语音推理联测**：`.qa` 使用 16 kHz mono PCM16 已知音频验证 Whisper Tiny 离线识别输出；该证据区分模型推理链路与后续真实麦克风链路验收。
- **套餐额度重置入口**：新增可用次数、过期倒计时、独立的 5 小时/周额度重置弹窗；请求去重、失败沿用请求标识、已受理但未确认时只查询状态，确认服务端新记录后刷新额度。真实账户只读核查，消耗流程使用合成传输与独立 Android QA 应用验证。
- **长历史阅读恢复**：冷启动按保存的消息 ID 逐页恢复历史，再定位对应消息和可见偏移；加载失败可重试或回到最新，历史已变化/位置已消失时显示明确提示。布局支持未构建的变高消息定位，以及不同宽度和大字号下的恢复。
- **草稿与导航持久恢复**：Android 将文本、原子引用、附件元数据、配置草稿、任务位置和面板/阅读状态加密保存，并保留上一个有效快照；重启不自动发送，等待回执期间中断会保留核对历史提示。
- **Android 附件持久缓存**：系统选取后在应用私有目录保存并校验内容，支持重启后的预览、准备中取消和显式重新准备；文件不可用时保留附件条目并提示重新选择。
- **隔离 Android QA 应用**：`ZCODE_ANDROID_QA=true` 构建独立 `.qa` 包，使用真实系统选择器、Keystore 和进程重启，发送端为合成服务，不读取 `.dev` 的设备记录。
- **V2 官方输入来源与用量链路**：承接侧栏全任务索引、独立置顶与归档视图、加号菜单、文件/技能/任务/插件引用、Android 附件选择和分块上传，以及 GLM/Start/MCP 额度；新增作用域、失败保留、首发、缓存与布局回归，完整产品/实机验收仍在全局 Goal 中推进。
- **V2 细节校准与上下文用量**：当前会话用量环及弹窗接入真实 `usage.contextWindow`，支持来源组成、缓存命中率和实时刷新；新增 7 项回归，完整 219 项测试、静态分析通过，交付 `build/artifacts/ZcodeRemote-v2-details-dev.apk` 并已覆盖安装到 MuMu。
- **V2 composer 配置与发送闭环**：接入 `prepareWorkspace/configOptions` 和会话配置，支持按供应商分组选择模型、协作模式、思考等级；菜单和门控使用远程选项，显示切换中、失败和配置失效状态。
- **运行与队列**：按 `inputRouting` 显示发送/排队/引导，按 `canStop/stopState` 显示停止；待发队列支持查看、暂停/继续、立即发送和移除，持有队列的发送使用明确确认及队列 ID 校验。
- **composer 回归与交付**：新增 37 项回归，完整 212 项测试通过，静态分析零问题；生成 29 张真实 Flutter 渲染截图。独立 `.dev` 调试 APK 为 `build/artifacts/ZcodeRemote-v2-composer-dev.apk`，包含 ARM64，APK v2 签名验证通过。
- **V2 Flutter 主工作界面**：设备连接后恢复最近任务；项目和任务、搜索、置顶/归档、重命名统一进入侧栏。设备切换位于左下方，头像名字弹出小菜单，设置入口迁入底部。
- **五形态自适应布局**：按实际宽度和文字缩放决定侧栏、并排面板或覆盖面板；避让竖向铰链；辅助面板和主对话在折叠/展开时保持原组件，覆盖面板隔离底层焦点与无障碍内容。
- **客户端设置中心**：持久保存主题、语言、文字缩放、代码字号；整合设备管理、通知与上岛和更新检查。完整官方远程设置仍待迁移，这些客户端设置不替代官方设置。
- **聊天阅读与工作面板**：Markdown 正文、按主题渲染代码、历史分页、用户驱动的最新消息跟随及可见消息锚点；工作面板接入任务状态、变更摘要和辅助对话。
- **纯 Flutter Android 路线**：应用级 `AppSessions` 管理设备连接、工作区桥与任务索引；返回页面和切换设备保留连接，新增工作区任务列表入口和按设备/工作区/任务隔离的内存草稿。
- **Android 预测性返回**：启用 `enableOnBackInvokedCallback`，使用 `PredictiveBackPageTransitionsBuilder`，测试覆盖手势预览、取消和确认返回。
- **返回后台保持监控**：任务监控中根页面返回将 Activity 移到后台以保留 Flutter 引擎，移除最近任务则清理通知服务；已在 Android 模拟器验证后台继续更新。
- **ColorOS 16 / Android 16 任务通知**：通过 AndroidX Core 1.18.0 的 `ProgressStyle` 与 promoted ongoing 请求上岛；聚合多设备任务，区分完成、失败、待处理，通知点击可恢复对应任务，停止显示不停止桌面任务；旧系统回退普通通知。
- **任务通知设置**：支持显式启用、权限结果、系统通知设置入口和 Live Updates 能力状态；服务不在后台擅自启动，不自动复活已取消的通知，处理 dataSync 超时。
- **独立调试包**：`.dev` applicationId 与正式版并存；新增 Keystore/通知的 Android 集成测试，CI 改为编译 Android 原生接口。
- **设备 → 工作区 → 会话导航链路**（批 2）：`DeviceSession`（relay 配对 → bootstrap → 工作区列表，ChangeNotifier 生命周期）与 `WorkspacePage`（连接动画、日志面板、工作区列表、错误重试）；点击设备卡进入工作区选择，打开工作区即进入会话。
- **对话页像素复刻骨架**（对话页规格 §1/§2/§3/§6）：turn 分组与折叠（官方 history-message 模型，运行中最新 turn 展开、完成自动收起、折叠只留总结正文）、turnHeader 触发行（「已工作 {时长}」文案 + chevron 旋转）、官方用户气泡（12px 圆角 + 右上 2px 尖角、surface 底 + hairline、max-w 576）、思考行/工具行/子智能体行/时间线标记/变更摘要卡（「N 个文件已更改」+ `+N -N`）、时段问候空态、composer（墨色发送方砖 + arrow-up）。
- **主题令牌补齐**：`subtlest`（foreground-subtlest 60%）、`messageSurface/messageBorder`（官方 `--color-surface`：深白 5% / 浅黑 4%）、`diffAdded/diffRemoved`（#46bf72/#ff5c5c、浅 #1e8a3e/#e03131）。
- **lucide 图标补齐**：arrow-left / folder / folder-open / alert-triangle（官方 lucide 路径数据）。

### Fixed
- **工作面板页序**：修复任务状态与终端在 `IndexedStack` 中下标反向的问题；窄屏覆盖面板恢复/切换后显示与所选页一致。
- **用量页整页几何**：大标题与“应用用量 / 个人套餐”进入同一内容行，移除 AppBar 重复标题；1180 宽对照确认两 tab 内容宽均为 832。
- **附件条官方形态**：附件卡对齐 48px 官方高度、36px thumbnail、名称/尺寸/状态布局；失败状态携带错误详情并提供红色重试。
- **发送后附件呈现**：用户消息在气泡上方显示官方式媒体缩略和文件 pill；媒体按附件读取接口渲染，不再发送后消失。
- **侧栏选中任务行密度**：按官方远控行为修正 selected 状态——选中行保持标题与时间的只读密度，归档/置顶操作只在 hover 或归档确认时出现；已用 ROG-STRIX 同任务官方成对截图回归。
- **已打开菜单的主题和键盘避让**：菜单在系统主题、字号或键盘尺寸变化后重新读取当前颜色与安全区域；兼顾 Scaffold 已消费的键盘 inset，保留来源字体，不再停留在打开时的旧底色和位置。
- **上下文与额度精度**：按官方紧凑数字规则显示总容量、占用比例和缓存命中率；来源色段只占已用容量，缺少分项时仍显示总占用条；MCP 独立显示日期与额度，修正零/越界时间戳。
- **旧格式团队套餐**：先按已订阅产品或已验证快照解析组织和项目，再查询同一来源额度；来源切换立即移除旧展示，重连清除旧账户缓存。
- **真实用量弹窗对照**：保留上下文与缓存的一位小数，按官方精度缩写容量；补总量进度条并把来源分段限制在已用区，零上下文不显示假 0% 入口。MCP 独立行补重置日期，日期缺失/越界不伪造时间，并校正分隔、间距和数字样式。
- **旧团队套餐来源**：按官方规则解析产品/项目旧键和 `projectId=0`，先查询实际组织与项目，再读取对应额度；源不可用时清除旧账户数据，保留明确刷新入口。重连会清团队身份缓存，迟到解析不能覆盖新套餐。
- **历史分页与触屏阅读**：按官方全局最早行 ID 判断分页，校验响应日志代次和当前游标；新日志不混入旧历史。拖动后的阅读锚点在布局结束后记录，避免下一帧把刚滑动的正文拉回。
- **发送前的异步窗口**：`/plan` 的模式准备阶段也参与发送去重；附件准备时不能提前发出纯文本。保存失败保留输入并阻止提交，已获得接受回执后本地保存失败不伪装成远程发送失败。
- **恢复作用域和迟到文件**：当前编辑优先于迟到的恢复结果；设备移除后，迟到的选择器和存储读取结果不能恢复该设备的草稿、附件、导航或面板；未知的较新存储格式不会被旧版覆盖。
- **引用菜单与官方图标**：文件优先于目录，支持路径关键词、30 秒缓存与重连失效；旧会话候选不能落入当前草稿，保留引用旁中文组合输入下划线。图标提取器沿真实模块转导出解析，修正信息/删除图标并补齐向下箭头。
- **大目录读取和桥接恢复**：修复 RPC 大于 512 KiB 的合法接收分片被丢弃、ACK 缺桥接代次/恢复标识的问题；真实 ROG 文件目录由超时恢复为 6,180 条候选。失效桥接按官方重建 Channel 并等初始化，旧桥迟到帧和旧握手不污染新连接，恢复不再在 15 次后静默停止。
- **协议架构**：移除协议目录的 Flutter 依赖，通知与平台识别使用纯 Dart 实现，独立 `dart run` 可编译并验证完整协议栈。
- **侧栏实时更新**：官方完整索引省略置顶/归档字段时正确取消状态；按数据时间合并标题和未读，旧列表不覆盖较新的远程状态。新增折叠项目未读点、任务切换状态与重复点击保护，修复英文长文案溢出。
- **套餐来源与缺失值**：重连清除可能属于旧账户的额度缓存；来源设置读取失败时保留错误与旧数据、不继续请求旧账户；未配置账户显示空状态。Start 缺失余额不显示假 0%，MCP 在窄屏大字号下独立换行。
- **官方视觉细节**：正文与 composer 统一按 conversation 容器 864/1280 断点限宽，校准输入区最小高度和 28dp 工具条按钮；侧栏项目/任务行收紧、补充数量/时间，顶栏项目紧邻标题。模式采用官方中英文文案，修正深浅主题的完全访问橙色；菜单按实测内容高度向上弹出，避让边缘和键盘，继承当前字体主题。
- **工具与思考行**：优先使用 V4 MCP `display` 元数据，按官方规则拆解服务器/工具名称，未知工具保留明确回退及原名详情；支持展开真实输入、输出、错误，成功行去除重复状态，思考缺时长使用官方“持续了几秒”。补齐 `inputStreaming/pendingApproval` 运行判定和 `subagentType/summaryText` 字段读取。
- **配置与异步作用域**：composer 编辑器和操作由应用按 device/workspace/session 持有；配置串行提交，失败恢复已确认值，迟到响应按代次/服务端 revision 处理，重连与页面恢复不主动覆盖其他任务配置。首发成功同时迁移文本、配置、阅读、布局和导航缓存，即使页面已退出也处理应用缓存。
- **发送与停止回执**：首条文本只随 `createSession(firstInput)` 提交一次；拒绝或超时保留文本，健康超时不自动重发；断线重放保持同一 commandId 以供服务端去重，取消猜测思考等级的自动重试；停止携带当前 foreground execution ID，迟到停止回执不标记下一轮运行。
- **输入法与断点**：composer 使用自身工具栏宽度的 384/576/672 断点；Android 使用多行换行，桌面 Enter 发送、Shift+Enter 换行，并保护中文组合输入及刚确认候选词的 Enter。保留键盘单次避让与辅助对话生命周期。
- **中断的界面迁移**：补齐主入口与聊天页的嵌入/状态接口，恢复可编译状态；统一导航使用应用级会话。
- **切设备恢复**：返回已有任务复用其路由，避免同一会话重复订阅；晚到连接不覆盖最后一次选择，主辅草稿、阅读位置和面板选择按设备/工作区/任务隔离。
- **发送失败保留草稿**：仅接受 accepted/duplicate 回执后清理输入，拒绝回执保留内容，不自动重发。
- **窄屏与浅色布局**：嵌入聊天只由外层计算键盘避让；大字号设置行改为上下布局；修正浅色折叠图标和分隔线透明度。
- **凭据与连接生命周期**：补齐 Android Keystore 通道；内存使用解密后的链接，落盘时加密，Android 加密失败不回退明文；旧 sid 主键迁移到 UUID，重导入同设备更新凭据；并发连接共用操作，握手中退出和失败时释放临时连接。
- **首发和草稿**：普通文本首条消息通过 `createSession(firstText)` 原子提交，避免二次发送；输入变化刷新发送按钮，已确认发送的草稿及时清理，迟到订阅释放监听。
- **正式包联网与备份**：主清单补齐 INTERNET，关闭设备凭据备份。
- **Release APK 构建失败**（根因三个）：①`local.properties` 的 `sdk.dir` 指向错误目录（`D:\SoftWare\Develop` 而非 `Jetbrains\AndroidSDK`），导致 NDK 许可证被判定未接受；②Windows 上 pub 缓存（C:）与项目（D:）跨盘使 Kotlin 增量缓存损坏（`this and base files have different roots`），关闭 `kotlin.incremental` 规避；③`key.properties` 中 `storeFile` 反斜杠被 properties 转义吞掉，改用正斜杠。
- **Flutter analyze**：修正 `DeviceSession` 的失效 switch 模式（`List(value:)` → `final List`）。

## [0.1.0] - 2026-09-08

### Added
- **全新项目脚手架**：clean-room 协议复刻，非 fork。继承 Zemote 的纯 Dart 协议栈（relay 配对 / rpc 帧 / Channel / Conversation V4，120 个测试锚定行为）与官方 Web 客户端逆向知识库。
- **多设备管理**：DeviceStore 支持添加（粘贴远程控制链接）、重命名、移除、最近使用排序；每台设备独立持有连接参数；Android 上 sid/hash 凭据经 Keystore AES/GCM 加密落盘。
- **官方 UI 基础体系**：ZInk 调色板（官方 CSS 变量直译）、ZRadius 圆角表、多设备首页壳。
- **官方资产抓取**：完整下载 /remote/v4 的 CSS（384KB）与 JS bundle（4.8MB）存档，整理出 `references/official-styles.md`（CSS 体系规格）、`references/official-i18n.md`（595 个 i18n 键索引）、`references/official-web-ui.md`（mention 触发/六类目/序列化格式/composer DOM 结构等逻辑解密）。
- **GitHub Actions CI**：push 触发 analyze + test + web 冒烟；tag `v*` 触发三 ABI 签名 APK 构建 + MD5 + Release 上传。

### Changed
- **更新检测机制**：复用 GitHub Releases 检查（版本号三处同步：pubspec.yaml / app_version.dart / update_checker_test.dart），仓库指向 `ALI2580/zcode_remote`。
