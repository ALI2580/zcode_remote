# 官方功能对齐清单（2026-09-09，进行中）

当前接续入口：[进度、详细 TodoList 与开发手册](D:/WorkSpace/ZcodeRemote/references/v2-progress-todolist-2026-09-09.md)。0.1.0+10 已完成侧栏成员状态/连续长按和 Android 富文本辅助功能修复，双端任务管理及 368 项测试通过；阶段产物已归档，完整视觉/数据组合和其余范围继续保持未完成。旧阶段说明保留历史语境。

本批承接对“只修零散样式、未补齐实际能力”的反馈。以下项目全部属于本批目标，不因现有测试通过而缩小范围。源码依据为当前官方 `index-nOVzQNKW.js`、`src-DHgFesxz.js`、`IntlProvider-BDZANi-i.js` 及 `index-BMndL2ru.css`；首次完整资产索引见 `official-web-baseline.json`。

完整 A–F 与交付范围见 [全局验收清单](v2-goal-acceptance.md)。以下条目均保留实际对照与安装验收，代码/测试通过不自动升级为验收通过。

## 验收清单

最新自动维护补充：0.1.0+9 已接入 `hXe/rI/EXe/AXe/oI` 对应的可见轮询、授予、历史已读、外部完成和动效。写入均以合成传输验收；真实桌面启动额度只读模式。363 项测试、双端原生流程和安装通过，详见 [阶段证据](v2-maintenance-acceptance-2026-09-09.md)。下方 0.1.0+7/+8 的未完成说明保留其历史语境；当前剩余包括实际辅助功能缺陷和完整数据/页面对照。

| 区域 | 官方依据与完整行为 | 当前状态 | 完成证据 |
| --- | --- | --- | --- |
| 侧栏任务行 | `KEt`：左图钉/未读/忙碌图标；右相对时间，交互时图钉与归档；归档二次确认；已归档可恢复/删除 | 已实现待验证；图钉/未读/切换状态、确认和触屏菜单已接入 | test/ui/task_navigation_test.dart；MuMu 新侧栏截图 |
| 任务索引 | `ECt/XEt`：置顶任务独立分区、不在项目重复；按项目/时间线；更新时间/创建时间排序；归档视图；跨项目范围和实时更新 | 已实现待验证；全索引、独立置顶、视图/排序；修复缺字段与迟到覆盖 | test/state/workspace_catalog_test.dart；test/ui/task_navigation_test.dart |
| 侧栏工具 | `jjt/er`：项目标签、全部展开/折叠、筛选排序、独立归档按钮；新任务、搜索、插件市场；手机可达 | 已实现待验证；含折叠项目未读点和切换去重 | test/ui/task_navigation_test.dart；build/visual-audit/goal-2026-09-09/ |
| 任务操作 | `ZCt`/`XEt`：置顶、重命名、归档、未读、恢复、已归档删除；作用域包含 workspace/task，失败状态不伪造成功 | 已实现待验证；写入失败保留原状态，删除仅已归档任务 | test/ui/task_navigation_test.dart；真实写入仍用假传输 |
| 远控门控 | `jjt`：远控不显示桌面定时任务、自定义分组/项目重排入口；客户端设备选择保留 | 验收通过；仅限本行侧栏入口门控，设置账户等仍独立核查 | 下方门控证据；TaskNavigation / WorkspaceShell；双 MuMu 侧栏截图 |
| 加号菜单 | `gRe/dRe/vRe`：模式左侧 plus；添加附件、@ 上下文、/ 能力、$ 技能；选择后恢复输入焦点 | 已实现待验证；菜单入口、引用选择与焦点恢复通过控件测试 | test/ui/composer_features_test.dart；MuMu 输入入口截图 |
| 引用候选 | `UA/NIe/zIe`：文件/目录、会话、插件、技能、能力候选，真实目录/会话范围；准确 Markdown 序列化；中文 ¥/￥ 与组合输入 | 已实现待验证；真实 ROG 文件 6,180 项、技能 15 项、插件 8 项已读取；APK 菜单仍待完整实测 | test/ui/composer_features_test.dart；official-connection-probe-ROG-STRIX.json；v2-goal-ROG-rpc-fixed-probe.log |
| 附件 | `TTe` + V4 schema：本地选择、预览/移除、分块上传/中止/失败重试、随输入发送；首发身份及失败草稿保留 | 已实现待验证；Channel 上传回归与手机原生选择/缓存/失败/进程恢复通过；完整同态视觉待补 | test/state/composer_attachments_test.dart；test/protocol/attachment_transport_test.dart；flutter-android-integration.md |
| 上下文组成 | `j2e.Fe → NZe/AZe/jZe`：V4 contextWindow.breakdown 按 source 累加 chars；占比按 chars 总和，固定同值顺序；缺数据不编造百分比 | 已实现待验证；ALI 同任务总量一致，来源缺字段不填假数据 | official_detail_test.dart；official-ALI-light-task-441.png；待补弹窗同态对照 |
| 套餐额度 | `O2e/pB/ES/BF/VF/fZe`：OAuth 家族来源门控，个人/团队/Start 区分；打开刷新、60s 新鲜度、20s 请求超时；5小时/每周/工具剩余百分比及重置时间 | 已实现待验证；源门控、缓存、重连失效、迟到、超时及空账户已覆盖 | test/state/composer_usage_test.dart；test/protocol/entitlement_test.dart |
| MCP 额度 | `NF/cZe`：mcpQuota.aggregate，使用已用 percentage 计算剩余；三张主卡时 MCP 单独全宽行；说明为预置插件每日合计额度 | 已实现待验证；独立来源/全宽行，窄屏大字号折行 | test/ui/composer_features_test.dart；quota_section.dart |
| 新任务额度 | `NZe`：没有上下文时，套餐/Start 可单独使入口可见 | 已实现待验证；无上下文仍可打开适用套餐；Start 缺值显示 -- | test/ui/composer_features_test.dart |
| 视觉/交付 | 五形态、深浅主题、140% 字号、实际数据截图；假传输验证写入；analyze/test/APK/MuMu | 已实现待验证；0.1.0+4 已在两台 MuMu 覆盖安装并核对安装字节；完整视觉矩阵仍未验收 | v2-phase1-acceptance-2026-09-09.md；v2-goal-phase1d-* 日志；33 张当前 Flutter 图；同目录安装/源码 manifest |

