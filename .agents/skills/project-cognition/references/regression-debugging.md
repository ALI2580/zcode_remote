# 回归排查：竞态、中文输入、辅助功能与原生交互

以下来自本仓库已复现的问题，按症状读取。适用版本与验证入口须保留；不要推定所有 SDK 都存在相同缺陷。完整历史见 [仓库 lessons](../../../../references/lessons.md)。

## 连接与大数据读取

- 按 relay → paired → bootstrap → bridge → Channel Initialize → Conversation handshake → projection 定位，不把每次空页面都当 UI 问题。
- `[200]` 是合法 Initialize；早到帧需缓冲。换栈前保存旧 bridge ID，新栈 Initialize 后再通知订阅恢复，迟到旧路由不能写进新 stream。
- 本轮文件列表超时曾由接收端误套本地 512 KiB 分片限制引起：合法更大片段被丢弃；ACK 还需完整 generation/recovery identity。小消息通过不代表大列表可用。
- 身份正常但反复掉线，先检查浏览器、探针、应用是否争用同端；不要盲目增加重连次数或猜测凭据失效。

入口：`test/protocol/rpc_transport_test.dart`、`bridge_recovery_test.dart`、`conversation_handshake_test.dart`、`tooling/protocol_smoke.dart`；真实探针只用当前授权的只读窄模式。

## 用可控时序测试异步隔离

使用 Completer：旧请求开始 → 切来源/推送新状态/重连/释放 → 返回旧值 → 断言当前数据不变。再测试失败重试和重复手势，而不是只测正常返回。

本轮实例：

- pinned/archived 回读不能被旧全局索引覆盖，也不能覆盖请求发出后的新推送。catalog 与 WorkspaceMonitor 都要测。
- 重置完成前启动的额度读取不能清除完成投影；等待旧读取结束后获取新额度。
- 相同 task ID 的两个设备/工作区、主辅会话、移除设备时尚未完成的附件选择/恢复读取，要分别测试。
- `rowsRange` 的旧 logEpoch/旧游标结果不能覆盖当前尾部；无进展的恢复不能无限空转。

入口：`test/state/workspace_catalog_test.dart`、`app_sessions_test.dart`、`plan_resets_test.dart`、`recovery_test.dart`、`conversation_history_test.dart`。

## 中文 IME 与引用编辑

- 区分拼音 composing、候选提交和真正的发送动作。未提交组合区不能触发引用选择或回车发送；某些桌面 IME 会先清 composing 再发确认 Enter，保留已有提交保护。
- Android/iOS 的普通 Enter 应遵循当前输入配置换行，不照搬桌面发送快捷键。核对控制键组合、中文 `¥/￥` 技能触发及 UTF-16 范围，不按字符数随意切 token。
- 引用标签和序列化值都要验证。删除/替换是原子引用行为，选择后恢复焦点；快速切换时不能接受旧来源候选。
- 原生 IME 声称“已显示”不等于有键盘占用区。结合截图、实际焦点、IME 配置、viewInsets 和物理/逻辑尺寸判断；曾出现搜狗报告显示但没有有效占用区，不能当作中文软键盘已验收。
- 修改 `show_ime_with_hard_keyboard` 或键盘模式前记录原值，结束恢复。实际组合输入在独立 QA 草稿上验证，不向真实任务发送测试文本。

入口：`test/state/composer_references_test.dart`、`test/ui/composer_features_test.dart`、`composer_ui_test.dart`；实际软键盘仍需原生步骤和截图。

## 辅助功能树变空：逐层最小复现

本机 Flutter 3.47.2 / Dart 3.13.2 曾复现：静态页面、普通弹窗、共享浮层、长 Text 列表、空任务壳均正常；带可选链接的 Markdown 第二次 UIAutomator 连接后整树变空。单独 SDK `SelectableText.rich` + 链接也可复现。

