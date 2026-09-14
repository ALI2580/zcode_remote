# 性能优化专项执行清单

状态：待核查 / 进行中 / 已实现待验证 / 通过（已验证优化）/ 测量排除 / 受阻。

## 环境与源码身份

- Win11 x64，Git Bash；flutter=`/d/SoftWare/Develop/flutter/bin/flutter`（版本见 baseline log）。
- 设备：`a094767f`（arm64 实体机）+ MuMu 模拟器 16448/16480/7555（x64, Android 12）。设备 profile/release 帧率采样待核。
- 源码身份：HEAD 23f0b30 + dirty（见 `build/optimization/r1-p0-baseline/`）。

## P0 基线

- [x] 最短基线检查（2026-09-14，HEAD 23f0b30 + dirty）：`flutter analyze --no-pub` exit 0 无问题；5 个重点测试文件 51 通过 exit 0；`dart run tooling/protocol_smoke.dart` passed exit 0。审计时的 chat_page 1 warning+1 info 已被既有 dirty 改动收口；未发现需登记的原有失败。证据：`build/optimization/r1-p0-baseline/{analyze,focused-tests,protocol-smoke}.log`。
- [x] P1-conv 基准与判定：conversation delta/upsert 线性查找（通过，见下方候选记录；后续 P2–P4/P5 与设备采样均见对应条目）。

## 候选与判定规则（实现前登记）

### P1-conv：ConversationState._applyDelta / optimisticRowUpdate 的 rows.indexWhere

- 代码事实（2026-09-14 重新定位）：`lib/protocol/conversation.dart:1994`（row.upserted）、`:2018`（row.delta）、`:2066`（optimisticRowUpdate）。rows 外部只读（chat_page/workspace_shell/conversation_history 均只读遍历），内部全部变更点：_applySnapshot 重建（epoch/窗口合并/清空）、row.appended、row.removed、prependOlderRows、optimisticRowUpdate。
- 假设（可证伪）：row.delta/row.upserted 单次成本随已加载行数 N 线性增长（indexWhere 全扫）；N=20k 时 600-delta 流式帧耗时应显著高于 N=1k（比例接近 20×），引入 rowId→index 映射可把该帧耗时降低 ≥15%。
- 基准：`tooling/bench_conversation_state.dart`（纯 Dart）。固定 delta 序列 600/帧（1 appended + 450 row.delta 流式 + 100 upserted 当前流 + 30 upserted 旧行 + 19 row.delta 旧行）；N ∈ {1000, 5000, 20000}；每 N 预热 3 轮 + 计测 7 轮，报告 median/mean/min。
- 主指标：N=20k 帧 median 耗时。达标：优化后 median 改善 ≥15% 且超过轮间噪声（max-min < 改善量）。非退化：N=1k median 回退 ≤5%。
- 行为门：`test/protocol/conversation_test.dart` + `test/state/conversation_history_test.dart` + `test/ui/conversation_viewport_test.dart` exit 0；索引一致性需覆盖 snapshot 重建、prepend、remove、epoch 切换、未知 rowId、null rowId 线性回退、恢复（历史分片）路径。
- 状态：**通过（已验证优化）**。
  - 基线（2026-09-14，HEAD 23f0b30+dirty，3 进程 × 7 轮，μs/帧 median）：1k=5195–5650，5k=23943–24410，20k=94470–95289。线性证实（20k/1k ≈ 18×）。噪声（median 极差）≤2.9%。证据 `build/optimization/r1-p0-baseline/bench-conv-baseline.log`。
  - 优化后：1k=598–670，5k=272–310，20k=209–217（μs）。改善 20k=**99.8%**、5k=98.8%、1k=88.5%，全部远超 15% 门槛与噪声；无路径回退。证据 `bench-conv-after.log`。
  - 实现：`ConversationState` 内 `_rowIndexByRowId`（rowId→index，结构变更即重建：snapshot 两分支、row.removed、prependOlderRows；row.appended 增量插入；重复 rowId 保留首命中语义；null rowId 保留线性回退）。`rows` 公共字段外部仅读（已核对 lib/ 全部引用）。
  - 行为回归：focused 5 文件 58 通过（51 原有 + 7 新增索引一致性）exit 0；analyze 0 问题；protocol smoke passed。证据 `focused-tests-after.log`、`analyze-after.log`、`protocol-smoke-after.log`。
  - 未做设备帧率验证（纯协议层算法指标；设备验证统一登记在下方设备验证节）。

