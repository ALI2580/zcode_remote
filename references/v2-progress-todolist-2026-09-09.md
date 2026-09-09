# ZcodeRemote V2 进度、待办与接续开发手册

更新时间：2026-09-09 11:17（香港时间）。本次按要求暂停功能开发，整理当前状态与后续执行方法。

**当前结论：0.1.0+10 已构建、双端覆盖安装并归档；全局目标尚未完成。** A/B/C 已有大量可用实现和阶段证据，后续主要包括第一优先级的联合验收，以及完整工作面板、远程设置/账户、离线语音和应用内更新链路。不要用 APK 数量、测试数量或某个页面正常代替整体完成度。

本文件是接续入口；详细验收状态继续维护在 [全局验收表](D:/WorkSpace/ZcodeRemote/references/v2-goal-acceptance.md)。原始阶段记录保留历史语境，最新状态以本文件、该表和当前代码为准。

## 1. 当前代码、产物与接管状态

| 项目 | 已核实状态 |
| --- | --- |
| 工作目录 | `D:\WorkSpace\ZcodeRemote` |
| 分支 / 基准提交 | `main` / `450164e081549c083ef2bec6c6f6e0635e08513f` |
| 工作区 | 有大量已跟踪和未跟踪改动，均已保留；本轮没有提交、推送或打发布标签 |
| 版本 | `0.1.0+10`，版本声明、更新常量及守护测试已同步 |
| 产品 APK | [ZcodeRemote-v2-sidebar-accessibility-dev.apk](D:/WorkSpace/ZcodeRemote/build/artifacts/ZcodeRemote-v2-sidebar-accessibility-dev.apk) |
| 包名 / 大小 | `com.zcoderemote.zcode_remote.dev` / 124,853,792 字节 |
| 引擎 ABI | 已确认包含 `arm64-v8a`、`x86_64` 的 `libflutter.so` |
| APK SHA-256 | `02bfd62a64cee65bf9e64af660da3515973d5847a6086090f19e775346468813` |
| 开发包签名 SHA-256 | `b020bef5c510b8ce9ba783349f4170d178fc279411ca4042287b1c91151a4857`，与前序开发包兼容 |
| 源码归档 | [183 文件源码 ZIP](D:/WorkSpace/ZcodeRemote/build/artifacts/ZcodeRemote-v2-sidebar-accessibility-source.zip)；[逐文件 manifest](D:/WorkSpace/ZcodeRemote/build/artifacts/ZcodeRemote-v2-sidebar-accessibility-manifest.json) |
| 源码 ZIP SHA-256 | `4d21b611b0c59fc39db82381620b0f80822c1fa0dc4c8b71fb4d2b1b0e1cdad2` |
| 源码状态 SHA-256 | `077d670ad8f14dee8ef484133f5776c3b9942091c20313e876822fceedb3ae78` |
| 完整测试 / 静态检查 | 368 项通过；`flutter analyze` 零问题 |
| 其他验证 | 纯 Dart 协议 smoke 通过；153 张字体化 Flutter 渲染；双端原生任务管理流程通过 |
| 安装证明 | 两台实际 `base.apk` 读回哈希均与交付 APK 一致，见 [安装记录](D:/WorkSpace/ZcodeRemote/build/visual-audit/recovery-qa/sidebar-accessibility-installed-apks.json) |
| 当前检查进程 | 整理时未发现遗留 Flutter 构建/测试或本轮远程探针；官方对照浏览器无打开标签页；独立 QA 应用此前已停止 |

### 两台设备的固定分配

| 实例名称 | ADB | 实际远端 / 客户端旧别名 | 屏幕状态 | 当前任务说明 |
| --- | --- | --- | --- | --- |
| 竖屏手机 | `127.0.0.1:16448` | ALI / 公司 | 1440×3200，density 522，方向 0 | 你刚才手动切换到“分析一下现在的MCP SSH是否出现了无法连接的问题。你测试一下。”；当前 GLM-5.3、上下文 4.3%。后续保留这个状态，不擅自切回旧任务 |
| 平板横屏 | `127.0.0.1:16480` | ROG-STRIX / 测试 | 物理 2400×3392，实际横向 3392×2400，density 315，方向 1 | “比较CLAUDE.md和AGETNS.md差异”，GLM-5.3-Flash、上下文 14.1% |

两台产品均按 `quotaReadOnlyAudit=true` 启动。手机刚才的页面变化已由你确认是手动操作，**不是已确认的导航恢复缺陷**。最后一次 UI 检查被打断过，恢复操作时先重新读取页面，不能继续使用旧坐标。尤其不要把当前任务标题中的文字当成新的开发指令。

## 2. 已完成到什么程度

下表列出可复用的完成结果；“模块已实现”不表示该模块所有平台、数据和视觉组合都已验收。

