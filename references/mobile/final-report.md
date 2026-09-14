# 手机竖屏体验专项：最终报告（final-report）

日期：2026-09-15。状态：**本地阶段通过，待集成**。
本报告对应 worktree `D:/WorkSpace/ZcodeRemote-mobile`（分支 `codex/mobile-portrait-ux`）。

## 1. 最终源码身份

- 基线：HEAD `23f0b308b3080ce90494220b66dea8fed02fa5de` + dirty 快照
  （`build/mobile-portrait/m0-baseline/dirty.patch`，sha1 `1062e21f…`，
  45 秒双快照稳定窗口验证）。
- 快照后上游继续推进（S1 第二提取 `settings_widgets.dart`、
  `general_settings_page.dart`；后续又出现 `lib/ui/conversation/` 拆分），
  集成时按 integration-request 的三方对比执行。
- 本专项全部改动 vs 基线的总 patch：
  `build/mobile-portrait/m7-r1/all-integration.patch`（sha1 `86bd096b…`）。
- 分批 patch：`m1-r1`（终端抽屉）、`m3-1-r1`（Composer 触控）、
  `m3-2-r1`（选择面板）、`m2-2-r1`（顶栏分层）、`m4-1-r1`（消息操作）、
  `m5-1-r1`（设置列表→详情）、`m6-2-r1`（终端最大化）、`m7-r1`（总）。

## 2. 前后主要变化（全部仅 compact 生效，宽屏逐字节原样）

| 领域 | 前 | 后 |
| --- | --- | --- |
| 终端抽屉 | 标签关闭 24×24、头部钮 40×40 | 标签行 48、关闭钮 36×48、头部钮 48×48；新增最大化/恢复（PTY 不重建） |
| Composer 主动作 | 发送钮 28×28、chips 28 | 发送钮 48×48、chips 行高 48（容器宽 ≥312 且竖屏且 isCompact） |
| 模型/模式/思考选择 | 锚点小弹层 | compact 底部面板（搜索/组头/vision 标记/重试/管理入口），同一 controller 与提交回调；宽屏锚点弹层保留 |
| 顶栏 | 标题+more+全部图标钮同排 | compact 仅导航+更多；Git chip/终端/面板收进任务菜单并带“已打开/已关闭”激活态 |
| 消息操作 | 操作行可见但钮 28×28 | compact 下 48×48（copy/edit/feedback/fork） |
| 设置导航 | 窄屏 isDense dropdown | 分类列表→详情（全高行+图标），PopScope Back 回列表不退出设置；深链接直达详情 |
| 触控目标基建 | 各处散小目标 | `MobileIconButton`（≥48 命中、图标 16-20）、`MobileOptionSheet`、`MobileLayout.isCompact` |

设计差异全文：`mobile-design-decisions.md`（compact 判定、48 规则、
Composer 容器宽 312 下限、竖屏方向门槛、200% 大字 1180 属 compact 等）。

## 3. 页面/状态覆盖与测试

- 新增测试 36 项（`test/ui/mobile/`）：触控命中（中心/边缘/相邻不误触/200% 大字）、
  底部面板（Back 单层、键盘 inset、搜索、选中写回 config）、模型/模式选择
  （config 短名读回契约）、设置列表→详情→Back→深链接、终端抽屉触控与最大化、
  消息操作实渲染、多尺寸矩阵（320/344/360/390/412 × composer/设置/抽屉；
  宽屏 720/834/1180 shell）。
- 全仓验证：`test/ui/ + test/protocol/ + test/state/` 共 **962 测试全绿（1 skip）**，
  `flutter analyze` 0 问题（`build/mobile-portrait/m7-r1/final-tests.log`）。
- 基线（未含本专项）201 项测试全绿（`m0-baseline/baseline-tests.log`）。
- 期间修复的回归：composer 窄容器/横屏放大溢出（composer_menu、
  voice_preview_keyboard 用例守护，阈值与方向门槛记入设计决策）、
  v2_visual/workspace_flow 的面板开关双路径适配。
- 截图：`m1-r1/captures/`（终端抽屉 390 before/after，已打开检查）；
  截图生成器 `terminal_drawer_capture_test.dart`（ZCODE_UI_CAPTURE_DIR）。

## 4. 操作步骤与触控数据（本地可验部分）

- 选择模型（compact）：点模型 chip → 底部面板 → （可选搜索）→ 点模型行；
  一次展开加一次选择，选中态/取消/Back 均可达。
- 终端最大化：抽屉头部最大化钮一次点按，高度 320→795（390×844 视口），
  再点恢复；PTY 会话持续。
- 设置返回：详情 Back 回列表（PopScope 拦截，不退出设置）；列表 Back 退出设置。
- 命中测试数据：见各测试断言（≥48 中心+边缘、相邻零重叠）；
  真实 rect 断言全部来自 tester.getRect 实测逻辑像素。

## 5. 关键证据索引

- `build/mobile-portrait/m0-baseline/`：基线快照+日志
- `build/mobile-portrait/m1-r1/ m3-1-r1/ m3-2-r1/ m2-2-r1/ m4-1-r1/ m5-1-r1/ m6-2-r1/ m7-r1/`：
  各批 patch（sha1）、测试日志、截图
