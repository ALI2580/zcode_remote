# ZcodeRemote 性能与代码结构优化：统筹长程任务 Prompt

请以当前 ZcodeRemote 仓库为范围，持续执行性能优化和代码结构优化两个专项，直到约定的实现与验收完成。中文沟通。请直接开展工作，不能只输出计划、复述上下文或写一份报告就宣布完成。

## 执行依据与目标

首先加载 `.agents/skills/project-cognition/SKILL.md`，读取其开发/测试规则，并读取：

1. `references/optimization-code-audit-2026-09-14.md`：起始审计，所有历史事实需按当前代码核对。
2. `references/performance-optimization-execution-prompt.md`：性能测量、候选、指标与完成条件。
3. `references/structure-optimization-execution-prompt.md`：结构边界、批次与保行为验收。
4. `references/ui-parity-current-todolist.md` 和适用的产品验收条目：保护既有功能与未完成条件。

这两份专项 prompt 的执行与验收要求均适用。总目标是以可复现数据改善真实热路径，同时降低设置/聊天/协议模块的职责耦合；保持协议、视觉、输入、阅读、来源隔离、恢复和单次提交契约。

## 第一轮必须完成

- 核对 HEAD、dirty diff、相关文件哈希、测试/工具链和可用设备，保存既有工作；不沿用旧文档的版本、零问题或完成标签。
- 建立或接续 `references/optimization/master-todolist.md`，链接两个专项清单和本轮证据目录。
- 执行最短基线检查，登记原有失败，不把它们算成本轮引入，也不掩盖它们。
- 完成首个确定性性能场景的基线采样；随后交付一个可验证的优化或低耦合结构提取。如果测量排除了候选，记录数据并选择下一项，不以“无明显瓶颈”空结案。

## 批次调度

建议顺序为：P0/S0 基线和所有权 → 会话 delta/投影性能 → 设置中心独立页面提取 → 代码/diff 与滚动性能 → 聊天生命周期/组件拆分 → 纯 Dart 协议拆分 → 来源/缓存/语音内存验证 → 结构守护与联合验收。可以依据测量收益调整顺序，调整时记录依据。

同一批只有一个主目标：性能批可做最小必要提取，结构批保持算法与事件语义。两者不要同时改同一个热点文件。默认在当前任务中顺序推进，不自动另开多个任务或要求并行代理。

每批执行：选定未完成条目 → 写可证伪假设与验收 → 保存前态 → 修改 → 最短相关验证 → 性能/结构证据对照 → 更新清单 → 进入下一批。多轮小改比整仓重写更容易验证；无证据的复杂优化应撤回本批增量，保留既有工作。

## 长程状态与恢复

master 清单头部固定记录：

```text
GLOBAL OBJECTIVE:
CURRENT SOURCE: HEAD + dirty snapshot/hash manifest
LAST VERIFIED: command / exit code / evidence / source identity
CURRENT BATCH: ID / primary objective / owned files
IN-PROGRESS: applied changes / verification still pending
PERFORMANCE: baseline / current / environment / uncertainty
STRUCTURE: responsibility moved / owner / boundary checks
BLOCKERS: minimal missing condition / last evidence / affected items
NEXT EXECUTABLE: exact next command or concrete edit
COMPLETION GATES: passed / pending / blocked
```

每轮恢复先读清单头部和实际 diff，继续 CURRENT BATCH，不重建整份计划；上下文压缩不意味着任务结束。阶段有效结果保留，只有源码/环境变化或新疑点才重跑。

有独立可执行项时持续推进。真实设备/官方链接/账户条件缺失只阻塞依赖它的验收，不阻塞合成测试、算法基准或结构提取。所有剩余工作都依赖外部条件时，保存证据与最小缺失条件，明确未完成；不要循环执行相同失败或承诺未实际安排的后台运行。

每批和关键失败后简短汇报已确认结论、实际变化与下一步。技术选择按现有授权自主处理；必要外部写入/发布边界按当前授权处理，先把工作做成可审阅的具体结果。

## 统一质量门

- 不删除功能、不弱化官方门控、不放宽现有失败断言、不把不确定结果改成成功；不凭性能理由丢事件、跳协议确认或自动重发。
- 不换整套状态管理/渲染架构；协议保持纯 Dart。共享根因在正确层修复，不向页面复制补丁。
- 作用域包括设备/transport、workspace、session、provider/org/project、连接代次、logEpoch。缓存必须有界、可失效，取消/释放后迟到结果不可写回新来源。
- 阅读锚点、真实手势跟随、IME、草稿/附件、主题/字号、主辅面板必须保留。结构改变跑行为和渲染，性能改变保留前后数据。
- 使用同设备/模式/fixture 对比，区分算法指标与 profile 设备指标。达标规则在实现前登记，不能优化后改口径；受阻项不能填成 0 或通过。
- 相关测试优先，阶段收尾完整 analyze/test/smoke；Kotlin/Gradle 变更真实编译 Android。Flutter/Gradle 同工作区串行，不重复无意义全量构建。
- 真实远端默认只读，合成服务承担写入测试；凭据不进源码/日志/文档。QA 与产品包分开，保留设备数据。

## 联合验收与最终交付

性能专项：所有必需场景有有效基线，保留的优化有量化收益及非退化证据，目标设备验证已满足；测量排除项有依据。

结构专项：核心集中职责已有合理边界，依赖方向和资源所有权可检查，保行为回归通过，最终架构说明与实现一致。

联合收口：最终同源码完整检查通过，必要设备性能/渲染验证有效，清单、指标、日志和源码身份对应；没有把未验证条件或原有问题隐去。未完成任何必需门时只能报告阶段进度，不能宣布全局完成。两个优化专项通过也不能代替产品 UI parity、真实账户或平台专项验收。

最终交付 `references/optimization/final-report.md`：主要变化、前后指标及噪声/模式限制、结构前后职责、实际验证命令与结果、证据路径、保留的技术债/外部条件、如何复现。不要用测试数量、文件减少、运行时长或已花 token 代替成果。

现在开始第一轮，完成首个可验证闭环后继续下一条可执行项。