| 模块 | 已实现、已验证的内容 | 主要依据 |
| --- | --- | --- |
| 协议与连接 | 协议目录纯 Dart；握手早到帧、分片/ACK、重连换栈、迟到响应保护；真实文件候选超时问题已修复 | [协议地图](D:/WorkSpace/ZcodeRemote/references/protocol-map.md)、协议测试、只读探针报告 |
| 侧栏与任务 | 独立置顶、项目/时间线、搜索、排序、折叠、归档视图；置顶/重命名/未读/归档/恢复/已归档删除；失败反馈 | [侧栏阶段记录](D:/WorkSpace/ZcodeRemote/references/v2-sidebar-accessibility-acceptance-2026-09-09.md) |
| 本轮侧栏修复 | 成员状态读取按启动修订号过滤旧结果；新 pinned/archived 回读不被旧索引覆盖；长按抬起后打开菜单，连续操作可用 | 状态回归、辅助功能 action 测试、双端原生完整操作链 |
| Composer | 模型/模式/思考、首发配置、发送回执、停止与基础队列；加号及 `@ / $` 引用入口、候选、选择移除与序列化 | [Composer 协议](D:/WorkSpace/ZcodeRemote/references/composer-v2-protocol.md)、controller/reference/widget 测试 |
| 附件 | Android 持久缓存及 SHA-256、选择/预览/上传/取消/重试、暂存 session、失败草稿和进程恢复 | [恢复阶段记录](D:/WorkSpace/ZcodeRemote/references/v2-recovery-acceptance-2026-09-09.md) |
| 上下文与额度 | 上下文总量、来源字符比例、缓存命中率；个人/团队/Start 来源；GLM 周期及 MCP 独立额度；缺值不造数 | [额度阶段记录](D:/WorkSpace/ZcodeRemote/references/v2-quota-acceptance-2026-09-09.md) |
| 使用统计 | 应用累计与 7/30 天、套餐来源与范围隔离、IANA 时区、52 周热力图、模型/工具/积分/健康度/分布、触屏明细 | [统计阶段记录](D:/WorkSpace/ZcodeRemote/references/v2-statistics-acceptance-2026-09-09.md) |
| 自动额度维护 | 可见时共用 5 分钟轮询、前台恢复、机会申请、外部完成历史、额度重查、已读去重、完成提示和减少动画 | [自动维护记录](D:/WorkSpace/ZcodeRemote/references/v2-maintenance-acceptance-2026-09-09.md) |
| 恢复与阅读 | 加密恢复日志及前一有效快照；草稿/引用/附件/配置/导航/面板；深历史按消息 ID 和可见偏移恢复 | [长历史阶段记录](D:/WorkSpace/ZcodeRemote/references/v2-history-acceptance-2026-09-09.md) |
| Android 辅助功能 | 已定位带链接的 `SelectableText.rich` 重连语义缺陷；正文改为 `SelectionArea` + `Text.rich`；跨段落复制保留 | 最小原生案例、双端重复读取、ROG 真实任务进入用量页后返回 85/85 个标签 |
| Android 已有能力 | Keystore、通知/前台服务、预测返回、键盘 inset、铰链布局基础；历史 ColorOS 上岛实现保留 | [Android 接入记录](D:/WorkSpace/ZcodeRemote/references/flutter-android-integration.md) |

全局表目前整项明确“验收通过”的是 **A3 侧栏远控门控、F3 进程恢复**。其余有很多局部通过，但仍须完成各自剩余条件。

## 3. 建议接续顺序

1. 完成 A/B/C 的同态视觉、手机中文输入和跨面板联合验收，关闭已实现功能的具体差距。
2. 按协议依赖完成 D3 完整 diff/终端/交互请求，再补 D1 顶栏、D2 富消息、D4 队列操作。
3. 逐项迁移 E1 远程设置与 E2 账户；把使用统计纳入完整设置/账户导航。
4. 完成 F1 离线语音、F2 应用内更新，随后统一验证 F4 系统组合。
5. 汇总最终 V1/V2 矩阵，构建和安装最终同代码 APK，完成 G1 审计。

遇到需要真实账户或真机的条件，记录最小缺失条件，继续不依赖该条件的开发。不能把待实现功能改写成“平台限制”来关闭目标。

## 4. 详细 TodoList

勾选规则：`[x]` 表示本行已完成且有证据；`[ ]` 表示仍有工作。原大项没有全部满足时仍保持未完成。

### R0：本次整理与接续准备

- [x] R0.1 核对最新版本、完整测试、静态检查、双端原生日志和实际安装哈希。
- [x] R0.2 冻结 0.1.0+10 APK 对应的源码 ZIP/manifest，保存 183 个源文件的状态。
- [x] R0.3 记录你最后留下的手机任务，区分手动切换与产品故障。
- [ ] R0.4 下次开始前重新读取两台当前页面、连接身份及后台运行项；确认是否有人正在操作同一模拟器。
- [ ] R0.5 任何新改码后使用新的阶段标识和证据目录，保留本次冻结产物。

### P1 / A：连接、侧栏与任务管理

- [ ] P1.1 最终代码做双远端切换/断线/恢复联合检查。保留“先到 Initialize、旧 bridge 迟到、重连重新订阅、超时不重复发送”的回归；每个远端身份必须与运行时链接匹配。
- [x] A1.1 修复置顶/归档新回读被旧全局索引覆盖，补 catalog 与真实 monitor 时序回归。
- [ ] A1.2 在真实只读数据上完成搜索、项目/时间线、创建/更新时间排序、全部展开折叠、归档开关的连续场景。验收：不重复显示置顶项、无错误项目归属、切回后显示状态正确，并保存截图和步骤。
- [ ] A1.3 核查实时列表更新与当前搜索/排序/归档视图组合。验收：晚到请求不回滚成员状态，空来源不擦掉另一来源，当前任务不会因列表刷新误跳转。
- [x] A2.1 双端合成服务原生验证置顶/取消、重命名、未读、归档/恢复、拒绝时保留状态、取消删除及一次真正删除。
- [x] A2.2 修复连续长按，并保留辅助功能 long-press action；两端深色英文 140% 菜单可达。
- [ ] A2.3 收尾图标、任务行密度、菜单位置、确认文案与官方同态对照。远控 `KEt` 的 spinner 是切换/修改中状态；不要直接套用移动首页 `m4` 的运行状态图标。
- [x] A3.1 固定官方远控分支不显示桌面分组/重排/自动化入口；保留客户端设备切换扩展。

入口：[workspace_catalog.dart](D:/WorkSpace/ZcodeRemote/lib/state/workspace_catalog.dart)、[app_sessions.dart](D:/WorkSpace/ZcodeRemote/lib/state/app_sessions.dart)、[task_navigation.dart](D:/WorkSpace/ZcodeRemote/lib/ui/shell/task_navigation.dart)、[workspace_shell.dart](D:/WorkSpace/ZcodeRemote/lib/ui/workspace_shell.dart)。