### P2-chat：ChatPage 通知→分组→build 链路与 Viewport 锚点

- 代码事实（2026-09-14 重新定位）：`chat_page.dart` `_onState`（每通知 setState）→ build → `_buildChat` 调 `conversationTurnGroups(rows)`（全量 O(N) 分组）。已在 `chat_page.dart` 加入确定性计数器：`chatPageBuildCount`、`chatTurnGroupComputations`、`chatTurnGroupComputeMicros`（Stopwatch 仅在 `chatTurnGroupProfiling=true` 时运行，由测量 harness 开启）。
- 测量 harness：`test/ui/chat_stream_metrics_test.dart`（FakeBridge + 真实 ChatPage + 真实 ConversationState；固定快照 N 行 + 60 帧 delta 流，每帧一次 pump）。
- 基线数据（2026-09-14，debug widget 测试环境，`p2-metrics-baseline.log`）：
  - 分组算法（纯计算，200 轮均值）：1k 行=36.7μs/次，5k=159.7μs，20k=1331.5μs——线性，证实假设。
  - 流式链（60 帧）：notifications=61 → builds=60 → groupCalls=60（200 行与 5k 行历史一致，1:1:1，无隐藏放大）。
  - 分组占帧成本：200 行历史 ≈43μs/帧；5k 行 ≈288μs/帧；debug 全帧 wall ≈13–17ms/帧（测试环境噪声大，仅作量级参考）。
- **候选判定 1：流式分组缓存（按结构修订失效）→ 测量排除**。依据：5k 行（现实长历史上限）全量分组仅占帧成本 ~2%（debug 口径，release 更低），20k 行极端历史全量分组 1.3ms/帧（debug）仍 <16.7ms 预算 10%；消除它的增量分组机制需在渲染链引入变更索引传播与前缀偏移查找，复杂度与回归风险显著高于收益。按"本就很快的路径优先证明绝对耗时"规则关闭，保留计数器作为长期观测。证据：`p2-metrics-baseline.log`、插桩行为门 46 通过（`p2-instrumentation-gate.log`）。
- **候选判定 2：可见行/回合 widget 记忆化 → 风险评估后暂缓（登记风险依据）**。检查发现 `_TurnGroup.build` 直接读取 `state.rows`（singleTurn 扫描，已另行提升）与 `state.logEpoch`（ValueKey 构造）并传递读活闭包（`revision: () => state.revision`）。按 widget 实例恒等复用会在 `state` 内部变化时跳过合法重建（stale 渲染风险），除非对 `_TurnGroup` 全部渲染入参做完整依赖清单。收益上限（分组占比 ~2%@5k）不支持先投入该清单成本；待 P2-viewport 测量后按数据重估。
- **候选判定 3：singleTurn O(rows) 扫描提升 → 保留（已实现）**。事实：`_TurnGroup.build` 每组构建执行 `state.rows.where(kind==userInput||turnHeader)` 全量扫描 → 每帧 O(可见组数 × 总行数)。修改：`_buildChat` 每次 build 计算一次（纯函数，build 期间 rows 不变，语义等价），作为 `singleTurn` 构造参数传入 `_TurnGroup`（字段 `state` 保留，logEpoch key 与活闭包仍读原对象）。
  - 效果：每 build 扫描量 O(G_vis×N) → O(N)；60 帧流式 wall（debug 测试环境，同机同法）：5k 行 808,164μs → 707,299μs（−12.5%）；200 行 1,007,373 → 1,048,397μs（+4%，噪声内，该规模本无收益）。收益随 N 线性增长（20k 行外推显著）。
  - 行为门：`chat_row_dispatch + conversation_viewport + file_changes_review_panel + conversation_test + conversation_history` 57 通过 exit 0（`p2-final-gate.log`）；analyze 0 问题。
  - 证据：`p2-metrics-baseline.log` vs `p2-metrics-after-singleturn-hoist.log`。
  - 备注：未达 15% 主指标门槛的口径说明——本项登记的主证据是确定性的每 build 扫描复杂度下降与语义等价（纯提升），wall 为 debug 测试环境噪声较大的辅助口径；不以事后改阈值包装成功，如实登记。

