# V2 Flutter 主界面实施记录

## 设置中心对齐第七轮（batch9~batch12，2026-09-12，未打版本号）

本地收口四批：常规节官方 locale 全量校对（修复交互行为下拉显示原始值等 17 处，阶段 `v13-locale-batch9`）；子智能体节官方分组重建（`v13-subagents-batch10`）；账户菜单移除登录占位、登出改官方「断开连接」真实断开行为（`e21-disconnect`）；命令文件新建/编辑/删除 wire 落地（`e12-commands-crud`，269 文件）；模型设置重排为官方双栏（`v13-provider-twopane`）。每批针对性回归+全量（末批 602/602、analyze 0、smoke 通过）、四阶段 APK 双端覆盖安装读回同哈希、证据 `build/visual-audit/takeover-2026-09-12/`。ROG-STRIX 桌面远控会话持续「连接失败」（r19），官方成对对照类仍挂起；自动化巡检 automation-070504ff 每 20 分钟检测恢复。逐项状态见 [进度与 TodoList 手册](D:/WorkSpace/ZcodeRemote/references/v2-progress-todolist-2026-09-09.md)。

## 当前接续入口（2026-09-09）

按要求暂时停止功能开发，整理了 [详细进度 / TodoList / 开发规范与测试手册](D:/WorkSpace/ZcodeRemote/references/v2-progress-todolist-2026-09-09.md)。下文旧阶段的“待实现/待排查”属于当时状态，当前逐项结论以该手册和全局验收表为准。

## 侧栏同步与辅助功能阶段（0.1.0+10，已归档）

修复置顶/归档成员状态回读的时序、原生连续长按菜单，以及带链接的可选 Markdown 在 Android 辅助功能重注册后使树失效的问题；正文选择/跨段落复制保留。368 项完整测试、零静态问题、153 张渲染及双端原生任务操作/深色英文 140% 菜单通过。两台 `.dev`10 安装字节一致，183 文件源码快照已冻结。真实 ROG 进入统计页并返回后连续语义读取正常；完整官方整页视觉及其余 A–F 范围仍未完成。详见 [阶段记录](D:/WorkSpace/ZcodeRemote/references/v2-sidebar-accessibility-acceptance-2026-09-09.md)。

## 额度自动维护阶段（0.1.0+9，已阶段交付）

可见额度界面共用 5 分钟轮询，回到前台立即检查；自动机会、外部完成历史、新额度重查、历史已读及单次完成动效已接入。363 项测试、零静态问题、双端原生额度与统计流程及覆盖安装通过；真实桌面采用同 APK 的启动级额度只读验收模式。APK 哈希、180 文件源码快照与证据见 [自动维护阶段验收](v2-maintenance-acceptance-2026-09-09.md)。实际重复 UIAutomator 查询/弹窗返回后辅助功能树为空的问题仍在排查，F4、C2 全部真实数据组合及全局其余范围继续推进。

## 使用统计阶段（0.1.0+8，已阶段交付）

应用与个人/团队套餐统计已接入独立数据口径、缓存和时间范围；Composer 更多入口、累计摘要、热力图、模型/工具与积分、健康度、模型分布均已实现。Android IANA 时区、来源/范围切换、迟到/重连、缺字段和 More 导航构建期回归已补充。355 项测试、153 张实际渲染、双端原生及覆盖安装通过；ROG 真实套餐/应用统计聚合匹配官方记录，时间范围独立。详情及冻结信息在 [统计阶段验收](v2-statistics-acceptance-2026-09-09.md)。自动重置维护和完整远程设置容器尚未完成，不能据此关闭 C2/E1 或全局 Goal。


日期：2026-09-08。承接「重构Zcode Remote界面逻辑」会话的最后一批未完成改动。

**最新进度（2026-09-09）**：持续推进「ZcodeRemote V2 官方远控对齐与 Android 完整交付」全局 Goal。当前工作区承接全部未提交改动，关联开发任务处于空闲或未加载状态；最新侧栏、引用、附件与套餐实现尚未形成完整验收证据。先完成 A/B/C，再继续 D/E/F，不沿用历史单轮范围豁免。逐项差距、验证方法和状态见 [全局验收清单](v2-goal-acceptance.md) 与 [官方功能清单](official-feature-parity.md)。历史 APK 和测试结果仅作为当时记录。

本轮真实环境规则：竖屏手机固定连接 ALI，平板横屏固定连接 ROG-STRIX；每次验证先重查实例地址、方向、density、可用尺寸及安装版本，并确认远程实际身份与连接独占。官方页面与同端应用串行持有连接，切换只释放客户端连接。真实远程只读，写入验证使用合成数据/假传输；文档、测试、日志及截图名称不含连接凭据。

## 额度与来源阶段：0.1.0+7（2026-09-09）

`build/artifacts/ZcodeRemote-v2-quota-dev.apk` 已在指定双 MuMu 覆盖安装并校验安装字节。SHA-256 `9706a27ef6df893441ab30d6020e93817f5ddb446bb941b6cd14e12c2cff7ecb`，169 文件源码 ZIP 与 manifest 已冻结；源码状态 `c4b1f0a6c26dd4dd67e7f1a9766d1131f142f207df931f68453797755b04d97a`。

- 修正上下文容量与缓存精度、总进度/来源比例、MCP 独立日期，补齐旧格式团队的实际组织/项目解析。
- 手动重置有真实状态/次数/到期/弹窗及请求确认链路。双击不重复提交，超时沿用标识，已受理但未确认仅查询；所有消耗行为由合成服务验证。
- 原生截图暴露的菜单旧主题/键盘 inset 捕获问题已通过共享组件修复；模态尺寸和背景模糊按官方 CSS 校准。
- 339 项完整测试、静态检查零问题、33 张 Flutter 渲染、纯 Dart smoke、双 MuMu 原生 QA 与产品安装通过。ROG 同任务真实额度数字、日期和 1 次周重置机会与官方一致。
- 真实使用统计的两套 RPC 与官方页面已核查；“更多”完整页、自动机会/已读/提示联动仍待实现。C2 及其余 A–F 必需项继续保持未完成。

详见 [额度阶段验收](v2-quota-acceptance-2026-09-09.md)。

## 长历史与阅读恢复阶段：0.1.0+6（2026-09-09）

`build/artifacts/ZcodeRemote-v2-history-dev.apk` 已在指定双 MuMu 覆盖安装，包含 ARM64 / x86_64，原 `.dev` 包名及签名保持兼容。SHA-256 `5ef6cef49a29fdb0da635d17811e00ca79ff0d419444a9257133e2e0b92614ff`；160 文件源码快照和 manifest 已冻结。

- 按官方 LTe/wb/Tb 修正分页下界、日志代次和游标校验，新日志不带入旧页。恢复按消息 ID 读取必要页，支持失败重试和取消，目标消失或历史变化会说明。
- 新列表能定位尚未构建的变高消息；验证 1,000 行、不同宽度、140% 字号、流式与折叠恢复。拖动后的锚点改在布局完成后记录，修复下一帧被拉回的问题。
- 手机/平板独立 QA 的原生加密保存、进程重启、两页读取和相同可见偏移均通过；排除阶段标题后恢复前后像素相同。
- 产品真实任务中，ALI 长回复和 ROG 实际分页后的旧消息也恢复到原位置，记录的正文区域均无像素差异。未发送或执行远端写入。
- 静态分析零问题、304 项完整测试通过、33 张 Flutter 渲染、独立 Dart 协议 smoke 与双 ABI 构建签名通过。

完整包信息与逐场景证据见 [长历史阶段验收](v2-history-acceptance-2026-09-09.md)。F3 持久恢复功能已验收；这不代表完整 D2、系统/视觉组合及其余 D/E/F 已完成。接下来继续团队套餐来源兼容及剩余官方对齐。

## 草稿与附件恢复阶段：0.1.0+5（2026-09-09）

`build/artifacts/ZcodeRemote-v2-recovery-dev.apk` 已构建并覆盖安装到两台指定 MuMu，两个安装包字节均与交付 SHA-256 `3f831adb11979d2b29038fd521aebe2b7cdf8b234b53e9bc608408b51069e817` 一致。保持 `.dev`、ARM64 与 x86_64 引擎及原签名。可定位的 151 文件源码快照与 manifest 同目录保存，基于未提交工作区，未创建提交或推送。

- `RecoveryJournal` 使用原生 Keystore 加密、前一有效快照与串行合并写入。后台和提交前 flush；保存失败可见且可重试；较新 schema 不被覆盖。
- 恢复文本、引用、附件/发送状态、暂存会话与配置、任务导航、主辅面板、侧栏和阅读锚点。读取期间的新编辑优先，移除设备同时阻止迟到的文件和存储结果复活旧作用域。
- 附件经原生选择器复制至私有缓存并校验 SHA-256；恢复后按需预览，缺失/损坏保持可见且阻止提交。恢复不自动上传、发送或新建会话；明确失败可显式重新准备，不确定发送必须先核对历史。
- `/plan` 的异步模式准备纳入发送去重，避免连续点击产生第二次首发。
- 完整测试 **289 项通过**，静态分析零问题，双 ABI APK 构建通过；日志 `build/artifacts/v2-recovery-final-{analyze,tests,build,signature}.log`。
- 手机和平板各完成独立 `.qa` 的真实文件选择、字节校验、失败保存、进程关闭后恢复与预览、显式单次发送。发送端均为合成传输。测试入口严格检查 QA 包名；日志与实际预览见 [Android 集成记录](flutter-android-integration.md)。

产品 APK 双端冷重启已恢复各自真实任务、本地草稿及平板面板；仅输入并清理本地标记，未发送。完整证据见 [恢复阶段验收](v2-recovery-acceptance-2026-09-09.md)。深历史自动分页定位、中文软键盘和 V2 系统组合、完整官方视觉对照仍待继续；D/E/F 的其余既定范围保持未完成。

## 全局 Goal 阶段交付：0.1.0+4（2026-09-09）

已交付 `build/artifacts/ZcodeRemote-v2-goal-phase1d-dev.apk`，两台指定 MuMu 已覆盖安装、启动并分别连接 ALI / ROG-STRIX。APK 包含 ARM64 与 x86_64 引擎，沿用 `.dev` 和原兼容签名；SHA-256 `373da487a8e4cee5fdbfc28019fce8494a4b4cf1b59a54717d624d80eea0926b`。源码快照、逐文件构建状态、日志、截图与场景结果见 [本阶段验收证据](v2-phase1-acceptance-2026-09-09.md)。