### B：Composer 输入来源与附件

- [ ] B1.1 完成真实中文软键盘组合输入。覆盖拼音未提交、选字、回车确认、插入 `@ / $`、删除原子引用、焦点恢复；确认不会因选字回车发送消息。当前搜狗 IME 曾报告显示但无实际占用区，仍需独立复现。
- [ ] B1.2 核对文件/目录、会话、技能、插件、能力候选的真实作用域。真实 ROG 曾读到 6,180 文件、15 技能、8 插件，这是当时数据，不是固定预期数量。
- [ ] B1.3 覆盖技能/插件运行时变化、查询失败/重试、快速换工作区/设备、迟到候选和移除后再插入。验收同时检查可见标签与最终序列化引用，不能只看菜单出现。
- [ ] B1.4 做手机/折叠两态/平板两方向、主辅面板、中英和 140% 字号组合。断点按 Composer 自身容器宽度判断。
- [x] B2.1 附件选择、持久缓存、校验、预览、上传/取消/重试、首发 session 和失败恢复已有协议/状态及原生证据。
- [ ] B2.2 最终组合验证多附件、图片/文本/不支持预览的类型、超限/缺文件/校验失败、慢上传中取消、切换与进程中断。当前本地上限为 20 MiB；修改上限时本地和上传约束须一起核查。
- [ ] B2.3 核对官方附件条目、进度、错误重试、预览和发送后的呈现；补完整同态视觉对照。

入口：[composer_references.dart](D:/WorkSpace/ZcodeRemote/lib/state/composer_references.dart)、[composer_input.dart](D:/WorkSpace/ZcodeRemote/lib/state/composer_input.dart)、[composer_attachments.dart](D:/WorkSpace/ZcodeRemote/lib/state/composer_attachments.dart)、[AttachmentPicker.kt](D:/WorkSpace/ZcodeRemote/android/app/src/main/kotlin/com/zcoderemote/zcode_remote/AttachmentPicker.kt)。

### C：上下文、GLM/Start/团队套餐、MCP 与使用统计

- [ ] C1.1 收尾当前上下文的完整/缺分项/缓存/无上下文场景及同任务官方对照。来源条按字符总量计算，并且只占总容量条的已用部分。
- [x] C2.1 个人、Start、旧格式团队来源解析；缓存/失败/迟到保护；手动重置及自动维护已实现。
- [x] C2.2 使用统计两套数据源、应用累计与时间范围分离、套餐范围独立、图表触屏明细已实现并有原生证据。
- [ ] C2.3 补真实 Start 与团队套餐有效数据组合。包含旧产品键、组织/项目变更、无有效订阅、失效来源；缺少真实账户条件时保留“已实现待验证”，不得用合成截图宣称真实对齐通过。
- [ ] C2.4 把用量页接入完整官方设置/账户框架，核对来源选择、套餐身份/到期文案及门控。当前独立页面已有内容，完整设置容器和来源入口未完成。
- [ ] C2.5 收尾整页几何：当前用量内容宽 848 与已研究的官方 832 等差异要在同宽条件下逐项校准，不能只调整单个图表。
- [ ] C2.6 最终验证自动维护在同来源多视图、不同设备、来源切换、前后台与重连下的组合；消费/授予/已读均用假服务。真实桌面只能在额度只读模式下核查。
- [ ] C3.1 核对 MCP 独立额度、日期、说明、三张主卡时的全宽行，以及无当前上下文时的可用套餐入口。覆盖缺值/非法日期，不补 0% 或 100%。

入口：[composer_usage.dart](D:/WorkSpace/ZcodeRemote/lib/state/composer_usage.dart)、[plan_resets.dart](D:/WorkSpace/ZcodeRemote/lib/state/plan_resets.dart)、[usage_statistics.dart](D:/WorkSpace/ZcodeRemote/lib/state/usage_statistics.dart)、[usage_page.dart](D:/WorkSpace/ZcodeRemote/lib/ui/usage/usage_page.dart)。

### D：对话、顶栏与工作面板

- [ ] D1.1 补分支信息和远控适用的顶栏工具入口；先确认数据读取、条件和行为，再显示入口。
- [ ] D1.2 核查顶栏、导航与面板切换在窄屏、常驻侧栏、覆盖面板和主辅会话下的组合；当前项目/任务显示不能替代分支和完整工具能力。
- [x] D2.1 历史分页、深历史定位和阅读恢复已有实现/原生证据；Markdown 选择复制及辅助功能重注册缺陷已修复。
- [ ] D2.2 完成官方富消息：思考/工具调用的结构化参数、结果、状态、文件/链接操作及大字段按需读取。当前原始详情/Markdown 不是完整官方工具卡。
- [ ] D2.3 核对消息复制、编辑或其他官方支持操作的实际门控与协议；确认后逐个实现，不凭桌面截图推定远控都支持。
- [ ] D2.4 主辅会话联合验收：输入、配置、队列、附件、订阅、滚动与面板状态隔离，关闭/重开/旋转/重连后不串用。
- [ ] D3.1 完整 diff 审查：查明文件列表、差异数据、分页/大文件/二进制/重命名状态和相应事件；实现完整可读 diff、切文件、错误重试与状态刷新。
- [ ] D3.2 核对官方允许的文件审查操作，再实现相应确认/失败流程；撤销、写文件等验证全部走合成数据，禁止在真实仓库试点写入。
- [ ] D3.3 终端：查明打开/附着、输出流、尺寸变化、输入、断线/退出、关闭与生命周期的真实协议。键盘、控制键、中文和大输出不能只用静态文本模拟。
- [ ] D3.4 官方交互请求：枚举实际请求类型与响应格式，实现对应输入/确认/取消；处理多请求、任务切换、失效请求及响应失败，避免重复提交。
- [ ] D4.1 在附件/引用/恢复/面板组合后重查配置 → 首发 → 回执 → 停止作用域闭环。
- [ ] D4.2 核查并补齐远控支持的队列编辑、重排、发送方式和快捷键；受 availability/inputRouting 门控，不能仅放按钮。