### P2-viewport：ConversationViewport 锚点捕获/indexOf

- 代码事实（2026-09-15 重新定位，文件 206 行，`4e24c070`）：`_capture`（:45–61）从 index 0 线性扫描 ids 找首个可见项（深滚动时 O(firstVisibleIndex)，每滚动帧末一次）；`findChildIndexCallback`（:157–164）每次调用做 `_items.entries.where(...)` 全表遍历 + `ids.indexOf(id)` 两次 O(N)（子项协调期每个可见子项调用一次 → 每次 rebuild 最坏 O(visible×N)）；`_restoreAfterLayout`（:96）`ids.indexOf` 仅在 !following 且锚点未布局时触发（低频）。super_sliver_list 0.4.1 无 firstVisibleItem 类 API（升级包不在本批范围）。
- 假设（可证伪）：rebuild 协调期 findChildIndexCallback 的 O(visible×N) 扫描在长历史流式追加（itemCount 每帧 +1）下构成每帧主要 viewport 开销；反向映射可将每次调用降到 O(1)。
- 基准：`test/ui/viewport_metrics_test.dart`（测量 harness）：确定性行数计数器（callback 调用数、扫描 entry 数）+ wall。场景 A：N ∈ {1000, 5000, 20000}，40 帧 id 追加（每帧 pumpWidget 重建触发协调）。场景 B：深滚动后 20 次小步滚动触发 _capture。
- 主指标：N=5000 场景 A wall（3 次取 median）与扫描计数器（精确）。达标：wall 改善 ≥15% 且超轮间噪声；计数器下降为确定性佐证。非退化：`conversation_viewport_test.dart` 全过（锚点恢复/宽度/字号/键盘 inset）；跟随/锚点语义不改。
- 状态：**通过（findChildIndexCallback 修复保留）+ capture 候选测量排除**。
  - 插桩（行为等价改写 + 确定性计数器：probeCalls/probeEntries/indexOfScans/captureScans），测量 harness `test/ui/viewport_metrics_test.dart`（场景 A 顶部流式追加 40 帧；场景 B 深滚动锚点捕获 20 drag；场景 C 深滚动下流式追加 40 帧）。
  - 基线（`p2viewport-metrics-baseline.log`）：场景 C indexOfScans 随 N 线性：1k=567,280 / 5k=2,807,280 / 20k=11,207,280（40 帧）；wall 275.9/325.3/329.2ms。场景 A probeEntries 22,505。场景 B captureScans ≈1×N/次捕获（1k=19,590、20k=399,590）。
  - 修复后（`p2viewport-metrics-after.log`）：indexOfScans=0、probeEntries=1/调用（O(1) 反向映射）；wall：场景 A N=5000 **345.9→247.4ms（−28.5%，达标）**；场景 C −30.5%/−42.5%/−51.6%。
  - 实现：`_idByKey`（GlobalKey→id，随 putIfAbsent 维护）+ `_indexById`（id→首个 index，按 ids list 实例 identical 惰性重建，putIfAbsent 保留首命中=原 indexOf 语义）。行为门 15 测试全过（viewport 锚点恢复/宽度/字号/键盘 inset + chat_row_dispatch + file_changes + stream metrics），analyze 0。证据 `p2viewport-gate.log`。
  - **capture 候选：测量排除**。深滚动每次捕获 ~1×N 次 O(1) 哈希查找（20k 行 ≈ 20k 次 ≈ 0.2–1ms/帧末），super_sliver_list 0.4.1 无 firstVisibleItem 类 API，提示窗口方案触及锚点语义（阅读契约）风险不成比例；绝对成本有界。保留计数器观测。