- 修复侧栏全索引合并、置顶/归档省略字段、旧标题覆盖、未读与切换状态；补齐操作确认和失败回归。
- 接通真实文件/技能/插件/任务引用、加号菜单、附件首发与取消重试状态；修正候选排序、缓存、作用域和中文组合输入标记。
- 接通 GLM/Start/MCP 独立用量，修复新任务门控、未知余额、旧账户缓存、失败及迟到响应；平板真实用量已读取。
- 修复导致真实文件目录持续超时的 RPC 接收分片限制与 ACK 身份遗漏，ROG 只读目录返回 6,180 项；修正桥接重建、旧帧/旧握手竞态和恢复停止问题。
- 协议目录现已无 Flutter 依赖，独立 Dart VM 可编译运行；源码/接口保持原生 Flutter 产品路线。
- 根据 ALI 同任务官方截图修正 composer 外层容器断点；修正信息/删除图标转导出解析，补齐向下箭头。
- 最新静态分析零问题，267 项测试通过，生成 33 张 Flutter 渲染图。源码状态以本阶段 manifest/ZIP 为准，历史 APK 均保留。

**这仍是阶段交付。** 原生附件的完整实机链路、中文软键盘/其余组合与完整官方同态视觉，以及 D/E/F 既定范围尚未全量验收；Goal 继续保留未完成状态。此前仅限单轮的“后续”不是范围豁免。

## 本批：官方细节校准（2026-09-08）

### 已完成

- 新增 `conversation_layout.dart`，正文和 composer 共用官方 `y5e/g5e` 规则：容器 ≥864 时 `min(width-96,896)`，≥1280 时 `min(width-384,1152)`；内部左右 16dp。工作面板占用后按主对话剩余宽度重新计算，主辅对话独立；保持阅读锚点及用户驱动跟随。
- 侧栏项目/任务行收紧为约 32dp，补充项目任务数与相对时间，任务时间区域可打开原任务操作菜单。顶栏项目与标题相邻；设备切换、头像账户入口继续位于底部。
- Composer 使用官方 40dp 输入区最小高度、12dp 间隔和 28dp 基础按钮；大字号允许按钮自然增高。模式文案映射官方 GLM 中英文键，保留未知值回退；完全访问橙色修正为深 `#ff8a30` / 浅 `#e07b00`。悬停/聚焦边框按官方 15% 墨色，底色不变。
- 新增 `composer_popover.dart`：按实际内容测量高度，优先向上、空间不足向下，限制在安全区与键盘上方；捕获局部主题，避免弹窗丢失字体。保留供应商分组和真实配置选择，未写入额外远程配置。
- 新增 `context_usage.dart`：从当前会话 `usage.contextWindow` 读取用量，缺失/非法总量时隐藏；按字符数合并并排序来源，低于 78% 的缓存命中率隐藏。触屏按下即打开、键盘可聚焦，弹窗随当前会话数据更新；未将套餐余额或压缩动作伪装为已实现。
- 新增 `conversation_work_rows.dart`：MCP 优先解析 `display.mcp_tool`，否则沿官方 `Knt/PJ/qnt/Jnt` 规则整理名称；常见内建工具显示操作及路径/命令，未知工具保留明确名称回退。工具可展开真实参数、结果、错误；成功行不再重复显示“已执行”。思考缺少 durationMs 时显示官方“持续了几秒”，思考图标改为 brain。补齐 V4 `pendingApproval/inputStreaming` 活跃状态和子智能体真实字段。

### 验证与交付

- `flutter analyze --no-pub`：零问题；`flutter test --no-pub`：**219 项全部通过**，新增 7 项针对本批缺陷的回归。包括阅读列实际左右边界、模式中英文/主题色、MCP 元数据优先级、缺时长文案、用量容错/排序、弹出位置与键盘避让、用量弹窗实时更新及无远程写入。
- 本批 Flutter 渲染预览共 **33 张 PNG**：`build/v2-details-preview/`，覆盖五形态、深浅主题、英文 140% 字号、主辅面板、菜单、队列与错误状态，并增加官方 schema 合成工具/思考/用量样本。修复了检查中发现的弹窗字体继承和输入区高度偏差。
- 重新下载官方线上 `index-nOVzQNKW.js`（4,779,908 bytes）和 `index-BMndL2ru.css`（384,056 bytes），与本地参考资产逐字节一致。重新打开真实官方页面时浏览器读取超时，本批没有取得同设备/同任务/同主题的新成对截图；沿用上一轮真实官方图做结构校准。
- `flutter build apk --debug --no-pub --target-platform android-arm64` 成功。交付 `build/artifacts/ZcodeRemote-v2-details-dev.apk`，包名 `com.zcoderemote.zcode_remote.dev`、开发版本 `0.1.0+1`，包含 ARM64，v2 签名验证通过且证书与前批相同。
- SHA-256：`b18b89c85062acf330a65c048b2cd506c6444bc201f96021ae42875f4c8e0ebd`。前批 APK 均保留。
- 已通过 `adb install -r` 覆盖安装到 MuMu（127.0.0.1:16384），系统安装更新时间 2026-09-08 23:30:40；1920×864、density 240，应用可用区域等效 1280×552dp。原设备/项目数据保留，实际任务正文与 composer 对齐、中文完全访问橙色和用量弹窗均确认。截图：`build/visual-audit/mumu-after-details-task.png` / `mumu-after-details-usage.png`。
- 日志：`build/artifacts/v2-details-{analyze,tests,render,build}.log`。真实桌面只读浏览，没有发送消息、停止任务或切换远程配置；未操作连接中的物理手机。

### 仍有差异

- 完整官方像素一致性尚未验收；字体栅格化、菜单供应商家族合并、触控/悬停细节、工具富预览/文件增删标签等仍需继续校准。当前工具详情展示已有快照，未补全远程超大字段分页。
- 附件/@ 上下文入口、完整终端/审查、分支数据及帮助入口、全量官方远程设置、语音和更新安装等继续保留在后续需求；没有放置无行为按钮充当完成项。底部多设备选择是已确认的产品扩展。
- 全部调试包仍为 `0.1.0+1`，用 APK 文件名和 SHA-256 区分本批。进程重启后的草稿/导航恢复仍不在本批范围。

## 本轮：composer 配置与发送控制

2026-09-08 在全部已有未提交改动之上继续实施；未重置或重建旧版本。协议依据见 [composer 协议核对](composer-v2-protocol.md)。

### 已完成

- 接入真实 `prepareWorkspace/configOptions` 和当前会话 `config`：按供应商分组选择模型、协作模式、思考等级；按返回元数据处理固定/不支持思考的模型，按官方 rank 排列思考项。
- `ComposerStore/ComposerController/ComposerOptions` 独立管理设备、工作区、会话作用域；编辑器与异步操作由应用持有。已有会话不会被 workspace draft 收敛写入，切设备、页面恢复与重连只读配置。
- 配置串行提交，保留最新待选展示，检查 accepted/noop/duplicate；失败回到已确认值，依赖失败模型的思考操作不发出，连续独立操作继续执行。旧 prepare/旧代次 ack/旧 revision 不覆盖新结果；原请求未结束时不放行重连后的新配置写入。
- 新任务首条文本原子 `createSession(firstInput)`，只提交一次；成功迁移编辑器、草稿、配置、阅读、工作面板布局和导航缓存。发送期间新输入保留，失败不丢草稿。页面已退出时仍迁移应用缓存。
- 已有会话检查发送 accepted/duplicate 回执；健康超时不自动重发，并提示核对历史。断线重放保留同一 commandId，不再换 ID；删除旧协议中猜测 reasoning effort 的重试。
- 发送/处理中/停止来自服务端 control/inputRouting；停止绑定设备、工作区、会话与可用 foreground execution ID。迟到的旧停止回执不把新一轮标记为停止中。
- 运行中输入交给服务端 enqueue/guide/reject；实现最小待发队列（查看、暂停/继续、立即发送、移除）。choice 明确确认保留/清空，携带队列 ID；本地或服务端报告队列变化时重新确认。
- 新 UI 拆分为 `ui/composer/`，`chat_page.dart` 只负责绑定会话和视图。384/576/672 使用工具栏实际容器宽度；小宽度图标、中宽度思考条、宽容器标签与供应商前缀。
- Android 多行换行不发送；桌面 Enter 发送、Shift+Enter 插入换行；保护中文 composing 及候选词确认后短窗口的 Enter。原有键盘单次避让、用户驱动阅读跟随及主辅组件生命周期保持。

### 验证与本轮安装包

- `flutter analyze --no-pub`：零问题。
- `flutter test --no-pub`：完整 **212 项通过**，比 175 项基线新增 37 项；包含 22 项配置/发送状态、9 项 composer UI/输入/布局、6 项实际 Channel 编解码假对端回归。
- 覆盖 A/B 使用相同 workspace/session ID、首发成功/失败/发送期间编辑及缓存迁移、连续配置失败/迟到/重连、能力门控与停止 execution 作用域、队列确认/保留/拒绝、中文输入法、桌面换行与发送；容器断点两侧、五形态、深浅色和英文 140% 字号均测试。
- 真实 Flutter 渲染生成 **29 张 PNG** 到 `build/v2-composer-preview/`，使用本机中文/等宽/图标字体；检查了手机浅色、344 宽英文大字号模型菜单、平板主从布局、720 宽运行队列、1180 宽 pending/失败状态。没有官方同数据截图对照，不声明 1:1 或像素一致。
- `flutter build apk --debug --no-pub --target-platform android-arm64` 成功；交付 `build/artifacts/ZcodeRemote-v2-composer-dev.apk`。包名 `com.zcoderemote.zcode_remote.dev`，版本沿用开发版 `0.1.0+1`，应用名 `ZcodeRemote Dev`，包含 `arm64-v8a`（调试包同时含 armeabi-v7a/x86_64）。APK v2 签名验证通过。
- SHA-256：`f5750a8a911437d795882c38b2e7ceac33e25d061f73a618a597cb2a3aeb5743`；同目录 `.sha256` 文件。已检查 APK 的 Dart kernel 含新增 ComposerController/ComposerBar，确保本轮代码进入安装包。
- 测试与构建日志：`build/artifacts/v2-composer-tests.log`、`build/artifacts/v2-composer-build.log`。本轮未通过 ADB 安装，也未操作真实桌面消息、停止或配置。所有写入验收使用合成数据与假传输。
- 旧 `build/artifacts/ZcodeRemote-v2-dev.apk` 保留为上一批主界面基线，本轮下载使用带 `composer` 的文件名。

### 真实限制