入口：[chat_page.dart](D:/WorkSpace/ZcodeRemote/lib/ui/chat_page.dart)、[conversation_work_rows.dart](D:/WorkSpace/ZcodeRemote/lib/ui/conversation_work_rows.dart)、[conversation.dart](D:/WorkSpace/ZcodeRemote/lib/protocol/conversation.dart)、[composer_controller.dart](D:/WorkSpace/ZcodeRemote/lib/state/composer_controller.dart)、[composer_queue.dart](D:/WorkSpace/ZcodeRemote/lib/ui/composer/composer_queue.dart)。

### E：远程设置、供应商、插件与账户

- [ ] E1.1 将 [官方设置目录](D:/WorkSpace/ZcodeRemote/references/official-settings-catalog.json) 逐项扩成“远控条件 → 当前读取 → 保存 RPC → 失败行为 → UI → 证据”的映射，不能只根据 `webDefaultVisible` 推定完整适用范围。
- [ ] E1.2 逐页核查/迁移下表内容；每页包括加载、空态、写入确认、失败重试、换设备/工作区隔离。

| 目录 ID | 页面 | 待办判断 |
| --- | --- | --- |
| general | 常规 | 区分客户端本地偏好与远程设置；补远程适用项 |
| appearance | 外观 | 逐项确认远端与本地作用域，不能用本地主题替代远端页 |
| modelProvider | 模型设置 | 供应商/连接/选中来源及保存链路完整核查 |
| memory | 记忆 | 查真实数据、作用域与允许的管理操作 |
| subagents | 子智能体 | 查列表、详情及远控允许的配置操作 |
| plugin | 插件 | 当前有市场与部分目录；补官方管理、状态和错误闭环 |
| mcp | MCP 服务器 | 与额度区分；查配置、运行状态及允许的管理操作 |
| skill | 技能 | 技能管理与 Composer 候选读取是两套验收要求 |
| commands | 命令 | 命令管理与 `/` 能力入口分别核查 |
| hooks | 钩子 | 查作用域、读取/写入协议及远控门控 |
| indexing | 索引库 | 查索引状态、操作和进度协议 |
| browser | 浏览器控制 | 查远控适用条件和设置项 |
| usage | 使用统计 | 复用已实现内容，补完整设置框架与入口 |
| automations | 自动化 | 目录已有本构建不显示的门控记录，保留证据并复核设置分支 |
| computerUse | 电脑控制 | 目录记录 desktop + 灰度门控；不要照搬为远控入口 |

- [ ] E1.3 对供应商/插件/技能等变化联动失效 Composer 候选缓存，核对显示与实际发送来源一致。
- [ ] E2.1 账户头像和名字整体菜单接入官方适用的登录状态、用量及升级等入口；根据账户与远控条件展示。
- [ ] E2.2 核查登录/登出协议和副作用，处理账户变更后的额度、来源与设置缓存失效；自动化写入验收使用假传输。
- [ ] E2.3 保留客户端语言/主题/字号/设备/Android 设置的独立作用域；客户端扩展与远程设置在导航及命名上区分清楚。

入口：[settings_center_page.dart](D:/WorkSpace/ZcodeRemote/lib/ui/settings_center_page.dart)、[remote_profile.dart](D:/WorkSpace/ZcodeRemote/lib/state/remote_profile.dart)、[plugin_catalog.dart](D:/WorkSpace/ZcodeRemote/lib/state/plugin_catalog.dart)、[plugin_marketplace.dart](D:/WorkSpace/ZcodeRemote/lib/ui/plugin_marketplace.dart)。

### F：Android 产品能力

- [ ] F1.1 查旧版语音实现、模型资产与兼容条件；当前 V2 尚无完整语音模块，先确认可复用范围。
- [ ] F1.2 模型管理：目录、下载进度、取消/重试、完整性校验、损坏处理、加载/卸载和删除；下载失败不能标为可用。
- [ ] F1.3 录音识别：权限、设备能力、录音开始/停止/取消、推理状态、错误和资源释放。
- [ ] F1.4 识别结果填入发起时的设备/工作区/会话草稿；切换、退出、进程中断后的迟到结果不得写入新会话。默认不自动发送。
- [ ] F1.5 用已知音频验证识别，再验证实际录音路径；区分模型推理成功与麦克风链路成功。
- [ ] F2.1 完成更新通道的可用 UI 和端到端行为。底层已有稳定/Beta 筛选、SemVer、ABI 资产选择与 MD5 文本解析，不能当作下载/安装已完成。
- [ ] F2.2 补下载、进度、取消、失败重试、临时文件清理与校验；安装前核对包名、版本和签名兼容性。
- [ ] F2.3 接入 Android 安装交接、未知来源安装设置与返回后的状态；在 MuMu 用匹配的合成/测试 APK 验证，不能拿不兼容包当升级成功。
- [ ] F2.4 区分 `.dev` 与正式发布资产；当前版本及仓库为 [app_version.dart](D:/WorkSpace/ZcodeRemote/lib/update/app_version.dart) 中实际值，不能沿用旧 Zemote 仓库名称或旧版本常量。
- [x] F3.1 草稿/附件/配置/导航/阅读/面板的进程恢复已阶段验收通过。
- [ ] F3.2 最终版本复验恢复，重点覆盖新增终端、审查、语音等模块后的状态保存；不要给每次文本流式增长都强制覆盖用户阅读位置。
- [x] F4.1 修复当前已复现的富文本链接辅助功能树问题，保留双端最小复现和真实 ROG 返回证据。
- [ ] F4.2 完成折叠/旋转、键盘、预测返回的预览/取消/确认，以及主辅/覆盖面板组合。
- [ ] F4.3 完成通知点击、前后台、任务结束与进程重建后导航的联合验证；保护已有通知服务与上岛逻辑。
- [ ] F4.4 取得 ColorOS 16 / Android 16 真机组合证据。MuMu API 32 的回退结果不能代替专属系统行为验收。