## 0.1.0+7 额度阶段补充

- 上下文、缓存数值和总进度按固定官方 JS/CSS 修正；旧格式团队经实际组织/项目解析后读取额度。
- 手动重置已贯通次数/到期/弹窗/请求/结果确认，含未确认状态只查询和旧历史基线防误判。只读访问不会授予或消耗额度。
- 完整使用统计页，以及重置机会自动周期、历史已读/完成提示联动尚未完成。`requestCodingPlanResetOpportunity` / `markCodingPlanResetHistoryRead` 已有协议与状态实现，不能将未接入的自动路径记为验收通过。
- ROG 真实只读统计接口与官方“更多”页面已核查。详见 [额度阶段验收](v2-quota-acceptance-2026-09-09.md)，本表 C1/C2/C3 仍保留待验证状态。

## 已核查的数据语义

- 上下文组成来自 `usage.contextWindow.breakdown`，不是累计 input/output token 统计。官方自身也只在数组有有效来源时显示分项；需要同任务证据确认实际缺失原因，不能用累计用量或猜测代替。
- 编程套餐请求是 `usage-stats.getEntitlementSnapshot`，参数包含 `includeSubscription:true`、`preferredProviderId`、`requirePreferredProvider:true`、`allowDisabledPreferredProvider:true`、`allowEnvApiKey:false`；团队额外携带选中来源对应的 organizationId/projectId。
- 官方 `O2e` 还检查 `setting.get()` 的 familyModes 和 familySelectedKeys；API Key、自定义供应商及 ZAPI 不展示编程套餐额度。已有任务使用自身模型来源，不能读取其他设备或其他任务的默认配置充当来源。
- 额度 `percentage` 是已用百分比，UI 展示 `100-percentage`；Start Plan 使用 remaining/(number??unit)，不能将两个公式混用。MCP 来自独立 aggregate，不是上下文内 MCP schema 的字符占比。
- 所有测试写入继续使用假传输；真实桌面只读核查，不发送消息、不停止任务、不切换其模型配置。

## 侧栏远控门控证据

2026-09-09 核查固定主包 `jjt`（`memo(function...)`）及当前 Flutter 入口：