- 官方供应商家族合并与连接管理、所有远程设置仍未完整迁移；现有客户端设置不替代官方全部设置。
- 队列已完成最小操作闭环；编辑/重排、投递方式快捷键和交互请求表单待继续。附件、@ 引用、完整终端/审查、离线语音、更新安装仍属后续，未放置无行为按钮充当完成项。
- （本条已由上方细节批更新）composer 原先使用 Flutter 原生菜单及 32dp 触发器，本批已改为实测定位弹窗和 28dp 基础按钮；完整同数据官方视觉对照仍待完成。
- 内存缓存不承诺进程被系统回收后的恢复；Android 真机中文输入法/折叠键盘/多设备联调尚待实测。ColorOS 16 上岛沿用已确认实现，本轮未改 Kotlin 通知能力。

## 当前产品入口

`main → ZcodeRemoteApp → HomePage → WorkspaceShell`。设备目录用于首次添加、连接失败重试和管理设备；成功连接恢复最近任务。`WorkspacePage` / `TaskListPage` 的旧分层入口保留为历史实现，不再由产品主入口使用。Web 验证目录不参与 Android UI。

## 上一批主界面已接入

- 项目/任务侧栏，项目展开、搜索、置顶/归档筛选与任务重命名；任务数据仍独立保存 channel 和 sessions-index 后合并。
- 左下设备菜单显示真实连接状态；设备更新凭据、重命名、断开、移除和重连共用 `DeviceStore` / `AppSessions`。
- 头像名字整体弹出小菜单；语言、主题/字号、通知和设置入口已可用。账户名字/头像来自远程 OAuth 已缓存状态；没有账户信息时显示 ZCode。
- 客户端设置持久化：跟随系统/深浅主题、中文/英文、文字缩放和代码字号；通知页面与现有更新检查接入设置中心。
- 顶部任务标题、宽屏项目名、更多操作和工作面板入口；当前面板支持任务状态、变更摘要和真实辅助对话。
- 主辅对话组件在面板开关、tab 切换、覆盖/并排切换时保持挂载；重新打开任务恢复内存草稿、阅读状态与面板偏好。
- Markdown 正文/代码、历史分页、用户主动滚动控制跟随；保存消息 id 与可见偏移用于旋转/折叠后恢复。已拒绝发送不清草稿。

## 状态与返回

- 设备连接和工作区监控由应用持有，页面不销毁连接。
- 同一设备/工作区/session 返回时优先复用路由，避免重复订阅和旧输入框覆盖新草稿；连接和工作区打开之后再次校验导航代次与路由当前性。
- 任务视图缓存按 deviceId/workspaceKey/sessionId 隔离；新会话创建后迁移草稿和布局缓存 key。
- 面板用 Flutter LocalHistoryEntry 参与返回；先关闭工作面板或抽屉，再返回上一个页面。普通页面继续使用 MaterialPageRoute 及预测返回过渡。
- 嵌入聊天取消内层 Scaffold 的键盘避让，由外层工作界面统一处理。

## 上一批主界面验收（175 项基线）

- `flutter analyze --no-pub`：零问题。
- `flutter test --no-pub`：175 项通过，包括原有预测返回、通知和协议回归。
- `flutter build apk --debug --no-pub --target-platform android-arm64`：编译成功。交付文件 `build/artifacts/ZcodeRemote-v2-dev.apk`，SHA-256 旁文件同目录。包名 `.dev`，使用产品 `lib/main.dart` 入口，可覆盖上一批独立调试版；本轮未通过 ADB 安装到已连接真机。
- 新场景：五形态主辅编辑器保持、A→B→A 路由复用、相同 sessionId 的跨设备草稿隔离、A 晚到不覆盖 B、辅助对话切 tab 不重复订阅、覆盖面板焦点隔离、铰链避让、流式/分页/折叠保持阅读锚点、键盘只避让一次、拒绝回执保留草稿、140% 字号与设置持久化。
- `test/ui/v2_visual_test.dart` 使用真实 Flutter 组件和合成任务生成本地 PNG；覆盖 344/390/720/834/1180 宽度、深浅两色、各尺寸打开面板及 344 宽英文 140% 字号。生成位置：`build/v2-preview/`。
- 截图使用本机测试字体，验证组件布局和主题可读性；未与同数据、同字体的当前官方网页逐像素对照，不能据此宣称 1:1 已验收。

复现可选截图：设置 `ZCODE_UI_CAPTURE_DIR` 为输出目录，`ZCODE_TEST_FONT` 为中文字体文件，`ZCODE_TEST_MONO_FONT` 为等宽字体，`ZCODE_TEST_ICON_FONT` 为 Flutter SDK 的 Material 图标字体，再运行 `flutter test test/ui/v2_visual_test.dart`。不设置这些变量时仍执行布局测试，不写截图。

## 仍需迁移

1. composer 后续：@ 引用、附件、完整交互请求、队列编辑/重排和投递快捷键。模型/模式/思考、发送/停止及最小队列闭环已在本轮完成。
2. 全量官方远程设置及账户菜单的登录/登出、用量能力门控；现有五类客户端设置不是官方全部设置。
3. 终端交互、文件 diff/完整审查、分支信息与工作面板剩余工具能力；当前变更摘要不等于完整审查。
4. 离线语音模型下载与识别、APK 下载/校验/安装；当前更新入口仅检查版本并可复制发布页面。
5. 进程被系统回收后的草稿与导航恢复、较深历史分页未加载时的锚点定位，以及同数据官方视觉对照。
6. 新 V2 页面在真实双设备、ColorOS 16 返回手势/键盘/折叠场景的联合验证。本批测试不向真实桌面发送任何命令。

ColorOS 16 上岛效果沿用上一批 He 的实测确认；本批不改原生通知实现。


## 2026-09-10 会话推进记录

### P1 / A 阶段推进

- **A1.2 收口**: ROG 真实只读场景补齐置顶数据分支——折叠全部、搜索 `Cognition`、清除、时间线、创建/更新排序、归档开关、项目视图与排序还原。两个真实置顶项均只显示一次，时间线项目副标题正确，原任务保持可见。ALI 既有记录覆盖无置顶数据分支。证据 `build/visual-audit/takeover-2026-09-10/a1.2-tablet-real/a1.2-scenario-record-2026-09-10.md`。

### D 阶段推进

- **A2.3**: 侧栏任务行按官方 `KEt` 对齐——16px switching/mutation spinner、6px 未读点、16px pin、24px 标题条、official selected/hover 与操作尺寸；switching 与 mutation 分离，mutation 不再阻塞打开。2026-09-12 同远端官方成对对照修正 selected 行不展开操作；修复包与截图证据见 `build/visual-audit/takeover-2026-09-12/a2.3-official-pair-2026-09-12.md`。

- **A1.3**: 侧栏实时更新组合回归补齐——timeline/搜索/归档/活动任务下，新 remote projection 正确刷新，旧 pin/archive 回读被拒绝，空 local source 不擦除 remote，刷新不误跳转。
- **P1.1**: 新增双远端 synthetic-A/B 相同 workspace/task ID 的断线恢复联合回归；恢复后各自身份独立重订阅、发令和收据，不跨 transport 串用。
- **D1.1**: Git 分支只读入口完成（GitClient + GitSummaryController + GitBranchChip）。47 项回归通过；ROG-STRIX `git.refresh` summary-only 只读探针通过。
- **D1.2**: 布局测试从 3 扩至 8 项，覆盖五宽度 × 140% 字号 × 侧栏/面板/覆盖/焦点矩阵。官方 JS 取证确认远控顶栏仅保留 Git chip + More + 侧面板切换。新增本地 Command Center：官方四 tab/前缀 scope/最近任务/最近文件/建议与面板动作首版，`Ctrl+K/N/B/J` 接入 shell；空文件 tab、最近文件排序、tab 图标与任务相对时间按官方证据实现，未发明未确认的 Skills/MCP/主题命令。
- **D2.2**: ToolCallRow 增强——输出截断指示、文件路径提取（官方 mge() 字段）、URL 提取、文件/URL 可点击芯片。
- **D2.3**: 消息操作——用户消息 Copy/Edit、最新完成助手正文 Copy/Fork 已接入；Fork 调 `forkAssistant({rowId, entityId})`，处理 accepted/duplicate、失败、迟到响应和新 sessionId 导航；Feedback 在远控隐藏，官方当前最新消息行未渲染 Retry，因此不发明 UI。
- **D2.4**: 主辅隔离已有 3 项完善测试（A→B→A 路由恢复、迟到连接不覆盖、拒绝发送保留草稿）。
- **D3.1-D3.4**: 本地合成闭环已完成（diff 审查、rewind、终端、交互请求），全部待真实远端只读取证。
- **D4.2**: reorderQueueItem 协议方法新增，queueAction 支持 edit/reorder，队列 UI 加编辑对话框和上移/下移。
- **D4.1（2026-09-11）**: 合成组合闭环覆盖配置、原子引用、上传附件、首发一次、回执、提升会话、精确停止和后续发送；28 项 Composer Controller 回归通过，analyze 0。证据 `build/visual-audit/takeover-2026-09-11/d4.1-combined-closure-2026-09-11.md`。

### E 阶段推进

- **E1.1**: 官方 settingService.get/update 模式取证，15 节设置远控条件→RPC→UI 完整映射文档。
     - **E1.2**: 设置中心加远控设置节导航框架（modelProvider/plugins/skills/mcp/hooks/usage），修复侧栏窄屏溢出；真实只读 setting/get wire format 已确认 43 字段；已加 RemoteSettingsController 和 modelProvider/hooks 只读 UI，含加载/错误/重试/scope 保护；plugins 接入既有隔离插件管理，退出清空插件候选缓存；skills 只读读取 skills/list；MCP 只读读取 workspace server statuses。