### V / G：最终视觉、隔离与交付

- [ ] V1.1 用最终代码完成五种形态 × 深浅 × 中英 × 100/140% 基础矩阵；再覆盖键盘与主辅面板、加载/错误/空态等必要状态。现有 153 张图只是已覆盖组件的回归集，不是全部笛卡尔组合。
- [ ] V1.2 与官方同远端、同任务、同滚动位置、同主题/字号、等效可用宽度配对。现有官方部分截图 DOM 宽 1723、输出宽 1664，有裁切，不能据此宣称整页像素一致。
- [ ] V1.3 收尾侧栏/顶栏、富消息、面板、设置和用量整页的结构、颜色、间距、图标、状态及文案；可明确记录平台字体栅格差异，但结构差异要修。
- [ ] V2.1 完成 ALI/ROG 两个独立远端的最终切换、重连、配置、草稿、附件、阅读和面板联合验证；相同 ID 隔离同时保留合成回归。
- [ ] G1.1 所有适用必需项逐项检查证据；未知门控继续核查，缺外部条件继续留待验证。
- [ ] G1.2 最终同代码完整检查、ARM64 + x86_64 开发包、兼容签名、双端覆盖安装及关键流程。
- [ ] G1.3 更新 CHANGELOG、实施记录、功能清单、全局验收表、阶段记录；归档 APK/源码/manifest/哈希/日志/截图。
- [ ] G1.4 只有全部完成条件满足后才关闭全局 Goal。当前不能关闭。

## 5. 开发规范与禁止事项

### 5.1 依据与模块边界

1. 开发前先读 [project-cognition 技能](D:/WorkSpace/ZcodeRemote/.agents/skills/project-cognition/SKILL.md)，再按模块读仓库根目录的最新参考文档。
2. 以已确认产品范围、当前代码和固定官方 JS/CSS/图标为依据。旧 Web 宿主方案已经被纯 Flutter 路线取代；不要恢复旧路线。
3. `lib/protocol` 保持纯 Dart。Flutter `ChangeNotifier`、页面状态和平台交互留在业务/界面层；Kotlin/MethodChannel 只接系统能力。
4. 共享问题修在共享组件或协调器，不在每个页面重复打补丁。当前状态管理沿用 ChangeNotifier/ValueNotifier，不为单个功能引入新的整套框架。
5. 作用域键覆盖设备/transport、工作区、会话，以及适用的供应商/组织/项目/范围/时区。服务端 task ID 相同不意味着同一个对象。
6. 新异步路径明确生命周期：请求去重、代次校验、迟到结果丢弃、取消/释放、失败后可恢复。UI 切换时立即换展示来源，旧结果最多填自己的缓存。
7. UI 使用主题 token 和官方图标。涉及 CSS 混色时按实际颜色空间核查；不能随意替换为近似 RGB 叠加。
8. Composer 的 384/576/672 断点看自身容器宽度；壳层侧栏/覆盖面板断点是另一套逻辑。

### 5.2 不得破坏的行为

- 禁止把真实连接凭据写进仓库、日志、测试、命令历史、截图名称或交接文档；只允许运行时注入及已有加密凭据存储。
- 禁止在真实桌面自动化发送、停止任务、执行终端命令、消费/授予额度、标记重置已读、删除或修改远程配置；这些验证使用假传输/合成数据。
- 禁止同时让本轮浏览器、探针和应用争用同一个远端。手机固定 ALI、平板固定 ROG；释放连接不等于停止远程任务。
- 禁止把 `.qa` 集成测试装到 `.dev`；禁止清除 `.dev` 应用数据来“解决”测试问题；覆盖安装使用 `-r`。
- 禁止删除已有未提交改动、盲目 `git reset --hard` / `git clean`、覆盖原 APK 或复用已冻结阶段名写入不同代码。
- 禁止首发重复创建/提交；健康等待超时不能自动再发；回执不确定要保留草稿并提示核对。
- 禁止配置失败却在 UI 显示已切换成功；必须以确认结果驱动可见状态与后续发送。
- 禁止用空响应清掉独立数据源；禁止旧读取、旧账户或旧 scope 更新当前页面。
- 禁止把“缺数据”显示为 0%/100%，也不能混用上下文字符占比、套餐额度和 MCP 额度。
- 禁止提供没有真实行为的按钮，或从方法名字猜测参数/事件。
- 禁止将桌面专属入口直接搬进远控；但已明确要求的客户端扩展也不能随意删掉。
- 禁止把合成截图称为真实官方对照，把 MuMu 回退称为 ColorOS 真机验收，把 CI 绿色称为全部产品完成。
- 本轮未要求推送、打标签或正式发布；阶段 APK 归档不等于获得这些外部发布动作的授权。

### 5.3 旧记录中容易误读的地方