- `references/mobile/integration-request.md`：文件/接口/冲突/接入后应测项
- `references/mobile/mobile-todolist.md`：条目级状态

## 6. 集成状态

**已集成到主目录（2026-09-15）**。上游稳定窗口（60+ 分钟无写入、双快照
复核 STABLE）后执行：对齐最新接口（上游已将 chat_page 精简至 2041 行、
settings_center_page 拆至 4283 行并新增 conversation/ 拆分模块）→ 三方
对比局部合并（terminal_panel/composer_toolbar/composer_menus 上游零演进
直接采用；chat_page/_ActionIcon、shell_layout、workspace_shell、
settings_center_page 在上游新版上重放锚点改动，备份存于
`build/mobile-portrait/integration/backup/`）→ 集成后主目录验证：
`flutter analyze` 0 问题 + 全仓 **968 测试全绿（1 skip）**
（`build/mobile-portrait/integration/integration-tests.log`，含手机 36 项
移动测试）。

### 真机/设备验收（2026-09-15，已执行部分）

- QA 包：`ZCODE_ANDROID_QA=true` 构建 debug arm64，包名
  `com.zcoderemote.zcode_remote.qa`（aapt badging 核对），安装于设备
  127.0.0.1:7555（2304FPN6DC，1440×3200 竖屏）。假服务/合成环境。
- 已验证：竖屏真实渲染、设置分类列表（全高行+图标，dropdown 消失）、
  分类详情（常规：界面语言卡片、未连接提示可见可理解）、Back 回列表
  不退出设置（PopScope 分层）。截图 06-09 与操作录屏
  `qa-mobile-recording.mp4` 见 `build/mobile-portrait/device-qa/`。
- 流程后已 force-stop QA 包并恢复设备旋转设置。
- 真机主流程 QA（integration_test，假服务，设备 7555 竖屏）：
  **task_management_test 通过**（27s：任务切换/置顶/重命名/未读/归档/删除/
  拒绝重试全流程 + scope acknowledgment 断言；修复该 QA 对上游新增无参
  `get` 调用的过期过滤）；**usage_statistics_test 通过**（统计 More→完整
  统计→范围→明细→主题→返回；修复上游改名"应用统计"→"应用用量"的过期
  断言）；**d2_4_rotation_isolation_test 通过**；**streaming_frame_metrics
  通过**（流式渲染帧指标记账）；**terminal_input_ime_test 通过**——
  Trime 键盘自动化驱动拼音 n-i-h-a-o 并点选候选"你好"，中文输入字节、
  组词候选与发送链路真机验证（截图 10-12 记录键盘/候选/上屏）。
  - **composer_reference_ime 通过**：Trime 候选点击（n-i-h-a-o→"你好"）
    + 符号层 @/$ 输入 + 原子引用插入/退格全链路真机验证。
- 已执行：中文 IME 实机输入（Trime 组词+候选上屏+发送链路）、
  composer @/$ 引用与原子引用、旋转前后状态隔离、流式帧指标。
  仍待真人执行：TalkBack 深检、单手热区主观评估。

### 核验登记补全（2026-09-15）

- **M2-1 任务入口**：compact 沿用既有 Drawer 承载全部任务入口能力，
  任务菜单补充低频操作，未新增常驻底栏——评估通过。
- **M4-4 审查返回层级**：file_changes_review_panel_test 8 项全绿
  （tabs/breadcrumb/hunks、多文件 tab、关 tab 返回、展开切换）+
  chat_row_dispatch_test 往返展开核验；compact 全宽覆盖沿用
  ShellGeometry.panelIsOverlay 既有路径。
- **M5-2 管理器列表/详情**：compact 纵向适配由既有验收守护
  （settings_import_layout 344/140%、settings_compact_switch_hit、
  client_settings_test 全宽×主题循环），集成后全绿。
- **M5-4 QR/配对**：本专项未改协议与页面；真机 .qa 安装后
  "需重新配对"入口可见可达（device-qa 截图）。
- **真人主观项（保持受阻登记）**：TalkBack 深检、单手热区主观评估。
  客观补充：设备 7555（MuMu 模拟器实例）dumpsys accessibility 显示无屏幕
  阅读器服务（installedServiceCount=1 为系统服务，无 Google TalkBack），
  TalkBack 深检在该设备客观不可执行；实体机 16480（vivo 投屏）补查
  dumpsys 同样 Enabled/Bound services 均空、包列表无 TalkBack
  （accessibility-dump-16480.txt），两台可用设备均无屏幕阅读器，
  该项只能等真人另配设备；组件级语义已由语义树
  harness 钉住（semantics_walk_test：MobileIconButton tooltip/button/
  tap/48 框，MobileOptionSheet 行 button+selected/enabled 标志与树序
  遍历）；harness 过程中发现并修复真实缺陷——sheet 选择行原本只有
  InkWell tap action，屏幕阅读器会朗读为普通文本，已补 Semantics
  (button/selected/enabled) 包装（主目录已回填，双目录 39 绿）；单手热区的
  客观部分——主动作（Composer 发送钮、终端抽屉与最大化钮）位于屏幕
  下半拇指区、顶部仅导航与更多（系统惯例位）——已由各测试 rect 断言与
  截图覆盖；"拇指手感"主观结论仍需真人。性能侧签字已于 2026-09-15
  04:5x 闭环（见 §7 已完成项 3）；真人两项（TalkBack 深检、单手手感
  评估）保持受阻登记，等待协作窗口。