- **E2.1**: 官方账户菜单结构取证，加 Usage/Upgrade/Login/Logout（带 auth 门控）。
- **E2.1**: 账户菜单 Usage 改为打开工作区作用域 UsagePage，补菜单级回归。
- **E2.1（2026-09-11）**: Upgrade 菜单打开本地只读套餐页。控制器先读 `providerFamilyDomain`，再复用官方 `getEnterprisePricing` 链路解析套餐、价格与权益；实现 generation、pending 去重、dispose 保护，并在 pricing 成功后原子提交 family/provider/products，失败保留旧展示。页面提供 loading/empty/error/retry，不含购买提交。定向 21/21，全量 541/541，analyze 0。证据 `build/visual-audit/takeover-2026-09-11/e2.1-upgrade-page-2026-09-11.md`。
- **E2.2（2026-09-11）**: 从官方 bundle 整理 OAuth 服务方法与 cached-state 语义：登录为外部授权 + polling/deep-link 双通道，迟到回调去重；过期 JWT 清理并要求重新认证；logout 触发 provider-family 迁移元数据、profile、provider 缓存、webview storage 与 relaunch。新增 `AccountChangeManager` 失效回归，确保确认账户变更后 usage/references 缓存重建。真实远端 OAuth wire 与写入副作用仍留外部验证。
- **E2.2 统计缓存补测（2026-09-11）**: AccountChangeManager 失效回归补齐 UsageStatistics——账户变更后 application 与 lifetime 统计缓存清空，必须重新读取；账户变更相关 2/2，analyze 0，全量 551/551。
- **D3.4（2026-09-11）**: 补交互请求同 task id 重连/替换回归——旧控制器未完成响应时释放，替换控制器绑定新的 pending snapshot；旧迟到 accepted 不移除新请求，也不把旧失败挂到替换控制器。交互专项 15/15，analyze 0，全量 543/543。
- **C2.3（2026-09-11）**: 补无有效订阅的团队套餐来源组合：旧产品键遇 `subscribed:false` 且 fallback 无团队身份时，标记 source unavailable 并清空来源/快照，不显示个人余额或猜测团队额度。额度来源 17/17，analyze 0，全量 544/544；真实账户组合仍外部阻塞。
- **D2.4（2026-09-11）**: 补双远端同 workspace/session ID 的重连隔离回归——仅 A 恢复时，A 的草稿/配置意图处理不受 B 影响，B 的草稿与配置也不被触发且无命令；连同既有“恢复丢弃 pending config、忽略迟到 ack”覆盖重连组合。控制器 29/29，analyze 0，全量 545/545。
- **B2.3（2026-09-11）**: 补附件条 UI 状态回归——ready 名称/尺寸/移除、uploading 百分比、failed 错误与 retry 入口、文本附件预览弹窗和关闭均实际渲染验证。附件条 1/1，analyze 0，全量 546/546。**2026-09-12 追加：按官方对齐 48px 附件卡、thumbnail/名称/状态布局、失败 error/retry；新增发送后媒体缩略与只读 pill。官方失败重试、历史发送媒体与预览已只读取证；实时上传进度需真实上传，保持 BLOCKED_EXTERNAL。证据 `build/visual-audit/takeover-2026-09-12/b2.3-attachment-official-alignment-2026-09-12.md`。**
- **C1.1（2026-09-11）**: 补上下文来源排序细节回归——字符量优先、同量按官方来源顺序、未知来源排末位；结合既有无效窗口、缺分项、缓存阈值和无 breakdown 实体条用例。official detail 11/11，analyze 0，全量 546/546。
- **D2.2（2026-09-11）**: 补工具详情实际渲染回归——`output.truncated` 显示警告；文件路径 chip 去重且多条并存；URL chip 多条并存且保留 fragment；调用/参数/结果仍可见。official detail 12/12，analyze 0，全量 547/547。
- **G1.1 审计快照（2026-09-11）**: 按当前 TodoList/验收表复核剩余项，未发现新的本地实现或合成测试缺口；剩余集中在官方成对视觉、真实桌面/账户/设备验证和 G 阶段最终构建安装归档。快照 `build/visual-audit/takeover-2026-09-11/g1.1-remaining-audit-2026-09-11.md`。
- **G1.1 证据路径审计（2026-09-11）**: 对 TodoList/验收表/实施记录中的证据路径做存在性扫描；未发现缺失证据文件，仅保留历史路径映射说明。B1.1 旧的 partial 路径已指向真实 IME closure 证据。
- **E2.1 状态补测（2026-09-11）**: Upgrade 只读页补 loading/empty 渲染回归，确认无套餐时显示官方空态且不出现购买入口；Upgrade 页 3/3，analyze 0，全量 550/550。
- **F1.3（2026-09-11）**: 修复 VoiceInputButton 未监听 VoiceInputController 的问题，避免 requesting/recording/recognizing/error 视觉状态停留；新增按钮全状态渲染回归，确认识别结果只写草稿且不发送。语音按钮 1/1，analyze 0，全量 549/549。
- **稳定性与证据审计（2026-09-11）**: 上下文额度弹窗的 `refresh → refreshResetStatus` 后续 future 补显式错误消费，避免维护任务异常以 unhandled async error 暴露；同时完成 TodoList/验收表/实施记录证据路径存在性扫描，B1.1 旧 partial 引用更新为 IME closure 证据。上下文/额度定向 51/51，analyze 0，全量 549/549。
- **D3.1（2026-09-11）**: 修复 Change Summary 展开时未消费 `fileChanges` 失败 future 的 UI 层问题，让既有错误/重试状态保持唯一可见恢复入口。新增实际渲染回归：失败状态可见，重试后恢复文件列表与 unified diff。file-changes UI 4/4，analyze 0，全量 548/548。
- **C2.3（2026-09-11）**: 补无有效订阅的团队套餐来源组合：旧产品键遇 `subscribed:false` 且 fallback 无团队身份时，标记 source unavailable 并清空来源/快照，不显示个人余额或猜测团队额度。额度来源 17/17，analyze 0，全量 544/544；真实账户组合仍外部阻塞。
- **D3.4（2026-09-11）**: 补交互请求同 task id 重连/替换回归——旧控制器未完成响应时释放，替换控制器绑定新的 pending snapshot；旧迟到 accepted 不移除新请求，也不把旧失败挂到替换控制器。交互专项 15/15，analyze 0，全量 543/543。

### C 阶段推进