| 旧说法 / 现象 | 当前应采用的做法 |
| --- | --- |
| 协议层 conversation/bridge 可以依赖 Flutter | 当前整个协议目录已纯 Dart，使用 observable/条件导入 |
| 重连固定尝试 15 次 | 当前按生命周期继续恢复；不得重新加回 15 次上限 |
| 所有 integration_test 都要真实连接 | 当前大多数 Android 原生验收是独立 `.qa` + 合成服务；先读入口的包名 guard 和参数 |
| `test/update_checker_test.dart` | 当前实际路径为 `test/update/update_checker_test.dart` |
| CI 不编译 Android，或主要编译 Web | 当前 [CI](D:/WorkSpace/ZcodeRemote/.github/workflows/ci.yml) 包括 Android debug ARM64 编译；仍不替代实际安装/系统行为 |
| 旧 ADB 地址、旧签名/旧仓库 | 每次按实例配置与当前 Gradle/版本代码核对；开发包证书以本次记录为准 |
| 自动额度维护尚未接入 | 从 +9 起已接入；真实只读核查必须启用本地 audit 启动参数 |
| 辅助功能树问题一直未定位 | +10 已有最小复现与修复；旧阶段记录中的“待排查”保留历史语境 |
| 手机突然切任务就是恢复 bug | 此次已确认是你手动操作；遇到共享设备变化先核实，再判断缺陷 |

project-cognition 已同步 V2 核心规则、开发保护、测试命令与回归经验；协议入口已改为引用仓库当前地图，测试发布说明已重写。保留的历史 UI/lessons/对话规格均标注了适用边界。遇到历史内容差异，仍以当前明确要求、根目录文档和源码核对，不照抄旧路径或发布命令。

## 6. 快速测试与验证命令

以下是供后续执行的 PowerShell 示例，本次整理没有重新运行开发验收流程。命令均要求显式目标；不要把包含真实凭据的命令写入文件。

### 6.1 环境初始化

```powershell
$RepoDir = 'D:\WorkSpace\ZcodeRemote'
$Flutter = 'D:\SoftWare\Develop\flutter\bin\flutter.bat'
$Dart = 'D:\SoftWare\Develop\flutter\bin\dart.bat'
$Adb = 'D:\Software\Develop\platform-tools\adb.exe'
$BuildTools = 'D:\Software\Develop\Jetbrains\AndroidSDK\build-tools\36.0.0'
$Phone = '127.0.0.1:16448'
$Tablet = '127.0.0.1:16480'
Set-Location -LiteralPath $RepoDir
git status --short
git diff --stat
```

当前工具链：Flutter 3.47.2、Dart 3.13.2、compileSdk/targetSdk 36。Android 依赖的 `androidx.core:core:1.18.0` 是已验证组合，升级前先查 AAR 对 minCompileSdk 的要求。

### 6.2 按问题选最短的测试集合

| 改动 | 优先测试入口 |
| --- | --- |
| 编解码、握手、重连 | `test/protocol/` + `tooling/protocol_smoke.dart` |
| 任务索引/成员状态 | `test/state/workspace_catalog_test.dart`、`test/state/app_sessions_test.dart`、`test/ui/task_navigation_test.dart` |
| Composer 配置/发送/队列 | `test/state/composer_controller_test.dart`、`test/protocol/composer_transport_test.dart`、`test/ui/composer_ui_test.dart` |
| 引用/中文组合 | `test/state/composer_references_test.dart`、`test/ui/composer_features_test.dart` |
| 附件/恢复 | `test/state/composer_attachments_test.dart`、`test/protocol/attachment_transport_test.dart`、`test/state/recovery_test.dart` |
| 额度/重置 | `test/state/composer_usage_test.dart`、`test/state/plan_resets_test.dart`、`test/ui/plan_reset_dialog_test.dart` |
| 统计 | `test/state/usage_statistics_test.dart`、`test/ui/usage_page_test.dart` |
| 阅读/富文本 | `test/ui/conversation_history_test.dart`、`test/ui/conversation_viewport_test.dart`、`test/ui/markdown_accessibility_test.dart` |
| Android 返回/通知 | `test/ui/predictive_back_test.dart`、`test/ui/notification_navigation_test.dart`、`test/notifications/` |

```powershell
# 依赖未变化时可以 --no-pub；pubspec/lock 变更后先 flutter pub get。
& $Flutter test --no-pub test/state/workspace_catalog_test.dart test/state/app_sessions_test.dart test/ui/task_navigation_test.dart --reporter expanded
& $Dart run tooling/protocol_smoke.dart
```

先用针对性回归定位和修正；收尾跑一轮完整检查。已经通过后，只因新改动、失败或未解决的疑点扩测，避免每个小改动都重复整套构建与双机安装。

### 6.3 完整检查与实际渲染

```powershell
$Evidence = Join-Path $RepoDir 'build\artifacts'
New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
& $Flutter analyze *> "$Evidence\next-analyze.log"
if ($LASTEXITCODE -ne 0) { throw 'analyze failed' }
& $Flutter test --reporter expanded *> "$Evidence\next-tests.log"
if ($LASTEXITCODE -ne 0) { throw 'tests failed' }
& $Dart run tooling/protocol_smoke.dart *> "$Evidence\next-protocol-smoke.log"
if ($LASTEXITCODE -ne 0) { throw 'protocol smoke failed' }
```

```powershell
$env:ZCODE_TEST_FONT = 'C:/Windows/Fonts/msyh.ttc'
$env:ZCODE_TEST_MONO_FONT = 'C:/Windows/Fonts/consola.ttf'
$env:ZCODE_TEST_ICON_FONT = 'D:/SoftWare/Develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
$env:ZCODE_UI_CAPTURE_DIR = 'build/v2-next-preview'
& $Flutter test test/ui/v2_visual_test.dart test/ui/usage_page_test.dart --reporter expanded
```

上述截图是实际 Flutter 绘制。一定打开有代表性的手机/平板、深浅、中英/大字号、错误/加载图检查；只确认文件生成不算视觉验收。最终需要的状态超过这两个测试文件时补相应场景。

### 6.4 双模拟器预检

实例配置位于 `D:\SoftWare\Common\Mumu\emulator\MuMuPlayer-12.0\vms\MuMuPlayer-12.0-{2,3}\configs`：用 `extra_config.json` 的 `playerName` 匹配实例，再从 `vm_config.json` 核实 ADB 映射。当前 2 为手机、3 为平板，但不要永久硬编码这个假设。