本地源码中 RenderEditable 缓存链接片段 SemanticsNode，没有 RenderParagraph 对应的 clearSemantics 缓存清理。产品正文改为 `SelectionArea` + Markdown 默认 `Text.rich` 路径，保留跨段落选择复制；双端重复读取与真实 ROG 用量页返回已验证。

排查顺序：

1. 确认前台包、截图与当前数据，区分工具只过滤出无文字节点与整棵树损坏。
2. 用不连接远端、不运行 Flutter 测试驱动器的独立 `.qa` 页面连续两次读取。
3. 按“静态 → 弹窗/路由 → 长列表 → 任务壳 → 富文本 → 单一 SDK 控件”加回组件。
4. 修复后做重复连接、进入/返回、选择与复制回归；不能靠频繁重启或强制常驻语义树蒙混通过。

入口：`tooling/accessibility_probe.dart`、`test/ui/markdown_accessibility_test.dart`；[阶段证据](../../../../references/v2-sidebar-accessibility-acceptance-2026-09-09.md)。诊断入口故意保留 SDK 失败对照，不能把它当成产品页面。

## 连续长按与路由

本轮任务菜单在长按开始时加路由，置顶/未读后下一次长按可能不触发。只按分区换 key 仅掩盖部分场景；最终以 `onLongPressUp` 在手指抬起后打开菜单，独立 Semantics long-press action 保留辅助功能操作。

验收要连续做第二次、第三次操作，包括置顶/取消、改名、未读、归档/恢复。鼠标右键、普通点击和辅助功能动作也要检查。这个结论针对已复现任务行，不要求所有菜单统一延后到 pointer-up。

入口：`test/ui/task_navigation_test.dart`、`integration_test/task_management_test.dart`。

## 原生测试等待与日志

- 聚焦文本框的光标或持续动画可能让 `pumpAndSettle` 卡住。等待明确状态或有限时长 pump；本轮重命名窗口采用有限等待。
- `ensureVisible` 后等布局完成再读坐标。路由、字号、旋转或键盘变化后，旧坐标作废。
- 原生平台回调只记录请求并返回合成数据，在测试主流程断言；回调内断言可能被业务 catch 吞掉，表现为莫名空态。
- fake-async 测试调用 SharedPreferences 等真实异步操作时，必要时用 `tester.runAsync`，不要把假时钟挂起当网络超时。
- Flutter 原生集成测试期间不并发扫描同一 Flutter 页面语义树；辅助功能专项使用独立诊断应用。测试若明确等待系统选择器，按该入口的 fixture/交互步骤执行。
- 中断工具调用后查残留进程和日志，不假定构建已经退出，不批量杀死全部 dart/java/adb。

## 视觉、主题与阅读

- 弹窗打开后切主题/键盘时，路由内部重新订阅当前 Theme/MediaQuery；不能只捕获打开瞬间的值。Scaffold 可能消费 IME inset，覆盖层需读取正确的根路由安全区域。
- 首次进入用量页若共享状态同步通知底层 Composer，可能触发构建期 setState；将初始化读取安排在首帧之后，并保留共享控制器回归。
- 颜色按 CSS 真实混色空间核对；本项目涉及 Oklab，不随意改为 RGB 混色。
- 浏览器 CSS 像素、Flutter logical 像素和截图物理像素分开记录。曾有 DOM 宽 1723 而截图仅宽 1664 的裁切，不能比较整页并归咎字体。
- 用固定字体/主题/语言/字号/数据/滚动位置对比，报告裁切区域和像素差异；UI 结构不同仍要修复。

## Windows 实用技巧

- 搜索先用 rg；独立读取并行，改动、构建、安装按依赖串行。
- Python 输出中文时先 `sys.stdout.reconfigure(encoding='utf-8')`。控制台乱码不意味着原文件损坏。
- 环境变量通常只属于当前 shell：每次原生 QA 显式设置包开关，产品构建显式移除。
- 用 PowerShell 原生参数处理路径；删除/移动前验证绝对范围，不跨 shell 拼接命令。多行文本用文件或结构化参数，不把 JSON 转义当 shell 转义。
