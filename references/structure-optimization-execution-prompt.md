# ZcodeRemote 代码结构优化专项：长程执行 Prompt

请在当前 ZcodeRemote 仓库执行保持行为的渐进结构优化，持续完成“依赖/所有权盘点 → 行为保护 → 小批提取 → 独立验证 → 更新架构说明”。这是实施任务，不以目录方案或大文件行数统计代替交付。中文沟通。

## 1. 读取与启动

读取 `.agents/skills/project-cognition/SKILL.md`、development-rules / release-and-testing、`references/optimization-code-audit-2026-09-14.md`、最新 UI parity 清单及相关测试。核对 HEAD、dirty diff 与源码，历史记录不能直接当当前通过事实。

创建或接续 `references/optimization/structure-todolist.md`，证据放 `build/optimization/<唯一批次>/`。保存开始前状态与涉及文件快照/哈希；保留已有工作，不全仓格式化，不无依据删除或重命名公共入口。

## 2. 明确结构目标（S0）

保留现有方向：`lib/protocol` 纯 Dart、`lib/state` 管业务与异步协调、`lib/ui` 管渲染与交互，平台能力维持现有 MethodChannel/条件导入。无需引入新状态管理框架、服务定位器或全局事件总线。

为首批模块画出轻量依赖图和所有权表：谁创建/持有/释放 controller/subscription/timer，scope key 包含什么，切换/取消/重连如何使旧请求失效。记录 UI 直接执行的 RPC、跨层导入、真正重复代码与不该合并的相似业务。

结构指标包括：入口承担的职责、公共 API 面、依赖方向/环、异步资源所有权、重复业务来源与局部测试能力。行数只作线索；机械拆文件、增加转发层、把巨型类摊进多个 part 不算降低耦合。

## 3. 推荐批次与提取边界

### S1 设置中心

优先 `lib/ui/settings_center_page.dart`（审计时 5,288 行）。先提取自包含页面/展示组件，再提取来源协调与生命周期。复用已有 model_provider_editor、settings_scope、各 catalog 和独立设置页面。

目标边界可放在 `lib/ui/settings/`：壳/导航、section 注册与真实门控、各页内容、scope binding。涉及业务请求与取消的协调器放 `lib/state/` 或既有领域模块，不把所有 State 字段透传成巨型 Context，不把私有成员全部改 public。

每提取一个领域，明确初始化、来源切换、卸载、提交失败与草稿恢复。先保持外部导入入口与 UI 契约，随后再按实际调用清理兼容导出。设置结构改变不顺手调整间距、标题、翻译或字段行为。

### S2 聊天页

`lib/ui/chat_page.dart` 拆清会话订阅/绑定、搜索定位、消息动作（编辑/fork/反馈）、投影/回合分组、行分派和变更摘要组件。候选位置是 `lib/ui/conversation/` 与相应 state 文件，最终目录以依赖清晰为准。

搜索涉及 GlobalKey/RenderBox 的部分留在 UI；纯搜索状态与异步请求可独立。业务控制器不持有 BuildContext。保留消息 ID、logEpoch、阅读偏移、草稿提升、主辅聊天差异与 single-submit 语义。

先保持算法和事件时序，再考虑性能专项的缓存/通知变更；不要把结构迁移与逻辑优化混在同一无法归因的大 diff。

### S3 会话协议

`lib/protocol/conversation.dart` 按 transport/RPC facade、订阅恢复与分片、session index、conversation state/history reducer、DTO 逐步拆分。可保留原文件作为兼容 export 入口；不要用 UI 类型解决循环依赖，也不要把协议状态转为 Flutter ChangeNotifier。

特别保护 seq/gap/resync、早到帧、断线新代次、Initialize 与订阅顺序、snapshot/delta、history prepend/epoch/truncation、dispose 和 pending 请求。结构拆分不得更改 wire shape 或容错语义；若发现缺陷，先复现，另列一个有独立测试的修复批次。

### S4 目录与作用域、外壳

审查 `remote_agent_catalogs.dart` 和 MCP/hooks/skills/plugins 目录。仅抽取有相同输入/输出/错误/取消契约的重复逻辑；保留有效配置来源、写入范围、实体身份和刷新语义差异，不设计包办全部目录的万能 Repository。

梳理 WorkspaceShell 的导航、面板与来源页面所有权。缓存、暂停订阅和生命周期策略改变交由性能专项按证据实施；纯结构批次保持现有运行行为。

### S5 架构守护与说明

补能检查实际边界的轻量工具/测试：协议层 Flutter/UI/state 依赖、非法反向依赖和环，包含 import/export/part 及相对/package 路径。沿用已有 CI；只有本地运行可靠后才接入。无需测试每一个文件名或设置武断的统一行数阈值。

产出 `references/optimization/architecture.md`，说明模块职责、依赖方向、资源所有权、扩展点、测试入口与仍然存在的技术债。说明必须对应最终代码，避免只留一张理想目录图。

## 4. 验证与保行为要求

先跑与当前模块有关的既有回归；缺少关键作用域/释放/失败保护时补可观察的行为测试，再提取代码。不要为纯搬文件新增镜像测试。设置重点覆盖相关 parent_scope、catalog、模型编辑/连接和 UI 流程；聊天重点覆盖协议、history、viewport、任务切换、runtime settings、搜索与首发。

每批检查：调用方正常、无新增循环依赖、资源只有一个明确 owner、dispose/切换可取消、旧代次结果不污染新来源、错误/重试仍可用、草稿和阅读保持。涉及 Widget 树/key/生命周期变化时补实际渲染与交互检查，沿用深浅、中英、字号/宽度矩阵。

审计起点曾有 `chat_page.dart` 的 1 warning/1 info，先重新验证；在处理该文件的批次中安全收口，不能宣称继承了历史 analyze 0。阶段收尾跑完整 analyze/test 和纯 Dart smoke；涉及平台代码实际 Android 编译。一次通过后无新改动/疑点不重复构建。

性能不是结构自然带来的成果。沿用性能专项基准或为相关热路径建立最小基线，证明结构迁移没有明显退化；不能将文件变小写成性能提升。

## 5. 持续推进与完成判定

第一轮完成 S0 的最小盘点，并交付一个低耦合边界的真实提取及相关测试。每轮先接续已有清单，选择一个可独立验证的领域继续；不能以“下一步建议拆分”结束已授权实施。

条目状态用待核查/进行中/已实现待验证/通过/受阻/有依据不适用。每条记录原职责、最终 owner/API、修改文件、风险、命令/结果、证据与下一步。阻塞条件缺失时继续独立可做项，不反复轮询旧失败，也不假定等待会自动提供授权。

全部必需结构批次落实、依赖/资源所有权清晰、行为回归与静态检查通过、架构文档与代码一致，才宣布专项完成。某模块经实证无需拆分可以给出理由关闭；有必需未完成项则保留未完成状态。结构专项完成与产品官方同态/真实账户/设备验收是不同结论。

真实写操作用合成服务，凭据不入库。保持现有官方协议、功能和视觉。提交、推送、发布按现有明确授权执行，不把结构专项当作发布授权。最终交付结构前后变化、真实文件与测试证据、剩余技术债。
