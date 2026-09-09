# 侧栏同步与辅助功能阶段（2026-09-09）

本阶段版本 0.1.0+10，已构建、双端覆盖安装并冻结源码。全局 A–F Goal 尚未完成；2026-09-09 按要求暂时停止功能开发，整理 [进度与接续手册](D:/WorkSpace/ZcodeRemote/references/v2-progress-todolist-2026-09-09.md)。

## 发现与修复

### 置顶和归档列表的时序

原 `WorkspaceTaskCatalog` 总是优先使用全局索引中的成员标志。置顶成功后，新的 pinned 列表会清除本地确认值，旧索引的 false 随即覆盖该结果。新增测试先复现 false，见 `v2-sidebar-membership-before.log`。

现在 pinned/archived 读取记录各自启动时的修订号；全局推送或本地已确认操作发生后，旧请求不能更新成员状态。新请求的结果可以确认新状态，之后的全局推送仍可更新。`WorkspaceMonitor` 传递对应修订号，保留任务双来源合并和按设备/工作区隔离的行为。状态与实际 monitor 回归均通过。

### 原生连续长按

实机原生测试复现：从长按菜单置顶后，下一次长按不触发菜单；只按分区重建任务行只能覆盖部分情况，标记未读后仍会发生。最终在长按手指抬起后打开菜单，让原手势先完成；辅助功能 long-press action 独立保留。普通点击、右键和任务行状态继续使用原逻辑。`v2-sidebar-gesture-before.log` 保留初始复现，完整连续操作在最终测试中重新验收。

### 可选 Markdown 链接使 Android 辅助功能树失效

独立 `.qa` 入口 `tooling/accessibility_probe.dart` 使用合成数据，不连接远程桌面，也不使用 Flutter 测试运行器。

| 场景 | 第一次 / 第二次 UIAutomator 标签数 |
| --- | --- |
| 静态 Flutter 页面 | 7 / 7 |
| 普通弹窗关闭后 | 7 / 7 |
| Composer 浮层关闭后 | 7 / 7 |
| 普通页面返回后 | 7 / 7 |
| 变高的长消息 Text 列表 | 9 / 9 |
| 空消息的任务壳与 Composer | 12 / 12 |
| 原可选 Markdown（含链接、表格、代码） | 55 / 0 |
| 单独 SDK SelectableText.rich + 链接 | 5 / 0 |
| 修复后的富文本任务页（平板） | 47 / 47 |
| 修复后用量页返回（平板） | 47 / 47 |
| 修复后的富文本任务页（手机） | 34 / 34 |
| 修复后用量页返回（手机） | 34 / 34 |

本机 Flutter 3.47.2（`d3b14c876900e553bc736ca19295fc09e3853e8e`）、Dart 3.13.2 的 `RenderEditable` 缓存链接片段的 SemanticsNode，缺少 `RenderParagraph.clearSemantics` 对应的清理；原生最小案例支持将故障范围定位到可选链接的语义生命周期。

聊天 Markdown 改用 `SelectionArea` + Markdown 的 `Text.rich` 路径，保持链接文字、表格、代码与选择复制。没有让产品强制常驻语义树。新增复制回归验证长按后“全选/复制”包含链接文字及完整第二段，不带原始 Markdown 链接标记。

证据在 `build/visual-audit/recovery-qa/accessibility-*.json`、`accessibility-*.png`，旧/新独立 QA APK 也保留以供复现。修复前后同态合成正文区域 6,065,952 像素中 8,128 个像素不同，主要文本绘制路径变化；不据此声称像素完全一致。

## 原生任务管理验证

`integration_test/task_management_test.dart` 使用实际 `WorkspaceShell`、`TaskNavigation`、`WorkspaceMonitor` 与合成 Channel 服务，原始全局索引保留旧状态以覆盖本次修复。范围包括置顶/取消、重命名并去除两端空白、标记未读、归档确认/恢复、服务端拒绝时保持原状态、取消删除和最终一次删除。所有写请求都只作用于选中 workspace/task，对照任务正文保持不变。

手机与平板最终完整流程均通过，另含深色英文 140% 菜单的可达与关闭检查；12 张截图为 `phone/tablet-sidebar-*`。原生文本框光标持续产生帧，重命名窗口使用有限时长等待，避免测试等待光标停止。

真实 ROG 的 +10 连续读取为 85/85 个标签，进入统计页后返回仍为 85/85；已实际打开任务长按菜单，仅查看未执行写入。ROG 套餐累计 40.1 亿、近 7 日 8.2 亿仍与前序只读记录一致。手机最小合成任务验证为 34/34；真实手机期间由你手动切换任务，已确认不是恢复故障。接续时保留你最后选择的 ALI/MCP SSH 任务与原阅读位置，不继续沿用最初 bike_refund_group 任务作为当前状态。

## 最终产物与检查

- APK：`build/artifacts/ZcodeRemote-v2-sidebar-accessibility-dev.apk`，124,853,792 字节，`.dev` 包名，ARM64/x86_64 Flutter 引擎；两台实际安装字节一致。
- APK SHA-256：`02bfd62a64cee65bf9e64af660da3515973d5847a6086090f19e775346468813`；证书 SHA-256 `b020bef5c510b8ce9ba783349f4170d178fc279411ca4042287b1c91151a4857`。
- 183 文件源码 ZIP SHA-256：`4d21b611b0c59fc39db82381620b0f80822c1fa0dc4c8b71fb4d2b1b0e1cdad2`；源码状态 `077d670ad8f14dee8ef484133f5776c3b9942091c20313e876822fceedb3ae78`；基准提交 `450164e081549c083ef2bec6c6f6e0635e08513f`，保留未提交改动。
- 368 项完整测试通过，analyze 零问题，纯 Dart smoke 通过，153 张 Flutter 渲染。完整日志 `v2-sidebar-accessibility-all-tests.log`、`v2-sidebar-accessibility-analyze.log`、`v2-sidebar-accessibility-protocol-smoke.log`，原生日志 `v2-sidebar-native-phone.log` / `v2-sidebar-native-tablet-final.log`。
- 安装证明：`build/visual-audit/recovery-qa/sidebar-accessibility-installed-apks.json`；阶段 manifest 和 source.zip 已生成。以上代表本阶段的代码与证据，不替代尚未完成的官方整页视觉和全局验收。

## 官方依据及剩余范围

- 固定官方主包 `ECt/KEt/XEt`：独立置顶、项目/时间线、归档、排序、确认与按 workspace/task 操作。`KEt` 的前置状态为切换/修改中 spinner、未读点和图钉；远控侧栏没有单独从 task.phase 生成运行图标，不能与移动首页 `m4` 混用。
- 触屏长按与当前任务的可见操作保留既定客户端适配。实际完整官方成对视觉核查、A/B/C 其余组合仍按全局清单处理。
- 本阶段只修复 F4 中已复现的辅助功能缺陷；折叠、键盘、预测返回和 ColorOS 16 真机组合仍需分别完成。