| 能力 | 官方实际条件 | 结论 |
| --- | --- | --- |
| 远控判定 | `zt = !!(webRemoteControlWorkspaceSwitcher || isWebRemoteControl)` | 远控使用 XEt 的工作区/时间线/归档任务索引 |
| 自定义分组 | `zt && grouped` 强制转 workspace；分组切换和新分组按钮均受 `!zt` 限制 | 桌面自定义分组在本远控基线中有依据不适用；Flutter 不提供该入口 |
| 桌面自动化 | 自动化导航按钮为 `zt ? null : ...onClick:wn`，wn 调用 onOpenAutomations | 远控无桌面定时任务入口，不能照搬 |
| 项目/分区拖动重排 | 桌面工作区和分区分支使用 sortable 组件；远控 f 分支直接渲染 XEt | Flutter 远控项目列表不加入桌面重排操作 |
| 保留入口 | 远控仍保留新任务、搜索、插件市场与账户入口 | 已接入现有 Flutter 侧栏；底部设备切换为已确认客户端扩展 |

此结论不豁免远控适用的设置、账户或任务写入功能，后者仍按全局清单分别实施与验收。

## 团队套餐来源兼容

- 官方 `fT/lT` 区分 product-only、product:project、product:organization:project；只有组织与项目都非空才是新格式。`pT/uT/xB` 将旧 `projectId=0` 作为同产品匹配，并允许同项目的产品 ID 更新。
- `lB/A2e/r2e` 从 `coding-plan-subscription.getEnterprisePricing({authenticated:true,family})` 的已订阅产品、teamProjects 读取实际组织/项目；保留已解析来源缓存，并可用 `k2e` 的当前团队权益身份回退。
- 客户端仅把回退快照用于身份解析，再发匹配的 scoped quota 查询；不会把未指定项目时的余额显示成所选团队的余额。源切换立即清旧展示，迟到/重连保护覆盖团队查询。证据：`entitlement_source_test.dart`、`composer_usage_test.dart`、实际 Channel 参数测试和窄屏英文大字号错误 UI 测试。

## 真实用量对照（2026-09-09）

- 官方与 `.dev` 同属 ROG 的「比较CLAUDE.md和AGETNS.md差异」；原生前图 `build/visual-audit/recovery-qa/tablet-ROG-v6-usage.png`，官方图 `official-ROG-light-usage-1723.png`。官方 DOM 视口为 1723×1195，但截图只捕获前 1664px；完整用量弹窗在截图内，不能把整张图当作无裁切的完整页面配对。
- 同态数据：上下文 140,794/1,000,000，官方显示 14.1%；缓存 93.8%。5 小时 100%、每周 94%、工具 95%、MCP 100%；MCP 的日期为次日。原生此前把前两项取整且遗漏总量进度条和 MCP 日期，现已修正代码，等待新 APK 对照。
- `DZe/OZe` 使用 Intl 最多一位小数，容量分母 compact 最多零位；`MZe` 要求 used>0。`kF` 的分段仅占用总量条的已用部分，缺分项仍显示总量条；`KYe` 是统一 p3/space-y3，缓存仅在有分项时增加上边线。混色采用 CSS Oklab 的预乘 alpha 规则，保留原始透明 surface token。
- 官方弹窗存在可用次数徽标、每周期重置入口和「更多」导航。已打开并保存只读重置界面 `official-ROG-quota-reset-dialog.png`；未点击真实重置按钮。相关入口与状态协议仍在补齐，不能将这几项视为已验收。
- 官方网页已关闭，临时视口已恢复，ROG `.dev` 已重新启动；ALI 连接始终由另一台模拟器独占。浏览器 DOM 测量未取得临时 portal 内容，`official-ROG-usage-geometry.json` 只支持根视口尺寸，不能用于弹窗几何验收。


## 2026-09-09 使用统计阶段

Composer 更多已迁移为真实使用统计页。Pqt/fJt 的应用 all 与 7d/30d分离，Fqt/SJt 的套餐 provider/org/project/range/timeZone 隔离，EJt/iJt 的 52 周三模式、DJt 三系列选择与积分门控、jJt 固定 7 天健康度均有实现。原生 More 进入/返回共享状态时序缺陷已修复；最终截图/APK 证据继续见 v2-statistics-acceptance-2026-09-09.md。C2 自动维护与 E1/E2 设置容器/账户入口仍为待完成，不以本阶段替代。