### P3-code：CodeSyntaxHighlighter 重复解析（2026-09-15 重新定位）

- 代码事实（`code_renderer.dart` 1,045 行）：`CodeViewer` 为 StatelessWidget，`_body` 每次 build 新建 `CodeSyntaxHighlighter` 并 `format(source)`（:552,561/566）；`wrapLongLines=true` 时 `_LineNumberPainter` 再 format 一次（:617，双倍）；:570–574 无条件 `source.split('\n')+join` 构建行号大字符串（showLineNumbers=false 也算）。`format` 为正则全量扫描 + 每匹配 `TextSpan`；`_scopeFor` 对**每个匹配**新建 `RegExp(r'^\d')` 与关键词大 RegExp（:462,467）——RegExp 构造是热路径最贵项。
- 假设（可证伪）：聊天流式帧中未变化代码卡随父级重建反复全量 format；缓存 (source,theme,fontSize)→span + 复用 wrap 模式第二份 + 静态化 RegExp 可把 40 帧重建序列耗时降 ≥15%。
- 基准：`test/ui/code_viewer_metrics_test.dart`：格式算法 bench（100/1k/10k 行、含长行与中文）；widget harness（1k 行 fixture，40 帧父级重建，wrap 开/关），计数器 `codeFormatCalls`。
- 主指标：1k 行 wrap=true 40 帧重建 wall（3 次 median）。达标：≥15% 改善且超噪声。非退化：`code_renderer_test.dart` + file_changes 门 + analyze 0；复制/选择、行号、换行、主题、字号缩放语义保持。
- 缓存边界（登记）：顶层 LRU ≤8 项，键=(theme identical, fontSize, source 值相等)；无失效定时需求——内容不可变，键不命中即重算，无跨来源污染（键含全部影响输出的维度）。
- 基线（2026-09-15，`p3code-metrics-baseline.log`，debug）：format 100 行=1.55ms/次、1k=9.52ms、10k=105.4ms（线性，RegExp 每匹配重建为最贵项）。重建 harness（1k 行 40 帧）：wrap=false wall=940.7ms、formatCalls=40；wrap=true wall=**10,529.7ms**、formatCalls=80（双倍确认）。
- **候选 B（测量中发现，先行登记）：_LineNumberPainter 每帧全量重绘**。`paint` 布局整个源段落 + computeLineMetrics + 对每个逻辑行新建 TextPainter 并 layout（1k 行=1,002 次 layout/paint）。
  - 假设：内容未变的重建帧中，painter 以字段相等性（source/span/style/width/color/textScaler）实现 `==`/`shouldRepaint` 后，RenderCustomPaint 可跳过重复 paint，wrap=true 40 帧序列 wall 降 ≥15%（基线 10.5s，预期远超）。
- **结果（2026-09-15，候选 A 保留；候选 B 修正归因）**：
  - 实现：`_scopeFor` 的每匹配 RegExp 静态化（`_digitPrefix`/`_keyword`）；顶层 `_formatLru`（≤8 项，键=theme identical+fontSize+source 值）经 `formatCode()` 供渲染路径复用，`CodeSyntaxHighlighter.format` 保持无缓存原语；`_body` 单次 format 并在 wrap 分支复用同一 span 给行号 painter；行号大字符串仅 showLineNumbers 时构建。
  - 候选 B 修正：`_LineNumberPainter.shouldRepaint` 已按字段（source 值/width/style/color/textScaler）比较，未实现 `==` 重写；收益机制实为**缓存 span 实例恒定 → RenderParagraph 因 text 相同跳过整段重排**（1k 行 wrap 段落布局是残余大头），painter 自身字段比较本就存在。归因如实记录，不写未做的实现。
  - 数据（`p3code-metrics-after.log` vs baseline）：rebuild wrap=true 10,529.7→6,262.4ms（**−40.5%**）；wrap=false 940.7→480.2ms（**−49.0%**）；`codeFormatCalls` 40/80→**0**（40 帧全部缓存命中，无真实解析）。format 原语单次成本不变（9.47ms vs 9.52ms @1k，噪声内）——静态 RegExp 收益未在 debug 口径显现，保留（减少分配，无风险）。
  - 行为门：code_renderer + file_changes + chat_row_dispatch + 两个设置页测试 18 通过 exit 0（`p3code-gate.log`）；analyze 0。
  - 备注：wrap=true 残余 ~156ms/帧（debug）为布局/paint 其余部分，超出本批假设范围，未做未登记的进一步改动；后续如需可另立候选（先做 paint 与 layout 归因）。