```powershell
foreach ($Target in @($Phone, $Tablet)) {
    Write-Output $Target
    & $Adb -s $Target shell wm size
    & $Adb -s $Target shell wm density
    & $Adb -s $Target shell dumpsys display | Select-String 'mCurrentOrientation'
    & $Adb -s $Target shell dumpsys package com.zcoderemote.zcode_remote.dev |
        Select-String 'versionCode=|versionName='
}
```

`settings user_rotation` 不等于实际当前方向；以 dumpsys 的当前方向和截图为准。截图物理像素、Flutter logical 像素、浏览器 CSS 像素要分别记录。

### 6.5 独立 QA 原生测试

```powershell
$env:ZCODE_ANDROID_QA = 'true'
try {
    & $Flutter test integration_test/task_management_test.dart -d $Phone --no-uninstall --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'phone QA failed' }
    & $Flutter test integration_test/task_management_test.dart -d $Tablet --no-uninstall --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'tablet QA failed' }
} finally {
    Remove-Item Env:ZCODE_ANDROID_QA -ErrorAction SilentlyContinue
}
```

其他可替换入口：`usage_controls_test.dart`、`usage_statistics_test.dart`、`android_system_test.dart`。读取包名 guard 后再运行。

`attachment_recovery_test.dart` 使用 `RECOVERY_QA_PHASE=seed/verify`，`reading_recovery_test.dart` 使用 `READING_QA_PHASE=seed/verify`。它们需要分阶段保留 `.qa` 数据并验证进程重建；附件还有系统选择器/fixture 步骤，先读入口，不要把它们盲目拼进普通测试循环。

同一仓库的 Flutter/Gradle 构建和原生测试串行执行；不要在一个构建尚未结束时让另一条命令覆盖 `app-debug.apk`。

### 6.6 产品构建、覆盖安装与只读启动

```powershell
Remove-Item Env:ZCODE_ANDROID_QA -ErrorAction SilentlyContinue
& $Flutter build apk --debug --target lib/main.dart --target-platform android-arm64,android-x64
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
$Apk = Join-Path $RepoDir 'build\app\outputs\flutter-apk\app-debug.apk'
& "$BuildTools\aapt.exe" dump badging $Apk | Select-String 'package:|native-code'
& "$BuildTools\apksigner.bat" verify --print-certs $Apk
Get-FileHash -Algorithm SHA256 -LiteralPath $Apk
```

检查包名必须为 `.dev`，再复制为新的阶段 APK。`aapt native-code` 可能因依赖列出 `armeabi-v7a`，仍须检查 ZIP 中实际的 `lib/<ABI>/libflutter.so`；当前交付承诺是 ARM64 和 x86_64 引擎。

安装前先保存页面和任务状态，确认没有别人使用同一实例。以下例子仅针对指定手机，平板显式换目标：

```powershell
& $Adb -s $Phone shell am force-stop com.zcoderemote.zcode_remote.dev
& $Adb -s $Phone install -r --abi x86_64 $Apk
& $Adb -s $Phone shell am start -n com.zcoderemote.zcode_remote.dev/com.zcoderemote.zcode_remote.MainActivity --ez quotaReadOnlyAudit true
```

**`quotaReadOnlyAudit` 只阻止额度的授予、消耗、已读三个写操作，不是全应用只读沙箱。** 任务操作、配置和终端仍要遵守真实远端边界。普通启动默认启用完整自动额度维护；冷启动前 force-stop 是为保证启动参数生效，不是清数据。

安装成功后用 `pm path` 找实际 base.apk，读回计算 SHA-256，与交付文件比较。不能仅凭 `adb install` 输出 Success 宣称安装了同一份文件。

### 6.7 UI、只读探针和源码冻结

```powershell
# 先读取/截图，再基于本次观察决定点击。不要沿用旧坐标。
python tooling/android_ui_probe.py --adb $Adb --target $Tablet --capture build/visual-audit/next/tablet-ROG-ready.png
```

UI 工具只打印有文字/描述的节点，空列表不自动等于页面没渲染；必要时同时看截图和包名/前台 Activity。Flutter 原生集成测试运行时不要并发扫描同一应用的语义树；单独的辅助功能复现使用 `tooling/accessibility_probe.dart` 构建 `.qa` 后再扫。该诊断入口含故意复现 SDK 缺陷的页面，不能当产品 APK 交付。

真实探针使用 `tooling/remote_feature_probe.dart`，完整链接仅通过运行时 `ZEMOTE_PROBE_URL` 注入；别把赋值原文写入脚本。可用的窄模式有 `ZCODE_PROBE_CONNECTION_ONLY`、`ZCODE_PROBE_FILES_ONLY`、`ZCODE_PROBE_STATISTICS_ONLY`，另设 `ZCODE_PROBE_ALIAS` 标记 ALI/ROG-STRIX。执行前释放同端应用和浏览器，结束后释放探针并清理凭据环境变量。

```powershell
# 先把已验证产品 APK 复制为新的阶段名称；不能覆盖已冻结的旧阶段。
python tooling/freeze_stage.py --stage new-stage-name
```

脚本要求已有 `build/artifacts/ZcodeRemote-v2-new-stage-name-dev.apk`，会生成源码 ZIP、逐文件 manifest 和 SHA 文件；同阶段重复运行只允许源码与 APK 完全一致。根目录文档不在该源码清单中，验收文档应另行保留并交叉链接。

## 7. 本轮得到的排错技巧

### 7.1 先切开问题层级