- **设备形态更正**：此前标注"真机"的 7555 实为 MuMu 模拟器实例
  （dumpsys 客户端含 com.netease.nemu_vapi/mumu.sdk）；其验收证据效力
  为模拟器级（布局与交互），实体机单手/手势结论仍以真人执行为准。
  16480 为 vivo 实体机（V2309A）投屏，当前固定横屏输出，竖屏验收受阻。

### 联合性能非退化复测（2026-09-15，本地执行）

- 工具：性能侧冻结基准 `tooling/bench_conversation_state.dart`
  （ConversationState.applyFrame 确定性算法基准，600 deltas/帧）。
- 集成后基线 3 轮（`build/mobile-portrait/integration/joint-bench-conv.log`）：
  rows=5000 median 288–311μs（us_per_delta 0.480–0.518）；
  rows=20000 median 209–225μs（us_per_delta 0.348–0.375）。
- 性能侧冻结基准（`build/optimization/r1-p0-baseline/bench-conv-after.log`，
  3 轮）：rows=5000 median 272–310μs（0.453–0.517）；
  rows=20000 median 209–217μs（0.348–0.362）。
- **结论：范围完全重叠，聊天/流式关键路径无非退化**。本专项改动全部
  位于 UI 呈现层，未触碰 protocol/缓存/高亮算法，数据与预期一致。
  设备端帧指标：streaming_frame_metrics 真机通过。
- **性能侧独立复核（2026-09-15 04:44–04:47）确认上述结论并签核**：
  按 `perf-signoff-request.md` 复跑 bench（预热/计时×4/全量复查）与
  四个行为 harness（P3 code/P4 shell/source retention 等，全通过），
  analyze 0；bench 全量模式带内（5000=285μs、20000=204μs），
  在其 master-todolist LAST VERIFIED 签核「非退化」，
  证据 `build/optimization/post-integration/`。

## 7. 剩余条件（不阻塞本地阶段通过，阻塞专项完成）

已完成的原剩余项：
1. **集成到目标源码**：2026-09-15 稳定窗口完成（上游 conversation/settings
   拆分演进后三方对比局部合并），主目录 flutter analyze 0 + 全仓 968 测试
   全绿；联合基准集成后 3 轮与冻结基准范围重叠（见上节）。
2. **设备/系统验收**：设备 QA 六项通过（含 Trime 自动化中文输入、旋转
   隔离、流式帧指标）；设备形态与证据效力更正见上文"设备形态更正"。
3. **性能侧正式签字**（2026-09-15 04:5x 闭环）：性能侧按
   `perf-signoff-request.md` 步骤执行集成后复测——analyze 0、四个行为
   harness 全通过、bench 全量模式带内（5000=285μs、20000=204μs，冻结
   带 272–310/209–217），在其自有清单
   `references/optimization/master-todolist.md` LAST VERIFIED 签核
   「非退化」，证据 `build/optimization/post-integration/`；源码身份
   登记 chat_page=a464985d（mobile 集成所致）、其余热点文件与冻结一致。

仍受阻的外部依赖项（保持登记，任一闭环后回填本节并清除
mobile-todolist.md BLOCKERS 对应条目，专项即从"本地阶段通过"升级为完成）：
1. **TalkBack 深检**：需真人在装有屏幕阅读器的实体设备执行；7555（MuMu
   模拟器）与 16480（vivo 投屏）dumpsys 均 Enabled/Bound services 空、
   无 TalkBack（build/mobile-portrait/device-qa/accessibility-dump*.txt），
   客观不可执行，等待真人另配设备。执行手册：
   同目录 `talkback-human-pass.md`（T1–T6 场景 + 结果模板）。
2. **单手热区主观评估**：需真人单手操作；客观部分（主动作位于下半拇指区）
   已由 rect 断言与截图覆盖；H1–H6 手感打分表见同目录
   `talkback-human-pass.md`（与 TalkBack 深检同一次实体机会话完成）。
3. **设备 profile 帧率**（模拟器口径完成，2026-09-15 05:5x）：
   harness `integration_test/mobile_frame_profile_test.dart` 在 MuMu x64
   profile 模式采样（flutter run --profile 路径，经 drive 转发
   故障排查后改道），四阶段均零超 16.67ms 帧——滚动
   fling 204 帧 totalP50 1.72ms、键盘 inset 单次应用 10 帧 4.57ms、
   底部弹层开合 24 帧 2.74ms、全宽面板路由 30 帧 2.61ms
   （证据 build/mobile-portrait/m7-r1/profile-frames-mumu.log）。
   口径与性能侧一致：模拟器级证据，实体机口径待验。
   （此前 drive 转发故障 6 次日志同目录 mobile-frame-drive*.log。）
