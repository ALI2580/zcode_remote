# V2 全局差距与验收记录

基线日期：2026-09-09。目标范围来自本任务最新目标文件，并继承三个 Composer / V2 关联任务的已确认产品决策。纯 Flutter + Dart 产品路线，Kotlin 仅接系统能力；协议层纯 Dart。全部适用必需项通过、同代码 APK 安装成功且证据完整后才能结束 Goal。

状态仅使用：待核查、待实现、已实现待验证、验收通过、受阻、有依据的不适用。某条的局部测试通过不能替代整条产品验收。基线官方资源为 `official-web-baseline.json`，不随线上更新无限增加范围。

2026-09-09 最新整理：0.1.0+10 已构建、双端覆盖安装、368 项测试通过，183 文件源码和 APK 已归档。按要求暂时停止功能开发，详细分解、开发规则和验证命令见 [进度与 TodoList 手册](D:/WorkSpace/ZcodeRemote/references/v2-progress-todolist-2026-09-09.md)。阶段通过不改变下表整体完成条件。

| ID / 需求 | 官方或产品依据 | 当前实现 | 剩余差距 | 验收方法 | 证据位置 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| P1 纯 Dart 协议与连接恢复 | 目标架构约束；官方 Z4t T/C/P | 协议纯 Dart、重连换栈/握手代次、大分片 ACK 修复；+10 完整回归及纯 Dart smoke 通过 | 最终双远端切换/断线/恢复联合实测 | 独立 dart run；Initialize 先到、旧桥迟到、超过 15 次失败、握手代次测试 | tooling/protocol_smoke.dart；test/protocol；v2-sidebar-accessibility-protocol-smoke.log | 已实现待验证 |
| A1 项目/任务组织、独立置顶、搜索、筛选排序、展开折叠、归档视图 | 官方 ECt/XEt/jjt；official-feature-parity.md | 全索引与独立置顶已实现；+10 修复成员状态读取时序，catalog/monitor 回归通过 | 真实只读搜索/排序/折叠/归档连续场景、实时组合和完整官方同态视觉收尾 | 假 channel/index 合并与切换回归；双端只读操作 | test/state/workspace_catalog_test.dart；app_sessions_test.dart；v2-sidebar-accessibility-acceptance-2026-09-09.md | 已实现待验证 |
| A2 图钉/未读/状态图标及置顶、重命名、归档、恢复、删除 | 官方 KEt/ZCt/XEt | 全操作双端原生合成服务通过；+10 修复连续长按，保留辅助功能 action；深色英文 140% 菜单通过 | 全部形态/组合和官方图标、密度、菜单位置的同态视觉收尾 | 假传输写入；原生连续操作、确认/失败、触屏菜单 | integration_test/task_management_test.dart；test/ui/task_navigation_test.dart；+10 阶段记录 | 已实现待验证 |
| A3 远控入口门控 | 官方 jjt：zt 判断，远控 XEt 分支 | 分组/新分组、桌面分区重排和自动化入口按远控条件排除；保留设备扩展 | 本行侧栏门控已核实；设置/账户门控仍见 E1/E2 | 固定官方 JS 条件、当前 UI 源码和实际双端侧栏 | official-feature-parity.md「侧栏远控门控证据」 | 验收通过 |
| B1 加号、@ / $ 候选与引用 | 官方 gRe/dRe/vRe/UA/NIe/zIe | 真文件/技能/插件读取、候选排序、缓存、引用/焦点/移除已接入并回归 | 中文软键盘及其他主题/面板组合；技能/插件运行时变更等完整行为继续核查 | 真实只读候选；假传输/编辑器回归；实际键盘 | composer_references_test.dart；本阶段验收记录与实际截图 | 已实现待验证 |
| B2 附件完整链路及首发 | 官方 TTe 与 V4 schema | 原生持久缓存、预览、上传/取消/重试、暂存 session、失败及进程恢复已接入；手机/平板原生选择及重启通过 | 其余形态/系统组合；完整官方附件视觉对照 | 实际 Channel 分片/哈希/中止回归；独立 .qa 原生选择/失败/重启 | test/protocol/attachment_transport_test.dart；test/state/recovery_test.dart；flutter-android-integration.md | 已实现待验证 |
| C1 上下文总量与来源 | 官方 j2e.Fe/NZe/AZe/jZe | 已修正紧凑数字、一位比例、缓存精度、已用容量内来源色段和缺分项总进度 | 最终产品同任务对照及更多数据组合 | 合成完整/缺失数据；真实同任务比较 | test/ui；build/visual-audit | 已实现待验证 |
| C2 GLM 个人/团队/Start 套餐 | 官方 O2e/pB/ES/BF/VF/fZe；fT/pT/A2e/k2e；rI/EXe | 个人/Start/旧团队、手动重置、统计、自动维护已接入；+10 真实 ROG 更多/返回及语义重复读取通过 | Start/团队全部真实数据组合、完整设置/来源入口、用量整页几何与最终联合验收 | 假传输时序/缺字段/旧 key/重连；实际 Channel 参数；只读额度；双端原生自动维护 | v2-maintenance-acceptance-2026-09-09.md；v2-sidebar-accessibility-acceptance-2026-09-09.md | 已实现待验证 |
| C3 MCP 独立额度及新任务入口 | 官方 NF/cZe/NZe | 独立日期、额度和全宽布局已接入，缺值及非法日期均不编造 | 最终产品同任务和全部形态/面板组合对照 | 解析/控件回归；新任务用量实机 | lib/ui/composer；待补证据 | 已实现待验证 |
| D1 顶栏任务/项目/分支和工具入口 | official-web-ui.md；design-draft-v2.md | 任务/项目及面板入口 | 分支及适用工具入口不完整 | 官方协议读核；五形态渲染/实机 | 待补 | 待实现 |
| D2 消息/思考/工具详情、历史/阅读恢复、主辅会话 | 官方 V4 / lessons.md | Markdown/原始详情、按日志/游标分页与消息 ID/可见偏移恢复；+10 修复可选链接语义失效并保留跨段落复制 | 富详情及大字段分页、官方消息操作门控；主辅隔离联合验证与完整官方对照 | 协议/状态回归；变高消息/140%/不同宽度；原生阅读和辅助功能 | test/state/conversation_history_test.dart；test/ui/markdown_accessibility_test.dart；+10 阶段记录 | 已实现待验证 |
| D3 完整 diff 审查、终端与交互请求 | 官方远控门控及协议 | 变更摘要/辅助对话 | diff、终端、官方请求表单与入口待迁移 | 先查协议；假传输操作；实际渲染 | 待补 | 待实现 |
| D4 Composer 配置、首发、回执、停止与队列 | composer-v2-protocol.md | 既有闭环与最小队列 | 新附件/引用影响；队列编辑重排、快捷键、门控再核查 | 全量既有及新增时序回归 | test/state/composer_controller_test.dart；test/protocol/composer_transport_test.dart | 已实现待验证 |
| E1 全量远控适用设置、供应商/插件管理 | official-settings-catalog.json | 客户端设置、部分远程页和插件市场 | 逐设置分类核查与迁移，不能用本地设置替代 | 清单逐项映射；假 RPC；实际设置渲染 | references/official-settings-catalog.json | 待核查 |
| E2 账户菜单及能力门控 | 官方 OAuth/remote_profile | 头像名字整体菜单 | 登录/登出、用量及远控门控需核对 | 官方资源及只读账户；假操作回归 | 待补 | 待核查 |
| F1 离线语音 | design-draft-v2.md；旧 Zemote 实现 | 当前产品尚无完整链路 | 模型目录/下载校验/加载/录音/识别/作用域填入，默认不发送 | 下载故障与识别状态测试；MuMu/真机语音 | 待补 | 待实现 |
| F2 APK 更新 | release-and-testing.md；产品决定 | 检查更新/发布页；底层已有稳定/Beta 筛选、SemVer、ABI 选择与 MD5 文本解析 | 通道 UI、下载/取消/重试/校验、安装交接与包名/签名兼容 | 资产/下载故障测试；匹配测试 APK 安装交接 | lib/update；test/update/update_checker_test.dart；端到端待补 | 待实现 |
| F3 进程重启恢复 | design-draft-v2.md | 加密日志与前一有效快照；草稿/引用/附件/配置/导航/阅读/面板恢复；深历史两页定位、原生及真实任务前后位置相同；移除与迟到隔离 | 本项已通过 0.1.0+6 验收，后续随最终代码回归；跨系统组合由 F4 继续验证 | 冷重启、失败草稿、同 ID 隔离、损坏/保存失败、宽度/字号与移除竞态 | v2-recovery-acceptance-2026-09-09.md；v2-history-acceptance-2026-09-09.md | 验收通过 |
| F4 Android 系统组合 | flutter-android-integration.md | 通知/上岛、预测返回、键盘与铰链基础；+10 富文本辅助功能最小复现/修复、双端原生和真实 ROG 复验通过 | 其余 V2 系统组合、实际中文 IME、ColorOS 真机返回/折叠 | API32 MuMu 回退 + ColorOS16 实机证据 | 历史上岛确认；+10 阶段记录；其余待补 | 已实现待验证 |
| V1 五形态/主题/语言/140%/键盘/主辅面板 | 目标文件；官方 JS/CSS/icons | +10 153 张当前 Flutter 渲染；双端原生深色英文 140% 任务菜单 | 新模块加入后的最终全矩阵、官方同设备同任务成对校准；不得忽略已知裁切 | 344/390/720/834/1180，容器断点；PNG 检查 | build/v2-sidebar-accessibility-preview；build/visual-audit/recovery-qa | 已实现待验证 |
| V2 双模拟器与真实双远端隔离 | 最新目标连接分配 | 手机 ALI、平板 ROG 已固定分配和核查；均安装 +10；手机最新任务由你手动切换并交回 | 最终跨端切换/重连/草稿/配置/附件/阅读/面板联合矩阵及每组同态对照 | 每次显式 ADB 目标；串行官方同端对照；重新确认当前任务 | +10 安装记录；最新进度手册；各阶段只读报告 | 已实现待验证 |
| G1 最终交付 | 目标文件交付 1–6 | 已有 +10 可安装 .dev、183 文件源码与 manifest，双端字节相同 | 所有适用项完成后再执行最终同代码检查/安装/完整证据审计 | 实际构建安装检查；逐项完成审计 | CHANGELOG.md；v2-implementation.md；本表；详细 TodoList | 待实现 |