- 连接失败：按 relay → paired → bootstrap → bridge → Channel Initialize → Conversation handshake → projection 顺序定位。别一开始就怀疑 UI。
- 文件候选超时：先看传输分片/ACK、来源和读取量；本轮真实问题出在大分片接收与 ACK 身份，不是候选 UI。
- 额度不对：先确认 provider/family/组织/项目、时间范围和时区，再看计算。不同设备或任务的数字不能互相充当对照。
- UI 点不到：区分没有数据、坐标过期、覆盖层拦截、手势仍在进行、辅助功能树损坏和真正的布局越界。

### 7.2 对异步问题使用“旧请求先开始，新状态后到达”的测试

用 Completer 控制顺序：先挂住旧请求，切来源/刷新索引/重连，再返回旧值，断言当前页面没有被覆盖。只测试正常返回难以发现串状态。

本轮两个实例：成员状态读取带修订号；重置发生前启动的额度请求不能清掉新完成投影，必须等待旧请求结束后再获取新额度。

### 7.3 辅助功能问题从最小原生页面逐层加回

本轮顺序是静态页面 → 普通弹窗 → 共享浮层 → 长 Text 列表 → 空任务壳 → 富文本任务 → 单个 SDK 可选链接。只有最后两类失效，才定位到可选链接的语义生命周期。不要把强制常驻语义树或频繁重启应用当成修复。

### 7.4 手势与路由不要互相打断

本轮长按开始就打开菜单，会让连续操作出现失效；分区换 key 只能掩盖部分情况。最终改为长按抬起后打开，辅助功能 action 单独保留。验证必须做连续第二次、第三次操作，不能只点通一次。

### 7.5 测试等待要等具体条件

- 有聚焦文本框、光标或持续动画时，`pumpAndSettle` 可能一直等待；用有限时长 `pump` 或等待明确的可见状态。
- `ensureVisible` 后补一帧/等待布局，再读取控件坐标。
- 原生平台回调中的断言可能被业务层 catch 吞掉；回调只记录调用/返回合成值，在测试主流程等待完成后断言。
- 假异步测试里调用 SharedPreferences 等真实异步操作，必要时放进 `tester.runAsync`；不要把卡住误判为产品网络超时。

### 7.6 视觉和证据要可比较

固定字体、语言、字号、可用宽度、主题、数据与滚动位置；截图名称含阶段和远端别名。计算像素差异时记录裁切区域和差异数量，先解释哪些区域可比。曲线/表格/面板结构不同不能用“字体差异”解释掉。

### 7.7 Windows 操作注意点

- PowerShell 优先 `rg` 搜索、`Get-Content -LiteralPath` 读取；多个独立读取可并行，修改/构建/安装按依赖串行。
- Python 中文输出先设置 `sys.stdout.reconfigure(encoding='utf-8')`；先区分控制台编码问题与文件实际损坏。
- 路径使用原生 PowerShell 参数，涉及移动/删除先核实绝对目标，不跨 shell 拼接破坏性命令。
- 工具调用被中断不表示子进程已结束；先查残留进程与构建日志，再启动下一次构建，别清空整组 dart/java/adb 进程。
- 每个独立 shell 的环境变量不保证沿用；每次 QA 构建显式设变量，产品构建显式移除。

## 8. 证据位置与完成定义

最新记录：[侧栏与辅助功能](D:/WorkSpace/ZcodeRemote/references/v2-sidebar-accessibility-acceptance-2026-09-09.md)。

| 证据 | 位置 |
| --- | --- |
| 全局状态 | [v2-goal-acceptance.md](D:/WorkSpace/ZcodeRemote/references/v2-goal-acceptance.md) |
| 实施历史 | [v2-implementation.md](D:/WorkSpace/ZcodeRemote/references/v2-implementation.md) |
| 官方逐项对齐 | [official-feature-parity.md](D:/WorkSpace/ZcodeRemote/references/official-feature-parity.md) |
| 固定官方资产版本 | [official-web-baseline.json](D:/WorkSpace/ZcodeRemote/references/official-web-baseline.json)；实际资产目录 `D:\WorkSpace\ZcodeRemote\build\official-web\assets` |
| 最新检查 | `D:\WorkSpace\ZcodeRemote\build\artifacts\v2-sidebar-accessibility-{all-tests,analyze,build,signature,protocol-smoke}.log` |
| 双端原生任务流程 | `D:\WorkSpace\ZcodeRemote\build\artifacts\v2-sidebar-native-phone.log`、`v2-sidebar-native-tablet-final.log` |
| 最新回归渲染 | `D:\WorkSpace\ZcodeRemote\build\v2-sidebar-accessibility-preview`（153 PNG） |
| 原生及真实截图 | `D:\WorkSpace\ZcodeRemote\build\visual-audit\recovery-qa`，含 `phone/tablet-sidebar-*`、`accessibility-*`、`*-v10-*` |

每个待办完成时至少回答：

1. 官方/产品依据在哪里，适用条件是什么？
2. 实际改了什么，来源和作用域如何保证？
3. 正常、错误、空数据、迟到/切换、重复操作如何表现？
4. 哪些测试与原生场景已通过，日志/截图在哪里？
5. 哪些视觉条件有真正同态对照，哪些仍没有？
6. 对应 APK、版本、签名、哈希、源码状态能否互相定位？

推荐给每个新子项记录这一小段，避免“已完成”没有含义：

```text
ID / 需求：
状态：待核查 / 待实现 / 已实现待验证 / 验收通过 / 受阻 / 有依据的不适用
官方或产品依据：
当前实现与文件：
剩余差距：
验收步骤及预期：
实际结果、日志和截图：
APK / 源码状态：
外部条件（如有）：具体缺什么，最小条件是什么，不影响哪些工作
```

当前需要保留的外部验证条件是：真实 Start/团队数据、ColorOS 16 真机组合，以及离线语音的真实录音链路。它们不阻止继续实现工作面板、设置、语音管理和更新下载等本地可验证部分。

本次整理结束后保持现有代码与设备数据，后续从本文件未勾选条目继续。
