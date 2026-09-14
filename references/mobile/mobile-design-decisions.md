# 手机竖屏设计决策（mobile-design-decisions）

维护基线：2026-09-15。本文件是手机竖屏体验专项的有意设计差异记录，只约束 compact 场景；
宽屏（≥600 逻辑像素可用宽度）继续沿用桌面像素基线，不受本文档回退。
本文件不改变官方协议、功能、字段、能力门控与业务确认语义。

## 1. compact 判定规则

- 唯一判定输入是 **LayoutBuilder 给当前容器的真实可用约束 + MediaQuery 的 SafeArea/viewInsets/textScaler**。
  禁止用设备名、`Platform.isAndroid`、`Orientation` 单独判定。
- `MobileLayout.isCompact(width, scale)`：可用宽度 `< 600 * scale` 时为 compact 候选（scale =
  `textScaler.scale(14)/14`，与 `WorkspaceShellLayout` 现有缩放算法一致）。600 是候选默认，
  逐组件按内容实测调整；调整必须记录在本文件并附证据。
- **Composer 例外**：Composer 内部继续用自身容器宽的 384/576/672 断点，
  不得用窗口宽替代其容器宽（不变量 6）。mobile 组件不重复实现该逻辑。
- **Composer 触控放大下限**：触控目标放大（发送钮/chips 48 行）要求容器宽
  ≥ 312（即 320 最小手机视口扣除对称 padding）；更窄的桌面窗口与弹层 rig
  保持官方尺寸——放大行放不下，强行放大只会横向溢出（composer_menu_test
  narrow submenu 用例为守护）。记录于 2026-09-15 M3-1/M7 矩阵修正。
- **Composer 触控放大方向门槛**：仅竖屏（视口高 ≥ 宽）放大；横屏矮视口
  （如 844×390 + 键盘 inset 时 48 行纵向溢出，voice_preview_keyboard 验收
  用例为守护）保持官方尺寸。140% 大字时 compact 上限达 840，横屏 844 宽
  因此必须叠加方向门槛。记录于 2026-09-15。
- `ShellGeometry.resolve` 现有 640/1000 断点保持不变；compact 布局策略叠加在其上，
  不改写宽屏几何。

## 2. 触控目标规则

- compact 场景下所有可交互目标（含语义命中区）≥ 48×48 逻辑像素，实测以
  `Semantics` rect / hit test 为准，不以图标视觉尺寸为准。
- 图标视觉尺寸可以保持 16–20（延续现有 `LucideIcon` 体系）；扩大的命中区不得与
  相邻目标重叠、不得越出父裁剪区。禁止用透明覆盖层伪造相邻大目标。
- 视觉尺寸与命中尺寸分离：`MobileIconButton`（`lib/ui/mobile/touch_target.dart`）
  对外提供 `visualSize` 与 `hitExtent`，默认 `hitExtent = 48`。
- 长按快捷入口保留，但同一目标的长按菜单与单击动作语义互斥测试覆盖
  （单击不触发菜单、长按不触发单击）。

## 3. 弹层与选择面板

- 宽屏保留现有锚点弹层（`composer_popover` 等），行为不变。
- compact 场景下承载复杂选择（模型/模式/引用/设置分类/终端标签）使用
  `MobileOptionSheet`（`lib/ui/mobile/option_sheet.dart`）：底部面板，含
  标题、搜索（可选）、可滚动列表、选中态、取消；遵守 SafeArea + viewInsets，
  键盘弹出时标题/取消/主动作保持可达，列表内部滚动。
- 同一 controller / 提交回调复用，mobile 面板只是呈现层，不建第二套业务状态。
- Back 关闭顺序：系统 IME → 当前 mobile 面板/弹层 → 面板详情 → 面板 →
  设置/导航页 → 任务页。一次 Back 只退一层，取消不产生导航副作用
  （`PopScope` 逐层登记，不做全局固定栈）。

## 4. 信息层级与文本

- 正文/表单字号从现有主题 token 出发，支持系统大字（TextScaler 140%/200% 进验收）。
  禁止用缩小字体或点击目标的方式通过布局测试。
- 次要信息可折叠，但关键状态、来源身份与错误必须当前可见、可理解；
  缺值不补 0%/100%（不变量 5）。
- 页面不得出现全页横向滚动；代码/diff 的横向滚动只允许发生在局部容器。

## 5. 状态与导航保留

- A→B→A、设备切换、搜索返回、旋转前后：草稿、附件、阅读位置、选中文件、
  来源身份全部保留；不新建重复 route/连接/订阅。
- 移动导航容器（任务入口、更多菜单、底部面板）只复用现有状态源；
  `WorkspaceShellLayout` 的 sidebar 子树保持策略（注释 78-80 行）不被破坏。

## 6. 与桌面像素对齐的关系

- 宽屏非退化由既有 ui-parity 验收保护；本文档的手机差异**不标记为官方手机同态通过**。
- 手机有意差异（命中区扩大、底部面板、更多菜单分层）记录于 mobile-todolist.md
  对应条目的“设计依据”，桌面像素审计不得以同态要求回退这些条目。

## 7. 证据规则

- 每条验收保存：源码身份、测试名、真实 rect/命中数据、PNG 截图（打开检查过）。
  证据目录 `build/mobile-portrait/<批次>/`。
- 模拟器证据只能证明布局与交互；实体机单手/IME/系统手势结论必须来自真机，
  否则标“待真机”。

- **无障碍语义规则（2026-09-15 批次）**：MobileOptionSheet 选择行必须
  带 Semantics(button/selected/enabled)（裸 InkWell 只注册 tap，TalkBack
  读作普通文本）；MobileIconButton 经 Tooltip 暴露 tooltip 字段语义。
  语义树断言用树序而非屏幕坐标（widget 测试 rect 无祖先 transform），
  新 API 用 flagsCollection（isButton bool、isSelected Tristate.isTrue）。
  由 semantics_walk_test 守护；真人 TalkBack 深检只需评估焦点与手感。