## 验证与阻塞记录

- 2026-09-09 最新：+10 368 项完整测试、analyze 零问题、153 张渲染及双端原生任务管理/深色英文 140% 通过；已构建覆盖安装、冻结源码。详细事实及未完成事项见最新进度手册。下方数字保留历史含义。
- 你已确认本次手机页面变化由手动操作产生，后续保留最后选择的 ALI/MCP SSH 任务；不能将其记为恢复缺陷。

- 阶段 `0.1.0+6` 的 304 项测试、33 张渲染、双端原生及真实任务阅读恢复、兼容签名和安装字节证明见 [长历史阶段记录](v2-history-acceptance-2026-09-09.md)。F3 已有独立完整功能证据；D2 富详情、全局视觉与系统组合仍未完成。
- 阶段 `0.1.0+5` 的 289 项测试、双端原生附件选择及进程恢复、兼容签名与产品双端覆盖安装、实际任务/草稿/面板冷恢复见 [恢复阶段记录](v2-recovery-acceptance-2026-09-09.md)。已清理测试草稿，未向真实桌面发送。
- 阶段 `0.1.0+4` 的构建、267 项测试、纯 Dart 检查、33 张渲染、双 MuMu 覆盖安装/实际用量/附件选择器取消及源码快照见 [阶段记录](v2-phase1-acceptance-2026-09-09.md)。两台安装的 base.apk 已与交付 SHA-256 一致，源码逐文件仍与阶段快照一致；这不代替全局验收。
- 中文实机组合输入仍待继续：当前 MuMu 的搜狗 IME 报告已显示但没有实际软键盘占用区。临时 show_ime_with_hard_keyboard 已恢复原值 0，测试字母与引用已移除，未发送到真实桌面。

- 2026-09-09 初始静态分析：`test/ui/fake_features.dart:139` 缺大括号，已修正，等待完整复验。不得把历史 219 项结果当作本轮结果。
- 文件候选超时已定位并修复 RPC 大分片接收与 ACK 身份问题。修复前后的同端只读证据为 `build/artifacts/official-connection-probe-ROG-STRIX-before-rpc-fix.json` / `official-connection-probe-ROG-STRIX.json`；后者返回 6,180 文件、15 技能、8 插件。仍需 APK 中实际菜单验收。
- 真实链接仅保留运行时或应用现有加密凭据存储；文档只记录 ALI / ROG-STRIX。连接验证前检查本轮浏览器/探针/应用持有者，避免争用。