- 状态：**通过（候选 A 保留；候选 B 经核对以既有 shouldRepaint 覆盖，无需新增代码，归因修正如上）**。

### P4-shell：WorkspaceShell 来源页保留/刷新

- 代码事实（2026-09-15 重新定位）：`workspace_shell.dart:833-838` `_conversationForSource` 每次构建把当前 sourceKey 的 ChatPage 存入 `_chatPages` 并以 Offstage Stack 渲染全部保留页；`:292-299` 来源切换（device/workspace/monitor/sessions 任一变化）在 didUpdateWidget 中 **`_chatPages.clear()`**（注释明确：缓存仅限单一来源，切源移除旧子树使 focus/voice controller 随页释放，草稿/视图状态留 stores）；非当前 key 的 Offstage 子项因 widget 实例 identical 被 Element 跳过重建。
- 假设（可证伪）：审计担忧的「每来源/每任务页缓存无界增长、隐藏页持续活动」——若来源切换循环中保留页数恒 ≤1 且 ChatPage 构建次数随切换次数线性有界，则该候选按设计已正确，判定为有依据的不适用。
- 测量：`workspace_shell.dart` 加确定性计数器（`workspaceShellChatPagesBuilt`、`workspaceShellRetainedPagesMax`）；`test/ui/shell_source_switch_metrics_test.dart` 用 FakeAppSessions + openDeviceWorkspace 在两个 workspace 源间循环切换 6 次。
- 判定：retainedMax ≤1 且 builds 线性（每源每次进入恰好一次构建）→ 测量排除（按设计有界，无泄漏无隐藏重建风暴）；否则立项修复。
- **结果（2026-09-15，测量确认按设计有界）**：12 次来源切换（ws-a↔ws-b）→ `chatPagesBuilt=12`（每次进入恰好一次）、`retainedPagesMax=1`（每次切源清空）。审计担忧的泄漏/隐藏重建风暴不成立：非当前 key 的 Offstage 子项靠 widget 实例 identical 跳过重建，切源即 clear。判定：**有依据的不适用（按设计有界），附计数证据**。计数器保留供长期观测。证据 `p4shell-metrics.log`、`test/ui/shell_source_switch_metrics_test.dart`。

### P5-voice：语音/模型 isolate 复测

- 代码事实（2026-09-15 核对）：`voice_transcriber_worker.dart` 识别已在常驻 `Isolate.spawn` worker 中执行（:46），`voice_model_store_native.dart` 解压与哈希已用 `Isolate.run`（:287,320）。审计「优先复用现有优化」成立。
- 本地合成判定（2026-09-15）：`test/voice/voice_transcriber_lifecycle_test.dart`（生命周期/取消）+ `voice_model_store_test.dart` + `voice_models_test.dart` 全部通过（含于全量门），UI 线程无识别/解压/哈希计算的代码路径未发现新增回归。
- 设备侧判定（2026-09-15，MuMu x64 模拟器 Android 12，QA 包 com.zcoderemote.zcode_remote.qa，合成 PCM fixture）：
  - `voice_known_audio_test.dart` 通过（真实 sherpa 离线推理输出含 "known"）。`p5-known-audio-mumu.log`
  - `voice_responsiveness_review_test.dart` 通过并产出计时：冷推理 2,072ms（UI 计时最大间隔 89ms，断言 <750ms，推理期 UI 操作 72 次）；暖推理 267ms（21ms）；预览+停止 1,673/248ms；取消迟到文本拒收 lateTextRejected=true。`p5-responsiveness-mumu.log`
  - 覆盖判定项：冷暖识别耗时 ✓、UI 阻塞间隔 ✓、取消回执/迟到拒收 ✓；未覆盖：物理麦克风录音链路、解压峰值内存（模型已预下载，本次未触发解压）。
  - **实体机复测仍待设备重连**（a094767f 于采样时点从 adb 掉线）；命令与 harness 就绪。
