---
name: project-cognition
description: ZcodeRemote / Zemote 仓库的项目认知与开发经验。用于本仓库功能开发、协议/连接排查、Flutter UI、Android 能力、测试和阶段交付；提供架构约束、作用域与凭据保护、PowerShell 验证流程和真实回归经验。
---

# Project Cognition：ZcodeRemote V2

本项目复刻官方 ZCode 远控协议和界面，采用 Flutter 原生 UI、Dart 业务逻辑，Android 系统能力通过 Kotlin/MethodChannel 接入。旧 Zemote 经验可以复用，但旧目录、完成状态和发布路线不能直接当作当前实现。

## 开始工作

- 本仓库开发先加载本技能；首次接续时读 [开发规则与作用域](references/development-rules.md)，之后按模块加载下表资源，不必每次全文重读。
- 仓库根目录相对于本技能为 `../../..`。当前机器路径是 `D:/WorkSpace/ZcodeRemote`；移动工作区后按相对路径定位，不把本机路径当作跨机器约束。
- 先核对工作区与当前明确要求，保留已有未提交改动。用户要求暂停或只整理文档时，按该范围处理，不因旧全局目标自动继续开发。
- 官方基线、最新待办与验收状态保存在仓库文档；不要把瞬时任务标题、测试数量、设备端口和 APK 哈希固化为长期技能规则。
- 本技能不增加远程写入、发布或外部通信授权。既有授权持续有效；常规已授权工作直接执行，缺少必要授权的动作留在具体边界处理。

## 按需读取

| 当前任务 | 读取资源 |
| --- | --- |
| 开发规范、异步作用域、真实环境边界 | [development-rules.md](references/development-rules.md) |
| 编解码、握手、重连、Channel/V4 | [protocol-map.md](references/protocol-map.md)，其链接指向当前仓库协议地图 |
| PowerShell 快测、原生 QA、构建、安装、截图、归档 | [release-and-testing.md](references/release-and-testing.md) |
| 竞态、中文 IME、辅助功能、手势、原生测试排错 | [regression-debugging.md](references/regression-debugging.md) |
| UI/Composer/引用/视觉 | [当前官方 UI 记录](../../../references/official-web-ui.md)、[Composer 协议](../../../references/composer-v2-protocol.md)、[固定资产基线](../../../references/official-web-baseline.json) |
| 项目当前进度及未完成范围 | [全局验收表](../../../references/v2-goal-acceptance.md)、[详细接续手册](../../../references/v2-progress-todolist-2026-09-09.md)、[实施记录](../../../references/v2-implementation.md) |
| 更早的回归或对话页结构取证 | [历史 lessons](references/lessons.md)、[历史对话规格](references/conversation-page-spec.md)；先看文件顶部的适用说明 |

## 当前架构入口

| 层 | 职责与入口 |
| --- | --- |
| `lib/protocol/` | **全部纯 Dart**。connection_params → proof → relay_client → rpc_transport → ipc_codec/channel_client；zemote_client 管理 bridge 生命周期；conversation 管理 V4 快照/增量/历史。通知对象使用 observable.dart |
| `lib/state/` | AppSessions / DeviceSession、WorkspaceMonitor / Catalog、ComposerController / Store / Input / References / Attachments、Usage / PlanResets、RecoveryJournal；UI 侧沿用 ChangeNotifier/ValueNotifier |
| `lib/ui/` | WorkspaceShell / shell、ChatPage / ConversationViewport、composer、usage、客户端设置与插件页 |
| Android | MainActivity、AttachmentPicker、TaskProgressService；系统权限、Keystore、附件缓存、时区、通知等 |
| `lib/update/` | 检查更新、版本/通道与 ABI 选择；应用内下载/安装是否完成以当前代码和验收表为准 |
| `test/` / `integration_test/` / `tooling/` | 协议与状态回归、原生合成服务 QA、只读探针、截图和源码冻结工具 |

完整 diff/终端、远程设置、离线语音和更新安装属于 V2 目标；不要因为旧架构图曾列出这些模块，就声称当前已实现。

## 必须保持的不变量

1. **先查官方再改协议**：方法、字段、门控和事件必须有依据；合法单元素 Initialize `[200]` 不能被当坏帧。握手兼容版本与客户端发布版本分开，当前兼容值先查源码，不用应用版本替代。
2. **连接代次与独立来源**：早到帧缓冲、旧代次丢弃；bridge 恢复需新栈和 Initialize 后再恢复订阅，不重新引入“重试 15 次后放弃”。一个空列表不能擦掉另一独立来源。
3. **提交确认**：首发只提交一次；配置失败保留已确认状态；健康等待或回执超时不能自动补发。已受理但结果未确认的额度重置只查状态。
4. **作用域**：设备/transport、工作区、会话、供应商/组织/项目、范围/时区分别建模。切换或释放后，旧请求不能更新新对象；共享协调器只在正确范围内去重。
5. **数值语义**：上下文总量、来源字符占比、套餐余额和 MCP 配额分开；缺值不补 0%/100%；应用累计与范围统计、应用与套餐选择彼此独立。
6. **布局与阅读**：Composer 用自身容器判断 384/576/672 断点，侧栏断点另算；用户真实滚动决定跟随，不能靠接近底部的静态距离重新吸底。
7. **主题与视觉**：颜色走主题 token，图标取官方资源；检查实际 JS/CSS/字体/显示条件。合成图不是官方同态对照，生成图片也不等于检查布局。
8. **凭据与 QA**：真实凭据只在运行时和已有加密存储；真实验证默认只读，写入使用假服务。Android QA 使用独立 `.qa`，产品为 `.dev`；额度 audit 仅保护三个额度写 RPC。
9. **原生兼容**：Kotlin/Gradle 改动实际编译 Android；沿用已验证的通知/上岛路径。升级 AndroidX/SDK 前检查 API 可用性及 AAR 的 minCompileSdk，不凭 API 名字猜能编译。
10. **交付证据**：版本同步 `pubspec.yaml`、`lib/update/app_version.dart`、`test/update/update_checker_test.dart`；保留完整测试、安装字节、签名及源码状态。阶段通过不等于全局 Goal 完成。

## 使用与维护

协议/连接/状态缺陷补能复现失败的回归；UI 和平台问题按需要补连续交互、实际渲染或原生验证。先跑最短相关集合，再做阶段完整检查，避免无新疑点时反复全量构建。

新增经验按“症状 → 根因/证据 → 修复 → 适用边界 → 验证入口”维护在对应参考文件。规则、命令和回归经验分别维护，减少复制；历史规格保留出处和日期，发现过时说明应纠正或标注，不能让多个版本同时声称是当前规范。
