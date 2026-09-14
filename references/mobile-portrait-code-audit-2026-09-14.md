# 手机竖屏体验专项：源码分析

## 范围与结论

2026-09-14，对正在变化的 ZcodeRemote 工作区进行只读源码抽查。本轮交付移动端执行 prompt，不修改产品源码、不启动另一个实施任务；未操作正在使用的设备，未运行 Flutter/Gradle 或重新渲染截图，以免与现有优化任务争用。以下区分代码事实、体验设计判断和待运行验证项。

项目已经有响应式基础，但部分操作仍沿用紧凑桌面控件，竖屏体验需要一次覆盖导航、触控、信息层级与键盘的专项。不能简单描述为“完全没有手机适配”，也不能把没有 overflow 等同于适合单手操作。

## 本次代码证据

行号属于读取时快照，其他任务正在修改源码，执行前按类/函数重新定位。

| 领域 | 代码事实 | 专项方向 |
| --- | --- | --- |
| 触控尺寸 | `composer/composer_toolbar.dart` `_Submit` 的 InkWell 内是 28×28 SizedBox（约 386 行）；`_Chip` minWidth/minHeight 为 28（约 290 行）。 | 测实际命中区域，建立手机触控目标；图标可保持紧凑，但不能用相邻重叠的透明区域伪造大目标。 |
| 顶栏 | `shell/shell_layout.dart` `ShellIconButton` 为 40×40（约 61 行）；标题同一 Row 后追加 more 与全部 actions。`workspace_shell.dart` actions 包括 Git、终端、工作面板（约 918 行）。 | 竖屏建立主要/次要操作层级，将低频操作收进可发现菜单，保留标题和来源辨识；不能只把标题继续挤短。是否溢出需按状态和宽度实测。 |
| 设置导航 | `settings_center_page.dart` 窄屏分支使用 isDense 的 DropdownButton 切换多个分类（约 1733 行）；宽屏判断考虑字号。 | 手机采用分类列表→详情的层级，明确详情返回与离开设置的区别，保留各分类状态、草稿和来源身份。已有子页面可复用。 |
| 工作面板 | `ShellGeometry.resolve` 已决定窄屏 overlay；panelIsOverlay 下实际宽度使用 workConstraints.maxWidth（约 392 行），不是固定 288px 的手机窄条。已有 ExcludeFocus/IgnorePointer。 | 保留全宽基础，核验标题/关闭/返回/焦点与列表→详情路径；不要重复实现“首次全宽面板”。 |
| 导航与系统区域 | 外壳已有窄屏 Drawer、SafeArea、键盘 inset 处理；Composer 有 384/576/672 容器断点与短键盘视口压缩。 | 复用机制，检查不同高度、IME/安全区、嵌套 inset 以及按一次 Back 是否只退出一层。不能清空草稿或重复创建订阅。 |
| 弹层 | `composer_popover.dart` 已按 overlay、anchor、键盘和 padding 做碰撞约束。 | 问题候选是小浮层承载复杂选择的操作成本；手机复杂菜单可改底部选择面板/完整选择页，桌面保留锚点弹层。不能认定所有弹层都缺少避让。 |
| 任务操作 | `shell/task_navigation.dart` 已提供 onLongPressUp 和语义长按，不仅支持 hover/右键；任务行最小高度为 32。 | 保留长按作为快捷入口，并提供可发现的显式操作入口；测长标题、状态与行高，避免选择任务和打开菜单互相误触。 |
| 终端 | `terminal_panel.dart` 标签关闭 SizedBox 为 24×24（约 538 行）。已有终端键盘/抽屉约束测试。 | 扩大手机目标、评估全屏终端与标签选择；键盘开合时保留输出读位、IME 和 PTY 身份，不能重建终端会话。 |
| 统计/表单/目录 | usage_page 有 LayoutBuilder 和分栏转纵向逻辑；模型编辑/目录页有大量独立控件和表单。 | 逐页核验按钮可达、表单错误、长路径、弹窗高度和大字；已有自适应部分通过后保留。不能仅因固定 maxWidth 就判定溢出。 |

Android 官方建议交互目标至少 48×48dp；视觉图标与命中区域应分别处理。[Android 触控目标与辅助功能](https://developer.android.com/guide/topics/ui/accessibility/views/apps-views)。Flutter 的适配建议强调窗口约束、可用空间和共享组件，应结合字号、输入方式处理，而不是只按“手机型号/竖屏”切换。[Flutter 自适应最佳实践](https://docs.flutter.dev/ui/adaptive-responsive/best-practices)。这些指导是设计依据，具体布局仍需当前产品任务流验证。

## 既有验证基础与不足

- `test/ui/composer_ui_test.dart` 已包含 344/390/720/834/1180 宽度下状态和无异常检查。
- `test/ui/settings_import_layout_acceptance_review_test.dart` 已检查 344px/140% 的导入失败与作用域布局。
- `test/ui/settings_compact_switch_hit_acceptance_review_test.dart` 已测开关的扩大命中区域，但用的是 1180×1100，不能当全部手机控件达标证据。
- 已有 `terminal_drawer_constraints_test.dart`、`terminal_keyboard_test.dart`、`predictive_back_test.dart`、`conversation_viewport_test.dart` 等入口；先复用，再补手机流程空白。
- `test/ui/review_capture.dart` 提供真实字体与 PNG 输出，适合后续同数据前后截图；截图生成后必须打开检查。

本轮没有执行这些测试，不能把旧通过结果写成本次手机验收。最明显的缺口是按手机触控完成完整任务流的验收，以及可达性/发现性/返回路径的前后对照。

## 与正在运行专项的交叉

读取 `references/optimization/master-todolist.md` 时，它记录 S1-settings 正在进行，拥有 settings_center_page、新拆页面及相关测试；后续 P2/P3/P4、S2 还将处理 ChatPage、code_renderer、WorkspaceShell。已出现 `lib/ui/settings/update_about_settings_page.dart`。这些是运行中快照，不复述其性能数字作为本轮验证结论。

当前另有 QR/引导、设备目录、AndroidManifest、pubspec 与测试的未提交修改。移动端 prompt 不接管这些功能开发，也不能从旧 HEAD 单独开始后把已实现入口删掉。

因此采用**独立工作区进行并行开发，共享入口按稳定批次集成**：移动端优先拥有 `lib/ui/mobile/`、独立测试和文档；性能/结构侧拥有算法、缓存、协议及正在拆分的 controller。仅约定文件名、在公共目录放一个“锁文件”，不能阻止旧任务继续写入，所以不作为已协调的证明。

## 交付

- [手机竖屏优化长程 Prompt](mobile-portrait-optimization-execution-prompt.md)
- [发给现有性能/结构任务的协作补充](mobile-performance-coordination-prompt.md)

新专项允许针对手机改变导航容器、层级、弹层和触控密度；这是本次手机体验要求下的有意适配。官方协议/功能/门控继续保留，宽屏维持原有基线，手机设计差异单独记账，不冒称官方像素同态。