- **C2.4**: 套餐身份与到期字段按官方 `subscription.details[0]` 取证接入--`EntitlementSnapshot` 新增 `planName`（productName→productId→quota.level fallback）与 `expireTime`/`renewTime` 宽松解析（毫秒/数字字符串/ISO 日期，非法与越界不渲染），用量页个人套餐头部优先显示套餐名并按官方 `EHt` 优先级（renew 优先）显示续期/到期文案行。5 项针对性回归、488 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/c2.4-plan-identity-2026-09-10.md`。
- **C1.1 收口**: 同用 ROG-STRIX 同任务完成上下文容量/缓存成对对照，21.7万/100万 (21.7%)、平均缓存命中率 94.8%；无 breakdown 时两侧均不显示明细。证据 `build/visual-audit/takeover-2026-09-12/c1.1-same-task-official-pair-2026-09-12.md`。
- **C2.5 收口**: 1180 宽官方/Flutter 成对几何确认应用与个人套餐内容宽均 832；用量页大标题与 tab 同内容行，AppBar 不再重复标题。证据 `build/visual-audit/takeover-2026-09-12/c2.5-usage-geometry-pair-2026-09-12.md`。
- **C3.1 收口**: 1180 宽官方/Flutter 四卡对照确认 ZCode MCP 独立标题/info、百分比、日期和进度条；三主卡全宽、缺值与非法日期行为由既有回归覆盖。证据 `build/visual-audit/takeover-2026-09-12/c3.1-mcp-geometry-pair-2026-09-12.md`。
- **C2.4 最终本地收口（2026-09-11）**: 设置中心 `usage` 节与账户菜单均打开工作区作用域用量页；应用/套餐来源分离、套餐名、续期/到期优先级与非法日期不渲染有专项回归。设置/用量/额度 4 组针对性测试 56/56 通过，analyze 0。证据 `build/visual-audit/takeover-2026-09-11/c2.4-final-local-closure-2026-09-11.md` 与 `build/artifacts/c2.4-final-local-tests-2026-09-11.log`。
- **E1.2**: 写入链路首个端到端闭环完成——hooks 自动处理提问开关走官方 `settingService.update(patch)` 模式，controller 新增 update（逐键在途去重、保存错误、lastAttempt 重试），可见状态只来自成功写入后的 get 回读，失败保留原值；UI 保存中显示 spinner、失败显示错误与重试（重发上次尝试值）。4 项新回归、492 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/e1.2-settings-write-2026-09-10.md`。
- **E1.2 追加**: memory 节接入同一写入闭环——开关逻辑抽成共享 `_remoteToggle`，memoryEnabled 字段复用 update/回读/失败重试模式。5 项相关新回归、493 项全量测试、analyze 0。
- **E1.2 追加 2**: general 节远端区接入任务自动归档两个字段——taskAutoArchiveEnabled（switch）与 taskAutoArchiveOlderThanDays（select，官方固定 3/7/14/30 天选项），以“远端设置”分隔线与客户端语言项区分；归档时限保存中转 spinner、失败可重试、缺值不造选项。6 项相关新回归、494 项全量测试、analyze 0。
- **E1.2 追加 3**: browser 节接入 embeddedBrowserAllowInsecureCertificates 开关（官方 update 调用 + 真实探针 43 字段双重取证）；快照解析新增该字段，开关复用 _remoteToggle 闭环。同时完整枚举官方 update 调用：modelProvider 家族字段为读-合并-写、indexing 走组合 setter，均需按节另行验证。7 项相关新回归、495 项全量测试、analyze 0。
- **E1.2 追加 4**: modelProvider 节接入家族 mode 切换——官方 `c9` 常量确认 oauth/apiKey 两合法值，`y5` 合并语义确认 patch 携带完整 modes map；UI 每家族下拉切换并发送合并 patch，复用回读/失败重试闭环（重发上次合并 map）。8 项相关新回归、496 项全量测试、analyze 0。
- **E1.2 追加 5**: indexing 节接入——官方取证确认 repo snapshot 开关发多键 patch（含 user-configured 标记）、instant grep 单键；controller 新增 updatePatch（多键 patch 整体去重/整体重试），UI 新增 _remoteTogglePatch 与索引节双开关。11 项相关新回归、499 项全量测试、analyze 0。
- **E1.2 追加 6**: conversation 节接入——显示推理/显示任务清单/模型 IO 保留三个单键开关与交互行为下拉（官方 queue/guide 两值，43 字段真实 wire 均有对应字段）；缺值时下拉隐藏不造选项。13 项相关新回归、500 项全量测试、analyze 0。
- **E1.2 追加 7**: 按官方 O1t/jB/AB/D1t 取证实现 migrateTeamSelectedKeys 组件——oauth 键迁 team-plan 键（URL 编码与 EntitlementSource 一致），unavailable/空身份/非 oauth 均跳过，读-合并-写更新；触发点为团队绑定事件流，待真实远端取证后接线，不发明设置页 UI。15 项相关新回归、504 项全量测试、analyze 0。
- **E1.2 追加 8（2026-09-11）**: 官方 bundle 确认 `subagentsService.list` 与 `commandsService.list` 是独立 bridge channel，不属于 43 字段 setting wire；新增只读 Subagents/Commands catalogs 和设置节（loading/empty/error/retry、scope/workspace path、generation 迟到保护），未接 `setCommandEnabled`。修复原 UI 回归用二次 pump 导致 Settings state 复用的问题，改为同页侧栏切换并验证内容互斥，再补空态/失败保留旧数据/重试清空/释放后迟到响应不写入。18 项相关测试、533 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-11/e1.2-agent-catalogs-2026-09-11.md`。
- **F1.5（2026-09-11）**: 已知音频推理通过——`.qa` 读取 16 kHz mono PCM16 WAV，用 whisper-tiny-en 离线推理输出 "This is a known audio test."，确认模型文件/绑定/解码链路；运行后停用模型并 force-stop QA 包。该项继续保留真实麦克风录音链路验证。证据 `build/visual-audit/takeover-2026-09-11/f1.5-known-audio-2026-09-11.md`。
- **F3.2（2026-09-11）**: 新增模块后又完成双端 `.qa` 原生长历史恢复复验——seed 后冷重启，手机恢复第 450 行/-84、平板恢复第 450 行/-104；verify 均加载两页、恢复精确偏移且无 conversation command。同时修正恢复 QA 证据目录未创建的问题。证据 `build/visual-audit/takeover-2026-09-11/f3.2-native-reading-recovery-2026-09-11.md`。
- **D2.4（2026-09-11）**: 新增双端 `.qa` 原生旋转隔离联测——portrait→landscape→portrait 后主草稿、辅队列和辅模型保持隔离，旋转不新增 conversation command；Android system QA 另验证根返回后台保留引擎并更新任务通知。证据 `build/visual-audit/takeover-2026-09-11/d2.4-native-rotation-background-2026-09-11.md`。
- **D3.2（2026-09-11）**: 官方 web remote platform 取证确认 `getInstalledEditors=[]`、`openInEditor` 明确返回 unsupported；ZcodeRemote 不复制桌面编辑器入口到远控审查页。该边界不再作为 D3.2 剩余项。证据 `build/visual-audit/takeover-2026-09-11/d3.2-open-in-editor-not-applicable-2026-09-11.md`。
- **E1.2（2026-09-11）**: Commands 目录从只读升级到 `setCommandEnabled` 合成写闭环——按官方语义传原命令对象和新 enabled，成功后强制 list 回读；失败保留旧值，UI 仅在 `userScopeAvailable` 且行有 enabled 值时显示开关，保存中转 spinner。20 项相关测试、535 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-11/e1.2-command-enabled-2026-09-11.md`。
- **D2.4**: 侧面板重开配置保持回归——主/辅确认配置 controller 层权威隔离，重开 obtain 同 scope 返回同一活跃 controller 且配置仍是辅面板自己的；501 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/d2.4-isolation-synthetic-2026-09-10.md`。
- **D2.4 追加**: 队列隔离回归——侧面板队列快照只在自己 conversation state，queueAction 经侧面板 sessionId 路由（fake 命令日志断言），主面板队列始终为空；502 项全量测试、analyze 0。
- **D2.2 追加**: 工具详情按官方结构拆分“调用”与“参数”两块——官方以独立 JSON 代码块渲染 input（JSON.stringify(r.input,null,2)）；参数区复用 monospace 代码面，input map 或 inputText 解析 JSON、fallback 原文。504 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/d2.2-args-split-2026-09-10.md`。
- **E1.3**: modelProvider 家族 mode 写入成功（回读确认）后失效连接 scope 的 composer prepared options（loadOptions refresh），写入失败不失效；技能运行时变化由 B1.3 覆盖，设置中心 skills 节只读无写入源。24 项相关测试、504 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/e1.3-prep-invalidate-2026-09-10.md`。
- **F4.2**: 旋转状态保持合成回归——竖屏→横屏→竖屏三次尺寸变化，主 composer 草稿与辅面板配置保持隔离；合成覆盖评估确认预测返回/键盘/铰链已有覆盖。505 项全量测试、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/f4.2-rotation-synthetic-2026-09-10.md`。
- **B2.2 预检**: 双模拟器在线、前台 .dev 用户状态保留；原生多类型组合的实施方案已定（attachment_types_test.dart：cacheDirectory 播种 + pick 拦截 + 慢上传取消/超限断言，.qa 运行）。证据 `build/visual-audit/takeover-2026-09-10/b2.2-native-plan-2026-09-10.md`。
- **B2.2 追加**: attachment_types_test.dart 已编写并两轮 .qa 运行——测试框架稳定，DocumentsUI 自动化多选可行（首次已选 3 项），但确认时序与坐标需单脚本全流程自适应解析；完整经验已固化到证据文件，下轮按单脚本执行闭环。
- **B1.2 追加**: ROG 只读探针补 session/slashCommands 数据源证据；修复 Composer `/` 能力候选因临时对象身份校验导致不可选，保留过期候选拒绝语义。UI 新增 session/command 候选回归，27 项聚焦回归、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/b1.2-references-real-2026-09-10.md`。追加 `.qa` 实际 APK 菜单验证 file/directory/plugin/session/user+workspace skill/command，run12 通过。
- **B1.3 收口**: `.qa` 实际 APK 验证失败重试、plugin/skill runtime 刷新、旧候选消失、可见标签与最终序列化；快速 scope/迟到/移除重插由合成状态层覆盖。证据 `build/visual-audit/takeover-2026-09-10/b1.3-reference-runtime-native-2026-09-10.md`。
- **B1.4 收口**: 五形态、折叠/平板两向、主辅面板、中英 140%、深浅主题、引用选择/焦点与 220px 键盘 inset 矩阵通过；相关回归 27/27。证据 `build/artifacts/b1.4-matrix-regression.log`。
- **B1.1 收口（2026-09-11）**: 手机 `.qa` 用 Trime 真实软键盘完成 `@$你好` 连续输入；`@/$` 通过长按候选弹层插入，拼音候选条点选提交，原子引用删除、焦点恢复与无发送断言全过。`ComposerInput` 补尾部退格整删引用回归。run11 通过、聚焦回归 28/28、全量 515/515、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/b1.1-real-ime-closure/run11-record-2026-09-11.md`。
- **D2.2 追加**: file-write/edit/delete 工具行增加官方 +N -N diffCount 角标，支持 output/raw/rawOutput 与 changes[].changeStat 汇总。official_detail 11/11、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/d2.2-tool-diffcount-2026-09-10.md`。
- **B2.2 收口**: 原生多类型组合通过——单脚本全流程（本周筛选 → 网格切换 → 坐标当轮解析 → 长按多选 → 确认）驱动真实 DocumentsUI 选择 image/text/binary 三文件，名称/mime/原生缓存 token/preview 字节断言全过（run7 log）。慢上传取消原生组合已通过——fake transport gate 在 picker 前挂起，验证进入 uploading；remove 首项经 isCancelled 中止并从列表消失，释放 gate 后其余附件 ready（run9 `00:17 +1: All tests passed!`）。

### F 阶段推进

- **F1.1**: 旧 Zemote 语音模块定位并迁移（6 模型目录、事件通知、存储 stub）。F1.2+ 受 Windows Developer Mode 阻塞。
- **F1.2 核心解锁**: 纯 Dart `archive` 成功引入，新增 Android `voiceModelsRoot` 通道后实现模型下载、进度、取消、bzip2/tar 解包、必需文件校验、失败清理和启用/禁用/删除。语音相关 7/7 通过、analyze 0；F1.2 仍待 UI/真实模型与原生验证。
- **F1.2 UI 进展（2026-09-11）**: 设置中心新增“语音模型”节，`VoiceModelManager` 显示模型状态并接入下载、进度、取消、重试、启用/停用与删除；失败保持未下载并可重试。相关设置/语音/UI 回归 23/23、全量 517/517、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/f1.2-model-ui-2026-09-11.md`。
- **F1.2 完整性进展（2026-09-11）**: `VoiceModelStore` 增加完整性清单与 SHA-256 校验；启用前强制验证，启用中的模型损坏时自动失效；`isDownloaded` 检查长度/记录；新增损坏压缩包、同尺寸篡改、截断文件测试。语音 10/10、全量 520/520、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/f1.2-model-integrity-2026-09-11.md`。
- **F1.2 原生根目录验证（2026-09-11）**: 新增 `integration_test/voice_model_root_test.dart`，平板 `.qa` 验证 `voiceModelsRoot` 返回 `.qa` 私有目录，`VoiceModelStore.directory()` 可创建模型目录，空目录 `isDownloaded=false` 并清理。日志 `build/artifacts/f1.2-native-root-run2.log`。
- **F1.2 真实模型收口（2026-09-11）**: opt-in .qa 集成测试下载 Whisper Tiny，验证三个提取文件长度/SHA-256/长度记录、启用/停用和失败不可用边界；语音模型/目录/管理 12/12 通过，analyze 0。证据 build/visual-audit/takeover-2026-09-11/f1.2-real-model-download-2026-09-11.md 与 build/artifacts/f1.2-real-download-run2-2026-09-11.log。
- **D3.3 中文 IME（2026-09-11）**: 手机 `.qa` 用 Trime 真实软键盘组合/候选提交「你好」，QA harness 检测提交后调用 `TerminalSessionController.write`，合成终端回显通过；终端相关回归 23/23、analyze 0。证据 `build/visual-audit/takeover-2026-09-10/d3.3-ime-real-soft-keyboard-2026-09-11.md`。
- **D3.3 工作面板下标修复（2026-09-12）**: `WorkspaceShell` 的 summary/terminal `IndexedStack` 映射与子节点顺序相反，导致窄屏 overlay 恢复后互相显示错页。已改为 side=0、summary=1、terminal=2，并补 360×760 真实场景 stack 回归；针对性 20/20、全量 579/579、analyze 0、smoke 通过，手机覆盖安装读回同哈希。证据 `build/visual-audit/takeover-2026-09-12/d3.3-panel-index-fix-2026-09-12.md`。
- **D1.1 顶栏官方成对（2026-09-12）**: 同 ROG-STRIX/同任务只读 CDP 与手机 `.dev` 成对对照确认 Git main/dirty、More、工作面板和远控门控；Git/分支/官方详情 18/18，当前源码全量 579/579。证据 `build/visual-audit/takeover-2026-09-12/d1.1-top-bar-official-pair-2026-09-12.md`。
- **F1.3/F1.4 本地闭环（2026-09-11）**: 接入 `record`/`sherpa_onnx`，迁移离线 `SherpaVoiceTranscriber`；新增 `VoiceInputController` 状态机与 Composer 麦克风入口，覆盖请求、录音、识别、错误、取消、释放、作用域切换、迟到结果丢弃和不自动发送。相关状态回归 4/4、全量 527/527、analyze 0、Android x64 debug 构建通过。证据 `build/visual-audit/takeover-2026-09-11/f1.3-voice-input-local-2026-09-11.md`。真实麦克风链路仍为 `BLOCKED_EXTERNAL`。
- **C1.1 上下文排序对齐（2026-09-12）**: 官方 AZe 检索确认未知来源 NaN→稳定出现序；本地从"末位+字母序"改为 firstSeen 出现索引 tie-break，7 项来源顺序表与官方 AI 一致。official_detail 14/14、全量 557/557。证据 `build/visual-audit/takeover-2026-09-12/c1.1-context-order-alignment-2026-09-12.md`。
- **D3.4 倒计时对齐（2026-09-12）**: 官方 JS 检索确认 uct 剩余秒 `max(1,floor)`、progress clamp 公式、snoozed 隐藏、consumeSnooze/releaseSnooze 去重与失败恢复均与本地一致；本地 ceil 差异已对齐官方 floor。专项 7/7、全量 557/557。证据 `build/visual-audit/takeover-2026-09-12/d3.4-countdown-alignment-2026-09-12.md`。
- **D2.2 task-control/message 工具行实现（2026-09-12）**: 按官方 Trt/xrt/crt/drt 字段实现 TaskOutput/BashOutput/TaskStop/KillShell（task-control 族，taskId/shell_id 提取）与 RespondToCoordinator（message 族，summary 渲染）。official_detail 14/14、analyze 0、全量 557/557。证据 `build/visual-audit/takeover-2026-09-12/d2.2-task-control-message-local-2026-09-12.md`。
- **D2.2 Skill 工具行实现（2026-09-12）**: 按官方 XJ 形态实现 Skill 行：family `skill` + sparkles 图标 + `input.skill.name` 嵌套取值 + `skillMetadata.qualifiedName` fallback。official_detail 13/13、analyze 0、全量 556/556。证据 `build/visual-audit/takeover-2026-09-12/d2.2-skill-card-local-2026-09-12.md`。
- **D2.2 官方工具卡映射补全（2026-09-12）**: 官方 web 87 个 JS 落盘本地检索，取得工具行 family→组件完整 switch 映射与特殊 toolName 分支（Agent/Task output.truncated 透传、Skill skillMetadata.qualifiedName/pluginId、TaskOutput/RespondToCoordinator 分支）。官方 UI 文档同步。本地差异核查项新增：Skill 行元数据展示、TaskOutput/RespondToCoordinator 形态对照（待真实数据）。证据 `build/visual-audit/takeover-2026-09-12/d2.2-official-tool-card-mapping-2026-09-12.md`。
- **E1.2 模型供应商只读 catalog（2026-09-12）**: 基于官方 getAll schema 实现 `ModelProvidersCatalog` 与设置中心只读供应商目录（loading/error 重试/空态/供应商行+模型行详情，apiKey 只记 hasApiKey 不外显；generation 迟到丢弃与失败保留旧数据）。catalog 3/3、client_settings 17/17、analyze 0、全量 555/555。写操作 save/delete/saveDisplayOrder 仍未实现（需授权）。证据 `build/visual-audit/takeover-2026-09-12/e1.2-model-provider-catalog-local-2026-09-12.md`。
- **E1.2 model-provider wire 取证与探针输出名修复（2026-09-12）**: 官方 87 个 JS 确认供应商/模型行 CRUD 走独立 model-provider channel；新增 ZCODE_PROBE_MODEL_PROVIDER_ONLY 只读探针取得真实 getAll schema（13 供应商、models 行结构完整、值脱敏）。探针输出名补齐 modelProvider/interactions 专属映射（此前 interactions-only 会覆盖默认 parity 文件，已重跑恢复），D3.4 interactions 证据改指 official-interactions-probe-ROG-STRIX.json 并确认无 pending。全量 551/551、analyze 0。证据 `build/visual-audit/takeover-2026-09-12/e1.2-model-provider-wire-2026-09-12.md`。
- **E1.2/V1.3 官方设置页批量取证（2026-09-12）**: 外观（界面字号 14px 默认、代码主题分离）、模型设置（供应商列表/连接方式下拉/套餐卡/模型行 CRUD）、插件（8 内置行+三 tab）、MCP 聚合页（2 自装 stdio+宿主插件分组）、钩子空态均已 1180 宽留证。模型行 CRUD 本地未实现，需官方写 wire format 取证（需授权），记为 E1.2 差异核查项。证据 `build/visual-audit/takeover-2026-09-12/v1.2-official-settings-capture-2026-09-12.md`。
- **D3.4 握手 capability 对齐（2026-09-12）**: 官方 gb() 在 clientHello 显式声明 `capabilities:{workspaceHookReviewUi:true}`（服务端可能据此门控 hook review 数据下发）；本地握手补齐该声明并加协议断言。handshake 3/3、analyze 0、全量 559/559。证据 `build/visual-audit/takeover-2026-09-12/d3.4-handshake-capability-2026-09-12.md`。
- **D2.3 assistant Feedback 实现（2026-09-12）**: 官方 kX 复核确认远控下 like/dislike 可见可点（旧取证误读），本地补齐 Feedback UI（乐观更新/清除/回滚/迟到保护，协议 setAssistantFeedback 已有）。message_actions 7/7、全量 558/558。Retry 无按钮判定复核维持。证据 `build/visual-audit/takeover-2026-09-12/d2.3-assistant-feedback-2026-09-12.md`。
- **E2.1 断开连接语义判定修正（2026-09-12）**: 官方 JS 证据（quickPick logout keywords 含断开连接/登出、i18n logoutAction=断开连接）确认远控「断开连接」即 logout 动作文案；此前"远控无登出项"判断修正。本地 Logout 语义一致，文案差异留 V1.3。证据 `build/visual-audit/takeover-2026-09-12/e2.1-disconnect-semantics-2026-09-12.md`。
- **V1.2 官方侧素材重新取证（2026-09-12）**: 2026-09-10 的 AUTH_FAILED 已不复现，新 remote URL（ROG-STRIX）配对成功。以 Chrome headless CDP 1180x820 只读导航+截图，取得官方会话页（最新位置）、账户菜单、使用统计应用用量/个人套餐两 tab、设置常规页。确认官方个人套餐为四卡布局（含 ZCode MCP 独立卡与说明 icon）、活跃度 KPI 行、设置侧栏三分组结构与远控菜单无登出项。未发送任务/命令/写设置。app 侧最终配对留 G1.2。证据 `build/visual-audit/takeover-2026-09-12/v1.2-official-side-capture-2026-09-12.md`。
- **D3.4 Hook banner 刷新修复（2026-09-12）**: `WorkspaceHookReviewBanner` 本地 dismiss 后未重建（StatelessWidget 未监听 controller，ChatPage 只监听 conversation state）；改用 `ListenableBuilder` 驱动重建，dismiss 回归新增 UI 消失断言。专项 7/7、analyze 0、全量 551/551。证据 `build/visual-audit/takeover-2026-09-12/d3.4-hook-banner-refresh-2026-09-12.md`。
- **D3.4 Hook admission 接线（2026-09-12）**: 官方 schema 确认 snapshot 独立 `workspaceHookAdmission{pendingCount,bundleDigest,workspaceIdentity?}`；本地解析该字段，admission 计数>0 时优先显示官方文案横幅，去审核打开设置 hooks tab 并发送 `requestWorkspaceHookReview`，忽略按 `sessionId+bundleDigest` 隔离。`pendingCount<=0`/null 时保留原 pendingInteractions review 流。请求按会话/身份/digest 去重，不发明或删除 pending。专项 10/10、analyze 0、全量 562/562、protocol smoke passed。证据 `build/visual-audit/takeover-2026-09-12/d3.4-admission-wire-2026-09-12.md`。
- **E1.2 model-provider 模型行 CRUD（2026-09-12）**: 官方 JS/schema 确认 `save(provider)` 整包保存与模型行 `{id,name,kinds,defaultKind,modalities,contextWindow,...}`；本地在 model-provider 目录接入模型添加/编辑/删除，成功后 getAll 回读，失败保留旧目录，同 provider 在飞去重；UI 不外显 API key，payload 沿用原始 provider 防止 endpoint/凭据元数据丢失。成功保存确认后联动刷新 Composer prepared options（E1.3）。专项 23/23、analyze 0、全量 567/567、protocol smoke passed。证据 `build/visual-audit/takeover-2026-09-12/e1.2-model-provider-model-crud-2026-09-12.md`。
- **E1.2 model-provider 自定义供应商删除（2026-09-12）**: 按 official `delete(providerId)` 接入自定义供应商删除；`source != custom` 在状态层直接拒绝，UI 确认后才发送。成功后强制 `getAll` 回读并刷新 Composer prepared options；失败保留旧目录，错误按 delete operation 展示，API key 不外显。删除与模型保存共用 provider 在飞门控，dispose/换 scope 保护沿用。专项 27/27、analyze 0、全量 571/571、protocol smoke passed。证据 `build/visual-audit/takeover-2026-09-12/e1.2-model-provider-delete-2026-09-12.md`。
- **E1.2 model-provider 自定义供应商新建（2026-09-12）**: 官方 custom endpoint 表单接入名称/Base URL/API Key/三种 API 格式与至少一个初始模型；payload 使用整包 `save(provider)`，路径与 defaultKind 按官方映射生成。失败保留表单可重试，成功 `getAll` 回读后刷新 Composer prepared options；空目录创建/最后删除刷新缺陷与 omitted `enabled` 默认 true 已修复。专项 40/40、analyze 0、全量 574/574、protocol smoke passed。证据 `build/visual-audit/takeover-2026-09-12/e1.2-model-provider-create-2026-09-12.md`。
- **E1.2 model-provider display order（2026-09-12）**: `getAll` 后读取 `getDisplayOrder` 并按官方 providerIds 投影；上移/下移发送 `{providerIds,updatedAt}`，失败回滚旧顺序并记录 display-order 错误，成功权威回读且 Composer prepared options 恰好刷新一次。display order 读取失败按官方语义回退 getAll 顺序。专项 43/43、analyze 0、全量 577/577、protocol smoke passed。证据 `build/visual-audit/takeover-2026-09-12/e1.2-model-provider-display-order-2026-09-12.md`。
- **E1.2/V1.3 钩子管理列表页（2026-09-12 第七批）**: 更正第三批「hooks 列表 RPC 取证不足」误判——js-1 内 `hooksService.loadHooks/saveHooks`（全列表保存）与 hook 行模型（WXt/GXt/P7 editable 投影）完整可得；新增 `WorkspaceHook`/`HooksCatalog`（loadHooks 读取 + saveList 整列表保存，在飞去重、失败按 errorId 保留重试、generation 防迟到），钩子节重建为官方管理列表（chrome 骨架+行开关整表保存；插件来源行只读）。client_settings 25/25、全量 597/597；阶段 `v13-settings-batch7` APK `8150f74d…` 双端同哈希。证据 `build/visual-audit/takeover-2026-09-12/e1.2-hooks-list-batch7-2026-09-12.md`。
- **E1.2/V1.3 钩子新建/编辑/删除表单（2026-09-12 第八批）**: 字段语义逐项对齐 js-1——事件固定 7 项（XXt，默认 PreToolUse）、类型 process（默认）/command、matcher+hint、命令必填、process 参数每行一个（空行忽略）/command 异步开关+Shell、高级折叠组（状态信息/超时 Number.parseInt||60/自定义 JSON 对象校验 customJsonParseError 与 customJsonObjectError 两文案，非法禁存）；`WorkspaceHook.buildCreateRaw`（WXt+UXt：`hook-<uuid>`、空可选字段省键、location zcode/user）与 `withFormUpdate`（GXt spread：保留 id/location/enabled，类型切换摘除不适用键）；删除两步确认走整表 saveHooks；保存失败保留表单可重试，成功经 loadHooks 权威回读后关闭；操作行 Wrap 修复「确认删除」态 22px RenderFlex 溢出（storageLevel 固定 user：project 变体无落盘真实样例；importHook 交互形态未捕获不发明）。client_settings 28/28、全量 600/600、analyze 0、smoke 通过；阶段 `v13-hooks-form` APK `67a24f6b…` 双端同哈希（268 源文件）。证据 `build/visual-audit/takeover-2026-09-12/e1.2-hooks-form-2026-09-12.md`。
- **D4 后台任务取消闭环（2026-09-12）**: 官方 schema 确认 snapshot `backgroundWorks{workId,kind,title,status,cancellable,...}`；本地新增 `cancelBackgroundWork{workId}`、running bash/subagent 投影、cancellable 门控、在飞去重、失败保留和权威 state 清理。ChatPage 显示官方后台任务横幅。专项 2/2、analyze 0、全量 564/564、protocol smoke passed。证据 `build/visual-audit/takeover-2026-09-12/d4-background-works-2026-09-12.md`。
- **F3.2 新增模块恢复核查（2026-09-11）**: 恢复相关测试 67/67 通过，覆盖恢复导航/草稿/附件/面板、终端面板与会话、Diff Review、Interaction Requests 和新增 VoiceInput 状态。最终同代码双端冷启动复验仍留 G1。日志 `build/artifacts/f3.2-recovery-related-tests-2026-09-11.log`。
- **本轮验证**: 引入 archive 与语音存储核心后全量 Flutter 回归 514/514 通过，Android x64 debug 构建通过，`.dev`/0.1.0(10) 包名与 x86_64 引擎核对成功。
- **F2.1/F2.2**: UpdateDownloader 实现（下载/进度/取消/重试/MD5 校验/临时文件清理），设置页接入下载 UI。
- **F2.3**: 修复 Android 安装交接阻断——manifest 补 `FileProvider`、`file_paths.xml` 和 `REQUEST_INSTALL_PACKAGES`；集成测试通过，平板 MuMu 系统安装器实际打开并完成 `.dev` APK 更新，Open 后焦点回到安装应用。
- **F2.4**: 版本、构建号和更新仓库常量与当前产品对齐，守护测试已补 `updateRepo`。
- **F2.1/F2.2**: UpdateDownloader 与设置页下载 UI 收口；安装后 base.apk 包名/版本/签名复核通过。
- **B1.4**: 补键盘 inset + 140% 字号的 344/720/834/1180 主/辅面板矩阵回归。
- **D2.2**: 工具大输出默认预览并支持按需展开/收起。

### V 阶段推进

- **V1.1 收口**: 最终代码矩阵完成——344/390/720/834/1180 × 深浅 × 中英 × 100/140% 的 base + 主辅面板，344/1180 键盘 inset，以及 empty/loading/error 两端点组合。144 张真实 Flutter 渲染图、目标回归 11/11、analyze 0。过程中发现并修复 `ChatPage.didUpdateWidget` 外部 sessionId 切换不重订阅，以及 interaction/hook 控制器在订阅复用时的残留。证据 `build/visual-audit/takeover-2026-09-10/v1.1-final-matrix-2026-09-10.md`。

### 验证状态

- 577 项全量测试通过
- flutter analyze 0 issues
- protocol smoke passed
- 全部证据保存至 build/visual-audit/takeover-2026-09-10/

### 外部阻塞

- E1.2 provider connectivity test：当前官方 bundle 仅确认方法名，未取得 request/response schema；真实连接测试可能使用凭据/外部 API，必须先取证并获授权，禁止按方法名猜测 payload。
- Windows Developer Mode 未启用：F1 原生插件（archive/record/sherpa_onnx/path_provider）无法注册
- 真实远端连接：D1-D4 只读取证、官方成对同态对照、E1.2 内容填充


## 2026-09-12 设置中心官方结构批次（第四~六批）与 F3.2 最终复验

- **V1.3 第四批 常规节官方结构（v13-general-batch4）**: 官方 js-1 取证确认常规页 terminalInheritSystemProfile/terminalFontFamily/integratedTerminalShell/nativeSearchEnhancementsEnabled/httpProxy 三键/toolGrouping 三键均来自 settingService.get，逐键单 patch update 保存；官方目录无「对话」节（settings.conversation 仅埋点 featureId）。本地 RemoteSettingsSnapshot 新增 11+5 字段解析（缺键保持 null 区分官方默认），general 节重排为官方四卡结构（语言徽章 chip/终端卡含 win32 门控集成 Shell 与字体输入/HTTP 代理三输入/行为卡并入对话节内容+自动处理提问/归档卡），文本输入 trim+dirty+Enter+成功回同步+失败保留重试；侧栏移除「对话」节；systemService 只读探测（info/listIntegratedTerminalShells，失败降级，generation 防迟到）。阶段 `v13-general-batch4` APK `691d6f23…` 双端同哈希（268 文件冻结）。证据 `build/visual-audit/takeover-2026-09-12/v1.3-general-batch4-2026-09-12.md`。
- **V1.3 第五批 记忆/索引库/浏览器控制（v13-settings-batch5）**: 记忆节官方卡片（工作区记忆+描述）+ 虚线桌面端提示卡（`_DashedNoteCard`，CustomPaint 虚线圆角）；索引库节官方「代码库」组与官方标签（索引新文件夹/索引存储库以实现即时搜索（测试版））；浏览器控制开关经 pluginManagement setPluginEnabled 驱动 `browser-use@zcode-plugins-official`（官方 `_({U7},e,pluginManagementService)` 取证），桌面专属「允许不安全证书」security section 按官方 isDesktop 门控移出远控 UI（快照字段与写证据保留），导入/清除按钮因 platform 服务 wire 未捕获不实现。阶段 `v13-settings-batch5` APK `20612d3c…` 双端同哈希。证据 `build/visual-audit/takeover-2026-09-12/v1.3-settings-batch5-2026-09-12.md`。
- **V1.3 第六批 目录页骨架（v13-settings-batch6）**: 新增 `_catalogChrome` 官方共享骨架（作用域 pill+计数+本地搜索+「已安装 N」+刷新+虚线空态卡），子智能体/命令/技能/MCP 四节由纯文字列表重建为卡片行（命令行保留已验证 setCommandEnabled 开关），插件节内联已安装插件行（复用 setPluginEnabled）。js-1 中 subagentsService 零方法调用（传输在未捕获 chunk），「新建」「继承默认」、技能「新建/导入」、MCP 启停等写链路无验证 wire 一律不实现。阶段 `v13-settings-batch6` APK `f6950131…` 双端同哈希（268 文件冻结）。证据 `build/visual-audit/takeover-2026-09-12/v1.3-settings-batch6-2026-09-12.md`。
- **F3.2 最终恢复复验（2026-09-12）**: 最终同代码双端 `.qa` 冷重启阅读恢复 seed/verify 通过——seed 保存 row 450 / offset -84，verify 经 2 页分页恢复且无 conversation command（手机与平板结果一致）。日志 `build/artifacts/f3.2-final-tablet-seed-2026-09-12.log`、`f3.2-final-tablet-verify-2026-09-12.log`、`f3.2-final-phone-seed-2026-09-12.log`、`f3.2-final-phone-verify-2026-09-12.log`。新增终端/Diff/Voice/设置模块的持久化边界沿用 2026-09-10/11 代码审查结论（terminal 不持久化、Diff 会话作用域、workspaceViewStates/sideChats/恢复日志持久化）。
- **G1.2 本地部分（2026-09-12）**: 最终同代码构建核对——`.dev` 包名、0.1.0(10)、ARM64+x86_64 引擎、签名 `b020bef5…a4857`、SHA-256 逐阶段记录（batch4 `691d6f23…`、batch5 `20612d3c…`、batch6 `f6950131…`），双端 `install -r --abi x86_64` Success 并 pull 读回同哈希；quotaReadOnlyAudit=true 重启前台正常。桌面会话恢复后仍需补：官方成对对照批次与关键流程真机联合验证。
- **验证状态**: 全量 flutter test 596/596、analyze 0、protocol smoke passed（每批次收口均执行）。
- **外部阻塞**: ROG-STRIX 桌面端远控会话关闭（连接失败截图 `build/visual-audit/takeover-2026-09-12/v1.3-general-batch4-native/tablet-connect-state.png`）——官方成对对照、真实写/账户验证、真实麦克风、ColorOS 真机等继续挂起；完整清单见 `build/visual-audit/takeover-2026-09-12/g1.1-remaining-audit-2026-09-12-batch6.md`。

## 2026-09-12 设置中心对齐批次（第九~二十二批）与落盘 wire 再取证

- **第九~十八批（V1.3 locale/子智能体/账户/命令 CRUD/双栏/套餐卡/钩子/插件）**: 逐批证据与阶段 APK 见 `references/v2-progress-todolist-2026-09-09.md` 头部与各批次证据文件（`build/visual-audit/takeover-2026-09-12/v1.3-*.md`、`e1.2-*.md`、`e2.1-*.md`）。要点：常规节 locale 全量校对（batch9）、子智能体官方分组（batch10）、账户菜单「断开连接」真实语义（e21-disconnect）、命令文件 CRUD wire 落地（e12-commands-crud）、模型设置官方双栏（batch13）、套餐卡日期行+额度 tile（batch14）、外观描述行（batch16）、钩子/插件节官方 chrome+空态（batch17/18）。
- **第十九批 空态卡组合+chrome 建钮（v13-empty-cards-official, APK `8f37c395…`）**: `_OfficialEmptyCard`——五节空态统一官方「标题+描述+按钮整体居中于整行宽虚线卡内」；chrome 新建钮移刷新右侧改实心；命令计数去「项」；钩子「以往任务」→「以在任务」错字修正；浏览器注释卡左对齐。证实 indexing2/skills2/commands2 编号截图为同一张使用统计误标图。
- **第二十批 搁置 wire 重取证+命令页文案（v13-commands-locale-official, APK `607c4e7e…`）**: commands `agentSource` 真实值=`zcodeAgent`（update/delete 回传条目值与本地一致）；来源筛选 locale 存在但菜单结构未证实不实现；命令分组 用户命令/插件命令；表单官方全规格（标题+描述/可选标签/占位符/校验拆分）；删除确认官方文案；命令导入=桌面 symlink/copy 能力不实现；技能新建=任务流边界；MCP mcpSyncService 均同步管道。
- **第二十一批 qXt 交叉验证+钩子/套餐卡文案（v13-hooks-plan-locale-official, APK `54d673f0…`）**: qXt 本体=`saveHooks({workspacePath,workspaceIdentity?,hooks})` 与本地 HooksCatalog 逐字段一致（写链路双重验证）；planCard 官方标签 5h 用量/1w 用量（totalTokens 不能映射 monthlyTool——TIME_LIMIT(5,1) 证据）；钩子 matcher 空=匹配全部；列表补官方 sessionSnapshot 提示。
- **第二十二批（本批，仅文档+第四轮取证，无代码改动）**: ①钩子信任交互 wire 完整取证——`respond_workspace_hook_review` 严格 schema：`{remoteSessionId?, sessionId, bundleDigest: /^[a-f0-9]{64}$/, reviewFlowId, generation: positive int, interactionId, decision: enum, workspaceIdentity 在 remoteSessionId 场景必填}`，属 D3.4 官方 Interaction Request 族首个完整 schema（实现待真实交互流+用户决策，归因不变）；②套餐卡「管理/解绑」键证实（codingPlan.manage/disconnect），动作为真实账户/套餐写，维持需授权边界；③G1.3 文档增量：v2-implementation/v2-goal-acceptance 补齐第九批以后概览（本节）。 另补第二十三~二十六批：D3.4 官方交互类型目录与三份取证附录（`build/visual-audit/takeover-2026-09-12/d3.4-official-interaction-catalog-2026-09-12.md`）——Eg 七成员 schema、oc/tc 决策枚举（allow/deny/escalate/modify）、Sg 四成员与状态基座、goal_verification/timeline/subagent/compact 流行 schema、permissionUpdates=addRules{behavior,rules[{toolName,ruleContent?}]}、rl 跨 chunk 未定义定案；本地覆盖对照（resolveInteraction/钩子四命令/队列族已覆盖；timelineType 合成分隔行族待真实流截图）。
- **验证状态（每批收口均执行）**: flutter analyze 0、全量 604/604、protocol smoke passed、12 节渲染、阶段 APK 双端 `install -r --abi x86_64` + pull 读回同哈希、quotaReadOnlyAudit=true 重启、源码 269 文件冻结。
- **外部阻塞（不变）**: ROG-STRIX 桌面端远控会话「连接失败」（r24~r28 截图序列）——官方成对同数据像素对照（D3.1→D3.3→D2.2→D3.4→V1.3）、真实写/账户验证、钩子信任复审实现、真实麦克风、ColorOS 真机等挂起；巡检 automation-c1889439 每 20 分钟核验。
- **2026-09-12 batch27-29 增量（规则 24 合成实现 + 测试守护收口）**:
  - **第二十七批**: GoalVerificationRow（status 四态 started/completed±passed/failed_closed/cancelled、reason/nextAction/迭代号、separator 形态、raw synthetic 与展平 kind 双 wire 形态识别）挂入 chat_page `_rowWidget` 分派；WorkspaceMonitor.handleTaskSnapshotInvalidated 具名处理（标记过期→refreshTasks 重同步→完成清除、重复通知合并、isSnapshotStale 查询）；合成测试 10 用例（8 渲染+2 失效链路）；阶段 `v13-goal-verification-row`（APK `9d71dedd…` 双端同哈希，全量 614/614）。证据 `v1.3-goal-verification-row-2026-09-12.md`。
  - **第二十八批**: 规则 24 剩余候选评估——钩子信任复审 UI 本地渲染已达标（interaction_request_card/hook_review 25 测试绿）；命令来源筛选菜单结构与 MCP 启停 wire 结构性缺失维持外部阻塞，不做猜测实现。
  - **第二十九批**: 重扫发现 batch27 接线缺 chat_page 行路由贯通守护——补 ChatPage 快照注入测试覆盖 raw synthetic（守卫分支）与展平 kind（显式分支）双形态路由及迭代号断言；全量 615/615（+1）、analyze 0；阶段 `v13-goal-verification-routing`（APK 同二进制 `9d71dedd…` 无需重装、源码包 `2662ec2f…`、271 文件冻结）。证据 `build/visual-audit/takeover-2026-09-12/goal-verification-routing-test-2026-09-12.md`。连接失败截图序列推进至 r43/r44（07:23/07:33）。
  - **第三十批**: r45 仍连接失败（二十一连）；测试守护面延伸——changeSummary 分派仅有组件直测、subagent 行分派会话流层面零测试，新增 `chat_row_dispatch_test.dart` 两用例（ChatPage 快照注入：变更摘要卡头部计数/增删行统计/展开文件行、subagent 类型·状态—摘要文本）；analyze 0、全量 617/617（+2）；阶段 `v13-row-dispatch-guard`（APK `9d71dedd…` 同二进制、源码包 `45b23527…`、272 文件）。证据 `chat-row-dispatch-guard-2026-09-12.md`。截图序列推进至 r45（07:35）。
  - **第三十一批**: r46 仍连接失败（二十二连）；CHANGELOG 核验无欠账（batch19~27 已收录）；三阶段冻结产物链完整性核验通过（manifest/APK/源码包齐全、哈希互证）；batch29/30 补 protocol smoke 通过（日志 `build/artifacts/v13-row-dispatch-guard-protocol-smoke.log`）。
  - **第三十二批（2026-09-12 下午，接管阻塞解除）**: 本会话目标提供新官方远控配对 URL，ROG-STRIX 桌面远控会话恢复（Web Remote Control 连接成功）；基线核验双端 base.apk（adb pull）=`v13-row-dispatch-guard`（9d71dedd…）。官方侧只读取证：D3.1 收起/展开/diff 面板三态、D2.2 终端工具卡、D3.3 官方终端=底部抽屉（更正 D1.2 顶栏判定）。桌面任务恢复运行后本会话让渡官方 web 席位（规则 5.2）。证据 `build/visual-audit/takeover-2026-09-12/d31-d22-d33-official-capture-yield-2026-09-12.md`。
  - **第三十三批（D3.3 结构修复，阶段 `d33-terminal-drawer` APK `defb9e6fd5b5f69865b96b613ad046c2809793953f671b65fe902c9576585b50`）**: shell_layout 新增 bottomPanel 槽位（320 高底部抽屉）；终端迁出侧面板 IndexedStack（枚举收敛 summary/sideChat）；顶栏新增「切换终端」square-terminal 按钮；TerminalDrawer 官方 chrome（终端标签+shellLabel 命名 tab+活动 X+新建+抽屉关闭，workspace 监听重建）；LocalHistoryEntry 预测返回/Ctrl+J/命令中心 toggleTerminal·addTerminalTab 接线；TerminalPanel 移除旧 InputChip 行。新增/迁移回归：抽屉标签栏生命周期、窄屏侧面板与抽屉独立性。全量 617/617、analyze 0、smoke 通过；源码 ZIP `9563f86b…`（272 文件）；双端覆盖安装读回同哈希；平板真机验证抽屉真实 create/dispose 全链。
  - **第三十四批（D3.1 快速对齐，阶段 `d31-summary-official` APK `1f608c23f9e810b273ca2fdb58500c470a3b9c7a95e9e47233de1a278cd1f467`）**: changeSummary 撤销按钮迁至头部行（官方位置，canRewindFiles/rewindOpen 门控不变，展开体旧块移除）；文件行改官方结构——file/file-text/file-code/file-image 四个 Lucide 文件族图标新增（官方品牌文件图标以 Lucide 近似记录）、名称/目录拆分（basename prominent+dir subtle）；chat_row_dispatch 断言更新。全量 617/617、analyze 0、smoke 通过；源码 ZIP `b575c3c1…`；双端同哈希。剩余：审查→独立 diff 面板+切文件、同数据 app 侧成对（G1.2 联合）。
  - **第三十五批（D3.1 ①收口，阶段 `d31-review-panel` APK `90d7dbfddb49ab4935ea2d736d767c8f95d8aa45499643e28120f6db29ec8ddd`）**: 新增 `lib/ui/file_changes_review_panel.dart`——FileChangesReviewPanel（官方 diff 面板 chrome：文件 tab 栏+活动 X+面包屑名称/目录+±计数+hunks+loading/error/retry+binary/裁剪消息+didUpdateWidget 动态加 tab+最后 tab 关闭收面板）、FileChangesHunksView 共享 hunks 渲染（chat_page 内联改复用）、FileChangesReviewHost InheritedWidget（shell 包裹会话内容，changeSummary 文件行新增真实「审查」按钮；无 host 隐藏，内联选择式 diff 保留为回退）。shell 新增 `_WorkPanel.review` 形态与 shell 持有控制器（`_openFileReview` 按 rowId|entityId|设备|工作区|会话 键控，行虚拟化回收安全，dispose 释放）。新增面板回归 3 用例；全量 **620/620**、analyze 0、smoke 通过；源码 ZIP `d31f9da8…`（274 文件）；双端覆盖安装读回同哈希。真机受限：深历史翻页未达最近 changeSummary 行，面板真实数据 E2E 归 G1.2 联合批次。
  - **第三十六批（D3.2 官方撤销弹窗对照，阶段 `d32-rewind-copy` APK `02a0bf6c4461104ceb97485f244869a0fcd3dc905dbfe4a5ffcc8b1af34cba94`）**: 桌面任务空闲窗口重开官方页核验——最新 changeSummary 仍为「10 个文件已更改」（昨天 23:39），无更近触发、无真实 pending 交互（`official-dom-03/04-bottom-check.txt`）；趁席位空闲完成 D3.2 官方视觉剩余——真实 10 文件行点「撤销」→ 官方「撤销文件改动」预检弹窗取证（标题/说明行/「可安全撤销 2」/「不能安全撤销 8」/红色「撤销文件」按钮，`d3.2-official-pair/official-rewind-dialog-1180.png`），与本地 rewindFiles preview 实现逐项一致；仅只读预检并立即取消，未执行 apply。唯一一字说明文案差异（改过→修改）已修；analyze 0、全量 620/620、smoke 通过；源码 ZIP `6b35d2de…`（274 文件）；双端覆盖安装读回同哈希。官方页随后关闭释放席位。D3.2 剩余收敛为同数据像素对（与 D3.1 同挂起条件：待更近真实摘要行出现）。