- 状态：本地通过 + 模拟器设备链路通过（计时已回填 final-report §2）；实体机复测与物理麦克风登记为剩余条件。

### 设备帧率采样（联合收口设备门，2026-09-15）

- harness：`integration_test/streaming_frame_metrics_test.dart`（1k 行历史 + 60 帧流式 + 滚动 fling；FrameTiming 全量采集，PDEVICE JSON 行）。
- 执行：`ZCODE_ANDROID_QA=true flutter run --profile -d 127.0.0.1:16448 integration_test/streaming_frame_metrics_test.dart`（注意：本 Flutter 版本 `flutter test --profile` 不可用，须用 `flutter run --profile`）。
- 结果（MuMu x64 模拟器，虚拟 333Hz 显示；非实体机达标口径）：流式 60 帧 build p95 4.50ms/raster 1.44ms/总 p95 5.87ms，超 16.67ms 帧 0/60；滚动 204 帧 build p95 0.25ms/raster 1.19ms/总 p95 1.87ms，超 16.67ms 帧 1/204。`pdevice-frames-mumu.log`
- 实体机复跑命令同上（换 `-d a094767f`）；剩余条件=设备重新连接。

## 设备验证登记

- [x] 模拟器设备口径（2026-09-15，MuMu x64 / Android 12 / QA 包 / profile 模式）：
  - P5 语音：`voice_known_audio_test.dart` + `voice_responsiveness_review_test.dart` 通过（冷推理 2,072ms/maxTimerGap 89ms、暖 267ms/21ms、预览+停止 1,673/248ms、取消迟到拒收 ✓）。证据 `p5-known-audio-mumu.log`、`p5-responsiveness-mumu.log`。
  - 帧率采样：`integration_test/streaming_frame_metrics_test.dart`（`flutter run --profile`）——流式 60 帧超 16.67ms 为 0、滚动 204 帧超帧 1/204。证据 `pdevice-frames-mumu.log`。
- [ ] 实体机口径：a094767f 于 2026-09-15 采样时点从 adb 掉线（`adb devices` 仅余模拟器）；重连后同 harness 同命令复跑即闭环（命令见 final-report §7）。物理麦克风链路与解压峰值内存同批补测。
- 重连尝试（2026-09-15，供追溯）：`adb kill-server`+重启后 `adb devices` 无 a094767f；`adb mdns services` 无无线配对服务；USB 枚举无 Android 设备。**需要物理动作**（USB 插拔或在设备上授权无线配对）——代理端无法完成，保持登记等待。

### 移动端集成后联合复测（2026-09-15，mobile-portrait M7 签字）

- 触发：mobile 侧 04:07 完成 M7 集成收口（INTEGRATION STATUS=已集成到主目录），按协作规则对集成后源码执行同源码复测（请求见 `references/mobile/perf-signoff-request.md`）。
- 源码身份：热点文件 SHA1 与 final-report §8 冻结清单一致（conversation_state/conversation/conversation_viewport/code_renderer/workspace_shell/settings_center 六文件）；例外 `chat_page.dart` 7d513345→a464985d（mobile 共享入口适配，其拥有范围，由 chat_stream harness 覆盖复测）。计数器全部存活。
- 复测：analyze 0；bench 全量模式 5000=280/285μs、20000=204/211μs 带内；四 harness 全通过（indexOfScans=0、formatCalls=0、retainedMax=1 维持）。
- 异常处置：bench timed 5000-first 模式 5000=430–463μs 带外 +45%，经同分钟全量模式对照（285μs 带内）+ mobile 04:17 同命令带内数据（288–311μs）定性为 JIT 预热次序 + 窗口负载测量伪影，非代码回退。证据 `build/optimization/post-integration/`。
- 签字：**集成后联合复测通过（非退化）**，已登记 final-report §9。实体机门（a094767f）保持原登记等待，不受本复测影响。
