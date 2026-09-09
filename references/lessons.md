# 踩坑记录（按主题分类，源自 CHANGELOG 与修复历史）

## 0.1.0+10 新增经验（2026-09-09）

- **可选链接与辅助功能重注册**：本机 Flutter 3.47.2 的单个 `SelectableText.rich` + 链接原生案例会从首次 5 个语义标签变为第二次 0 个；普通 Text/弹窗/浮层均正常。聊天正文改用 `SelectionArea` + Markdown 的 `Text.rich` 路径，保留跨段落选择复制，双端和真实 ROG 返回后重复查询正常。不要用频繁重启或产品强制常驻语义树代替修复。
- **长按与路由生命周期**：长按开始就打开任务菜单，原生连续操作可失效；只重建分区行只能掩盖部分情况。最终使用 `onLongPressUp` 打开菜单，并以独立 Semantics long-press action 保留辅助功能操作；验证必须连续做置顶/取消、改名、未读、归档/恢复等。
- **成员状态来源要带读取修订**：不能总让全局索引优先，也不能按响应到达顺序覆盖。`listPinnedTasks` / `listArchivedTasks` 记录启动修订号，晚于全局推送或本地确认的旧请求被丢弃；新的读取可以确认最新状态。
- **原生测试等待具体条件**：聚焦文本框的光标可能持续排帧，重命名窗口不要无限 `pumpAndSettle`；平台回调内记录调用，在测试主流程断言，避免业务 catch 吞掉测试失败。
- **共享模拟器要确认操作者**：本轮手机切换任务已由你确认是手动操作。页面变化先核实，不直接归因为恢复缺陷，不擅自切回测试开始时的旧任务。

当前完整接续清单、环境命令、旧记录差异及验证规则见 [进度与开发手册](D:/WorkSpace/ZcodeRemote/references/v2-progress-todolist-2026-09-09.md)。

## ZcodeRemote 原生迁移补充（2026-09-08）

- 2026-09-09 `@` 文件候选真实超时根因：RPC 接收端错误套用了本地发送用的 512 KiB 分片大小，合法的 700 KiB 分片被静默丢弃；ACK 同时漏了 bridgeGeneration/recoveryId，官方 `a2t` 会按完整身份拒绝。接收按官方物理帧预算校验，ACK 复用完整 identity，代次/恢复标识不同的帧不进入当前栈。修复前 ROG-STRIX 文件查询 20/60 秒超时，修复后相同只读探针返回 6,180 项。不能仅通过小列表/小消息测试判定协议完整。

- 2026-09-09 桥接恢复：官方 `workspace-reconnect-request` 只重连工作区后端，不能代替 `workspace-bridge-open`。旧实现 cheap path 成功就把旧 Channel 标为健康，已通过假对端复现。恢复需新建栈、等 Initialize、再通知订阅恢复；切栈前记住旧 bridge ID，否则 `_swap` 后再取旧 ID 会留下旧路由，迟到帧进入已关闭 stream。恢复不可在 15 次后静默停工；仅恢复失效工作区。
- 握手绑定开始时的 Channel 与代次。旧 hello 不能在新通道发 initialize；旧失败不能无条件清空共享 `_handshakeFuture`，否则新通道会并发重复握手。待健康操作在 bridge dispose 时立即失败，不能把 dispose 当作已恢复。

- 2026-09-09 实际 ALI 同任务 441px 对照发现：官方 `@container/composer` 在 `chat-composer-region` 上，位于带边框/12px padding 的输入 surface 外侧。不能用更内层工具条扣除 padding 后的宽度查询断点，否则 409px composer 会被当成 383px，模型名/思考条提前消失。Flutter 在 ConversationColumn 内、surface 外用 LayoutBuilder 取 region 宽，工具条仍按自身实际剩余空间约束文本；主辅各自查询，绝不用屏幕宽。对应 `surface padding does not move the official composer region breakpoints` 回归。
- 官方完整任务索引使用省略字段表示非置顶/非归档（CCt 删除属性）；不得仅处理显式 false。全局索引与 local sessions-index/channel 列表按更新时间合并字段，空快照继续独立保存；旧 pin/archive 请求不能撤销更新的全局投影。
- GLM 源选择失败后不能继续刷新旧账户的额度；重连时源 key 可能仍相同但账户已变，必须失效缓存。缺余额/分母不是零，Start/套餐/MCP 各自显示未知，不编造百分比。

- Composer 异步操作应属于设备/工作区/会话，而不是只属于可销毁的输入组件；首发成功后迁移文本、配置、阅读、布局和导航缓存，即使路由已经退出也不能遗留旧 draft key。
- prepare 响应需要请求代次保护；会话配置 ack 需要 revision 下界保护。重连不能重放另一个 pane 的 workspace draft，也不能让已失效的模型切换回复覆盖新选择；在旧请求结束前禁止新配置写入。
- 连接断开不证明发送未到达。健康超时不重发；断线单次重放必须保持原 commandId，不能换成新操作。思考档位错误只能按返回元数据处理，禁止猜一个其他模型家族的默认值再写入。
- 官方停止从 activeWorks 携带 expectedForegroundExecutionId，防止旧按钮停止下一轮任务；旧停止 ack 也不能把已经更新的运行投影标记成 stopping。
- 官方队列确认是 UI 的 confirmationRequired，协议 status 不含该值；服务端 reasonCode 为 guard.heldQueueConfirmationStale。测试应检查真实回执字段，不能把 UI 返回值冒充协议字段。


- 响应式工作面板保持同一 Stack 子树，通过 Positioned 宽度和 Offstage 调整摆放；不要在 Row 与覆盖层之间条件重建辅助 ChatPage。切换面板 tab 用 IndexedStack，隐藏时隔离焦点。五形态测试要断言订阅没有重复，而不只断言草稿文本仍存在。
- 嵌入式 ChatPage 禁用自己的 `resizeToAvoidBottomInset`，由壳 Scaffold 统一避让；否则键盘底距计算两次。测试注入 300dp viewInsets 后，composer 应恰好上移 300dp。
- `Color.withValues(alpha: .5)` 会替换原 alpha，不是把现有透明度乘半。官方 `border-border/50` 对 10% 线应得到 5%，需用 `ink.border.a * .5`；此前错误替换会把浅色分隔线变成重黑线。
- 同一个 session 路由重复压栈会建立多个订阅和多个草稿编辑器。按 device/workspace/session + 当前 monitor 复用已有路由，新任务首次创建后更新路由身份；异步连接完成前后都校验最近导航代次。
- Widget 测试中的设备保存若触发未模拟的 Android MethodChannel 会卡在 fake async。UI 故障注入测试显式提供合成 encrypt 回调；真实 Keystore 仍由 Android 集成测试验证。

- 原生前台服务不会自动保留 Flutter 引擎。监控期间根页面 `SystemNavigator.pop` 若结束 Activity，就可能只剩静止通知。使用 `FlutterActivity.popSystemNavigator()` 在任务监控中将根 Activity 移到后台；移除最近任务/真正结束 Activity 时停止服务。集成测试必须验证后台还能调用 Dart→native 更新，而不只检查通知创建成功。
- Flutter 的 `addPostFrameCallback` 不会自行请求新帧。暖启动通知点击可能发生在空闲帧之间，路由恢复应调用 `ensureVisualUpdate()`；否则点击看起来无响应。通知 URI 用于 PendingIntent 唯一性，关闭 Flutter 自动 URI 深链，路由统一交给包含设备/工作区/任务的 `TaskTarget`。
- AndroidX Core 1.18.0 的 Live Updates compat 已编译验证；AGP 当前配置默认关闭 `resValues`，使用调试包专属应用名称时必须显式启用 `buildFeatures.resValues`。
- 加密只发生在存储边界，不能把 `enc:` 数据放进运行时 URL 解析器。Android 加密失败不能静默降级明文；本地设备主键不得直接用配对 sid，以免通知 payload 泄露凭据标识。

修 bug 或设计新功能前扫一遍对应主题；修复后把新经验追加到这里。

## 连接与重连

- **后台切回连不上**（0.5.1-beta.2）：从其他应用返回、锁屏解锁后停在"重连中"无法恢复。
  多个重连请求并发时旧 WebSocket 事件覆盖新连接状态。教训：重连路径要防并发覆盖。
- **误判"被踢下线"**（0.5.1-beta.2）：连接冲突被当成永久踢下线。认证阶段先执行一次干净
  重连再判定。
- **bridge 不恢复**（0.3.5）：relay 心跳超时触发重连时跳过了 `reconnecting` 状态，导致配对
  后 bridge 不恢复。状态机迁移不能跳步。
- **重连后发消息超时**（0.3.2/0.3.3）：relay 断开时立即标记 bridge 降级，命令在恢复前排队
  （`waitHealthy`）；发送超时后等重连并自动重试一次；恢复循环重试到成功为止。另外
  `sendText` 在连接健康时超时**不**自动重发（避免重复消息），只在断线中重试。
- **冷启动预热超时**（0.3.5）：会话首次订阅放宽到 60s，避免打开聊天页时误判"连不上"。
- **泄漏**（0.3.3）：`ZemoteClient.dispose()` 必须释放活动桥；订阅初始化失败要清理事件
  监听和定时器。

## 协议帧与握手

- **单元素帧 `[200]` 被误杀**（0.4.2/0.4.3，两次回归）：合法 Channel Initialize 帧
  `[200]` 被边界检查判为畸形 → `listTasks` 和 sessions-index 永远等待 → 会话列表无数据。
  教训：帧校验边界以官方行为为准，回归测试锚定。
- **握手版本协商错误**（0.4.2/0.4.3）：Conversation V4 握手曾错误携带 Zemote 应用版本
  （`0.x`）参与桌面能力协商。正确做法：协议能力版本固定 `3.6.5`。
- **首条消息发不出**（0.3.1）：订阅未就绪时命令被丢弃。对齐官方 composer：普通文本首条
  消息随 `createSession(firstInput)` 一起发送；附件/目标指令路径发送前等待订阅建立。
- **ack 不检查**（0.3.1）：`sendText` / `sendGoalCommand` 的 ack 被忽略导致发送失败静默。
  所有发送路径必须检查 ack 并提示具体原因。
- **交互格式错**（0.4.1/0.3.2）：AI 多问题交互的答案是一次性 `accept` 提交；权限请求选项
  按官方 schema + 自由输入；`questions` 表单（单选/多选）。

## 数据合并与状态

- **双数据源互相清空**（0.4.3）：channel 任务数据与 sessions-index 实时数据必须独立保存
  再合并；空快照、晚到响应、订阅失败都不得清空对方。
- **跨工作区串数据**（0.4.1）：从聊天页返回后要按当前工作区 sessions-index 重新合并会话
  列表，避免缺项、旧顺序、跨工作区任务混入。会话列表缓存按工作区隔离（0.5.0）。
- **骨架屏卡住**（0.4.2）：sessions-index 快照到达后立即结束加载，不被旧任务 RPC 的超时
  骨架屏遮住；空列表也要正常结束加载。

## 消息渲染

- **气泡顺序颠倒 / 拆分**（0.3.2/0.3.3/0.3.4）：保留服务端原始段落顺序
  （思考→文本→工具→文本…），连续文本合并，一条回复一个气泡、一个点赞区（只在最后一个
  文本段）；`turnId` 中途变化不拆散分组。
- **滚动定位**（0.3.4/0.3.5/0.4.1）：打开聊天页完成初始历史加载后强制定位到最新；向上翻
  历史时流式更新不拉扯；加载更早消息后若在底部则自动回底。

## UI / 主题

- **自定义弹窗必须继承局部主题**（V2 细节批）：`showGeneralDialog` 不像 `showMenu` 自动捕获触发器的主题。用 `InheritedTheme.capture` 包住新路由内容；弹窗内部的 `DefaultTextStyle` 应使用 `merge` 或基于当前 TextTheme，避免抹掉字体。合成截图的方块字并不一定是系统缺字，先检查跨 Overlay 的字体继承。
- **Composer 高度按容器拆解核对**（V2 细节批）：官方输入正文 `min-h-10`=40px，外层 `gap-3`=12px，按钮 28px，加 12px 内边距及边框后常态约 106px。只把按钮从 32 改为 28，而保持单行输入的自然高度，会使整体比官方矮约 19px。
- **官方 MCP 展示不是把协议名首字母大写**（V2 细节批）：优先 V4 `display.kind=mcp_tool` 的 serverName/toolName，再按 `mcp__server__tool` 拆解和去掉重复前缀；未知工具保留明确回退，原名进入可展开详情。思考 durationMs 缺失时官方文案是“持续了几秒”，不能拼成“思考 · 持续了”。

浅色主题下"白底白字/不可见"是本仓库反复出现的回归类型，中过招的组件：代码块与行内代码、
推理面板、工具卡片、状态点、Diff 内容、骨架屏、Markdown 标题/列表/表格（0.2.1/0.3.2/
0.4.3/0.4.4/0.5.2）。**规则：任何颜色必须来自 `ui/theme.dart` 的 ZInk 主题感知体系，
禁止硬编码颜色。** 新增 UI 后浅色/深色都过一遍。

布局类：任务首页固定模块过多曾把任务列表压到半屏（0.5.2）；低频操作收进按需展开；文案
不直接显示内部状态值（如 `completedSuccess` 要映射成人话）。

## Android 平台 / 更新

- **APK 按 ABI 拆分 + MD5**（0.4.2）：`arm64-v8a` / `armeabi-v7a` / `x86_64` 三个产物各带
  `.md5`；安装前校验。
- **下载健壮性**（0.4.1/0.4.2）：断点续传；本地已有且 MD5 正确的包跳过下载直开安装器；
  APK 存放在应用内部 `files/update` 目录，FileProvider 只暴露该目录；升级完成后靠
  `MY_PACKAGE_REPLACED` 广播自动清理旧包。
- **Beta 通道重复提示**（0.5.2-beta.2）：更新检查曾用旧硬编码版本常量，装了 Beta 后反复
  提示同一版本。版本常量单一来源（`pubspec.yaml` → `update/app_version.dart`）。
- **签名统一**（0.2.1）：正式 keystore 本地 + CI（GitHub Secrets base64 注入）同一签名，
  否则覆盖安装失败。
- **凭据不进备份**：Android `allowBackup` 禁用 + 凭据加密存储（`credential_cipher.dart`）。

## 安全红线

- 远程控制 URL 含 `sid/hash`，等同设备访问凭证：不入库、不写进测试代码、不外发。
  集成测试用环境变量 `ZEMOTE_PROBE_URL` 注入。
- 拒绝非 HTTPS/WSS 的连接 URL。
- 凭据泄露的补救：桌面端重新生成远程控制二维码，旧凭据立即失效。

## 发版与仓库迁移（2026-09-06，v0.5.3 发版实战）

- **发版守护测试是第三处版本常量**（第一次 CI 失败的直接原因）：`update_checker_test.dart`
  的 "bundled app version matches the release currently being built" 断言 `appVersion` /
  `appBuildNumber` 的具体值。发版 = 三处一起改：`pubspec.yaml`、`app_version.dart`、
  该测试。改完 CI 全绿才准打 tag。
- **比较测试不得依赖 appVersion**：`compareVersions` 语义测试曾把 `appVersion` 混进断言
  （`compareVersions('0.5.2', appVersion)`），版本一 bump 就崩。已改为字面量，后续发版
  不再触碰；新增版本测试同理，只测纯函数语义。
- **仓库指向硬编码四处**：原作者仓库地址曾出现在 `update_checker.dart`（更新检查 API，
  3 处）、`settings_page.dart`（关于页，2 处）、`README.md`（badges）。迁移/fork 后必须
  全局替换，否则应用内更新检查打的是别人的 Release API。
- **文档声称的安全边界要实测**：README 声称 `.gitignore` 已忽略签名文件（`*.jks` /
  `key.properties`），实际条目缺失（已补）。验证方式：`git check-ignore <路径>`，不要信
  文档描述。
- **`keytool -printcert -jarfile` 验不了现代 APK**：Flutter 产物是 v2/v3 签名（无 v1 的
  META-INF/*.RSA），该命令报"不是已签名的 jar 文件"。验证线上包签名的可行路径：解包
  APK Signing Block 抠出 DER 证书 → `keytool -printcert -file`；或看构建日志的签名步骤。
- **CI 绿色 ≠ 正式签名**：Secrets 缺失时 build-apk.yml 只打 WARN 并回退 debug 签名，构建
  依然成功。重要发版要么确认 Secrets 已配置，要么实拆 APK 验证证书 CN。
- **tag 强推只允许发生在 Release 生成前**：修 CI 后曾 `tag -f` 重指向新提交并强推——
  当时 Release 还没产出，安全；一旦 Release 已发布，强推 tag 会造成版本事实分叉，禁止。

## 交互实现模式（2026-09-06，v0.5.4 实战）

- **流式列表滚动拉扯的根因是距离启发式**：旧代码 `pixels > max - 400` 就跟随——流式输出
  时 `maxScrollExtent` 持续增长，静态阈值反复成立，每帧把翻历史的用户往回拽；且普通
  controller 监听分不清用户拖动与程序动画，动画本身又会把 `pixels` 拉回阈值内形成循环。
  正确模式：`_onScroll` 只在 `userScrollDirection != ScrollDirection.idle`（用户拖动/惯性）
  时更新吸底标志（`animateTo` 的 DrivenScrollActivity 期间恒为 idle），跟随只在吸底时执行；
  `ScrollDirection` 需从 `package:flutter/rendering.dart` 导入。判定用"距底部 40px"只在
  **用户滚动时**比较一次，不参与跟随决策。
- **AnimatedSize 必须常驻挂载**：条件渲染 `if (expanded) AnimatedSize(...)` 会让收起动画
  永远不生效——收起时组件连同动画一起被移除，内容瞬跳。手风琴标准写法：每个分组的
  动画容器常驻，child 在"内容"与"零高度盒"（`SizedBox(width: double.infinity)`）之间切换，
  靠 child 尺寸变化驱动展开与收起两个方向的动画。
- **缓存类状态要清理"旧 key"**：输入框草稿按 sessionId 缓存、新会话按 workspaceKey 缓存。
  首条消息发送后 sessionId 从 null 变为真实 id，若不清旧 key，返回再新建会话会冒出已发送
  的内容。模式：会话创建成功时显式 `cache.remove(旧key)`，发送清空控制器会自动写空新 key。
- **宽屏断点用 640dp，别用 800/840**：折叠屏内屏展开宽度约 717dp，840 阈值会把它漏进
  窄屏路径。辅助对话侧滑面板实现：`showGeneralDialog` + `Align(centerRight)` +
  `SlideTransition`（barrierDismissible 点遮罩关闭），ChatPage 可作为普通组件嵌入面板
  （嵌套 Scaffold 合法，ScaffoldMessenger 走根 messenger）。面板宽度
  `(width * 0.55).clamp(360, 560)`。
- **StatelessWidget 的辅助方法访问不到 build 局部变量**：`_modeChip` 最初引用 build 里的
  `sid` 直接编译失败——类方法只能访问字段。要么把值当参数传，要么改用类字段
  （`sessionId ?? ''`）。列表项内需要新 context 时用 `Builder(builder: (context) ...)` 包裹。
- **无 SDK 静态自查抓到过真 bug**：0.5.4 的两个缺陷（手风琴收起动画不生效、草稿旧 key
  残留）都是自查阶段发现修复的，CI 未必能覆盖（无对应 widget 测试）。本机无 Flutter 时
  自查清单：删除符号的残留引用、动画/生命周期组件的挂载周期、跨 key 状态残留、
  闭包捕获的变量作用域、`withValues` 等版本敏感 API 与仓库既有用法一致。

## Android Live Updates 接入（2026-09-06，v0.5.5 实战）

- **framework 的 Live Updates 符号不在 stable SDK 36 里**：`Notification.ProgressStyle`
  类可解析，但其 `setColor` 与 `Notification.Builder.setRequestPromotedOngoing` 编译报
  unresolved——它们属于 API 36.1（Baklava QPR，@FlaggedApi）/ 更新层。官方 compose 文档
  恰好把 compat 方法名写成了 framework 链接，误导性强。**结论：上岛通知一律走 androidx
  compat，不直接调 framework 符号。**
- **androidx.core:core:1.18.0 是甜点位**：`NotificationCompat.ProgressStyle` +
  `Builder.setRequestPromotedOngoing`（写 extra，无 framework 依赖）齐全，minCompileSdk
  =36。**1.19.x 的 POM 传递依赖 core-ktx 1.19.0，其 AAR metadata 要求 compileSdk 37**，
  在 `:app:checkReleaseAarMetadata` 阶段直接构建失败。升级 androidx 前先下载 AAR 查
  aar-metadata.properties 的 minCompileSdk。
- 验证 API 真实存在性的可靠手段（本机无 Android SDK 时）：从
  `dl.google.com/android/maven2/androidx/core/core/<v>/core-<v>-sources.jar` 下载源码
  jar 用 `jar -xf` 解压 grep；framework 事实以 AOSP raw 源码
  （`aosp-mirror/platform_frameworks_base`）与 CI 编译结果为准，官方文档/diff 页可能
  空内容或模型补全有误。
- ProgressStyle 语义：compat 的 progress max 默认 100（`getProgressMax()`），segment
  长度是相对权重；promoted 需 `setOngoing(true)` + `POST_PROMOTED_NOTIFICATIONS` 权限 +
  无 customContentView + 非 groupSummary/colorized + 渠道 importance ≥ LOW。用户可在
  系统设置里关闭某个应用的 promoted 通知（`canPostPromotedNotifications()` 探测）。
- CI 的 ci.yml（web 冒烟）**不编译 Android**——Kotlin/gradle 改动只有 tag 触发的
  build-apk.yml 才会真正编译。首次接入原生 API 时预期 1-2 次构建失败是正常的，修复后
  `tag -f` 重指（Release 未生成的窗口内安全）。

## 官方 UI 对齐实战（2026-09-07/08，v0.5.7→v0.6.6 八轮迭代）

**视觉级证据强于逆向推断**：bundle 的 class 串只保证结构；卡片容器、状态文字、图标、颜色层级这类视觉决策必须用 He 的官方截图校准（v0.5.9 曾"结构对但视觉错"被打回）。主动要截图，比猜快。

**Flutter InputDecoration 三态继承**：`border: InputBorder.none` 只关 border 一态，`enabledBorder`/`focusedBorder` 仍从全局主题漏入（灰边+聚焦蓝边）。一体化输入框（composer、气泡内联编辑）必须三态显式置空。

**AnimatedSwitcher 手势陷阱**：切换瞬间旧 child 仍在层级内、新 child 已可命中，同一手势的抬指可能落在"刚出现的部件"上反向触发（状态胶囊收起点击无效的根因）。形态切换要么瞬时 swap，要么延迟切态。

**SVG path 解析**：小写 `m`（相对移动）之后的隐式线段是相对的（`m5 12 7-7 7 7`），误当绝对坐标会画出飞出画布的"竖线"。lucide 图标大量以小写 m 起笔。

**图标体系**：官方全部用 lucide（main.js 内 `X=Io('name',dataVar)` 定义 + 懒加载 chunk 格式 `var t=[[…]],n=e('name',t)`）。仓库 `lib/ui/official_icons.dart` 是生成物——重抓/新增图标走 `build/gen_icons.py`（icons.json → dart），生成后必须核对 map 收尾 `};` 没被拼接吃掉、无重复键。Dart 侧解析器已修相对移动 bug。

**工具族图标映射**（实抓）：思考=brain、Bash=terminal、Read/Grep/Glob=search、WebSearch=earth/WebFetch=globe、Write/Edit族=file-diff（官方无独立铅笔字形！）、TodoWrite=list-todo、Task/subagent=bot、fork=git-branch（官方无 split）。

**流光真身**（官方 CSS `index-BM2ndL2ru.css`，**样式在 CSS 资产里，别只抓 JS**）：`.animated-gradient-text` = linear-gradient(90deg, strong 0/34/66/100%, soft 50%)，background-size 300%，`gradient-flow` 4s linear——前 2s 从 position 100% 扫到 0、后 2s 停驻；strong=正文色（深 #fff/浅 #0d0d0d），soft=同色 20%/22%。是墨色呼吸，不是彩色闪光。

**层级规则**：进行中行=foreground 墨色+流光标签；已完成行=subtlest（更浅）。turnHeader 时长官方用 BX 函数算：`activeMs ?? endedAt-startedAt ?? now-startedAt`，只读单一字段会拿不到秒数。

**composer 断点=容器查询**：官方 `@container composer/inline-size`（@sm 384/@xl 576/@2xl 672），必须用工具条实测约束宽（LayoutBuilder），用视口宽在平板主从/折叠屏上必错。侧边栏壳断点（768px+触屏判定）是另一套，Zemote 有意下调 640/720。

**脚本工程**：Git Bash heredoc 会吞反斜杠（`'\'`→`''`），带转义的 python 一律用 Write 工具写成文件再执行；循环 curl 里用 `stat -c%s` 判断成败会整批误报，单发 curl 实际都成功。

**协议补充**（逆向）：rowsRange 响应=`{rows:[…], atSeq, atLogEpoch, hasMore}`（rows 是裸数组），schema 对 limit 有 max（rowsRangeMaxLimit，值未挖到，用 50 安全）；官方 loadAllOlder 循环拉到 hasMore=false——单页大 limit 会被拒。turnHeader/turn 时长字段=startedAt/endedAt/activeMs。goal 终态枚举含 completedSuccess（勿原文渲染）。

**辅助对话语义**（官方）：独立 sessionId、创建时携带主会话上下文；隐藏 goal 横幅/重试/分叉/编辑重发/点赞点踩/嵌套入口；保留完整 composer（模型/模式/思考按会话独立）+ 用量环。配置命令按 sessionId scope，串扰是 UI 层共享草稿显示问题。

## 第十一轮反馈批（2026-09-08，未发版）——四个真根因

**胶囊收不起的真根因不是手势**：上一轮把「无法收起」归因为 AnimatedSwitcher 过渡吞手势（见上节），实际是 `_StatusSummaryOverlay.build` 里 `if (!_expanded)` 分支构建胶囊后**没有提前 return / else**，随后的展开面板赋值把胶囊直接覆盖——点收起 rebuild 出的胶囊永远被丢弃，界面恒为面板。教训：**「移除动画修手势」这类解释若无验证就可能掩盖真正的结构性 bug**；同变量两段赋值必查互斥性。本轮已改胶囊分支提前 return。

**SVG 隐式数字分隔（查询工具族整行消失的根因）**：SVG path 允许无分隔符连写数字，第二个小数点即新数字起点（`1.704.706` = `1.704` + `.706`；`c0 1.1.9 2` = `1.1` + `.9`）。解析器把整段吞成一个 token，`double.parse` 在 **paint 期**抛 FormatException → release APK 里所在工具行整体渲染失败（earth=查询/WebSearch 族、file-diff=写入编辑族均中招）。已按 SVG 数字文法在第二个小数点分词；**回归测试逐字形 pump 全部 LucideIcon 并断言无 paint 异常**（test/official_icons_test.dart），新增字形必须过这道闸。

**图标名缺失 = 静默空白**：`LucideIcon(未知名)` 渲染空白 SizedBox 不报错——`git-branch` 字形从未入库，分叉按钮在 APK 里一直是隐形占位（He 报的「四个按钮错位」实为第四个按钮不存在）。图标引用走变量（`lucideIcon: 'name'`）时编译期查不出，**入库新图标后要 `grep 引用名 vs kOfficialIcons 键` 对账**；官方图标测试已断言关键字形存在。

**LayerLink.leader 是 LeaderLayer 不是 RenderBox**：popover 定位强转 `as RenderBox?` 在 leader 挂载后必抛 TypeError（debug 红屏、release 静默无反应）——用量环点击「没有任何效果」整一轮都是这个。取锚点 RenderBox 的正路是给目标 widget 挂 GlobalKey 再 `currentContext.findRenderObject()`。

**操作行时机（官方语义补全）**：复制/点赞/点踩/分叉只在轮次结束后出现——门控必须用**轮次级** running（`_rowIsActive`：流式文本/执行中/待确认/turnHeader running 任一即压住），按文本段自己的 streaming 判定会在工具调用间隙闪出按钮。

**工具族 id 容错**：桌面流式下发的 toolName 大小写/下划线形态不定（`webSearch`/`web_search`），MCP 形态是 `server__tool`。`resolveToolFamily`（公开顶层函数，有单测）先精确归一化匹配、`__` 尾段解析，查询类模糊回退保持「搜索」族标签与 earth/search 图标。
# 草稿持久恢复与原生附件验证（2026-09-09）

- 保存阅读锚点不等于完成冷恢复：先加载到所在历史页，再定位未构建的变高消息。列表使用固定版本 `super_sliver_list 0.4.1` 的索引定位，继续以实际消息 key 和局部偏移校准；只渲染所需范围。组件依据见 [维护者说明](https://github.com/superlistapp/super_sliver_list)。
- 原生阅读测试发现，ScrollController 通知发生在布局之前；此时直接 `localToGlobal` 记录的是上一帧位置，下一帧恢复会抵消刚发生的拖动。只由真实用户滚动设置待记录标记，在布局结束后记录锚点，并让它优先于恢复跳转。问题不在 SelectableText，保留原文本选择组件。回归含真实文字区域拖动，不能仅检查 following=false。

- 文件选择器返回的临时 URI 不能作为重启后的唯一来源。选中时复制到应用私有缓存，先 `.part` 写入、同步再重命名；保存随机 token / SHA-256 与元数据，读取验证路径及摘要。不存在或损坏时保留可见条目，禁止静默发送缺文件的文本。
- 保存不能只做普通防抖：提交前和后台切换须 flush，写入串行合并且保留上一有效快照。等待远端回执时保存不确定状态，重启不自动重发；远端已接受后的本地保存失败不能变成“远端发送失败”。
- 设备移除与存储读取也会竞态。恢复前后检查已移除设备，涵盖编辑器、配置、导航、阅读和面板；仅清当前 map 不能防止 await 后复活旧条目。回归见 `recovery_test.dart`，保留了修复前失败日志。
- `/plan` 解析后的异步模式准备属于整个提交事务；在进入准备时就参与发送去重，不能等 RPC 发出后才置 busy。
- Flutter `test integration_test` 默认在退出时卸载测试应用。验证进程恢复时用独立 `.qa` 包并显式 `--no-uninstall`；验证入口启动先断言包名，不将测试入口装入保留真实数据的 `.dev`。
- 集成测试期间运行 uiautomator 会临时开启语义树，导致测试结束 `SemanticsHandle was active`。选择系统文件时使用 ADB 原生截图定位点击；不改变业务断言来规避真正缺陷。


## 2026-09-09：额度重置确认与已打开菜单的动态环境

- 重置 RPC 返回成功与重置真正完成是两个状态。比较请求前后服务端 `latest*ResetHistory.usedAt`；旧历史不能确认本次请求。健康超时保留 idempotencyKey；已受理却未查到新历史，不再提交新请求，只刷新状态。
- 额度满值只能基于服务端确认投影。记录额度请求开始时可见的完成记录，旧的在途额度查询不能清除稍后完成的重置投影。
- `showComposerPopover` 不能在调用时捕获固定底色和 MediaQuery。原生大字号/主题检查复现白菜单留在深色页面；修复后路由内订阅主题与 MediaQuery，保留源字体但重新计算颜色和位置。
- Scaffold 可能已为 composer 消费 keyboard viewInsets，原上下文底部会是 0；浮层定位同时取 route 的完整 inset 和本地覆盖值，不能只读 composer 上下文。
- 模态标题的关闭按钮和操作行不要让 Material 默认触摸占位撑高整个布局。官方视觉 24/32px 控件采用显式 shrinkWrap，窄屏仍保留滚动和可达按钮。


### 统计页的共享状态、时间范围与原生测试

新路由 initState 不能直接调用会同步通知底层页面的共享控制器刷新；先用完整 More 进入/返回回归复现 build 期间 setState，再将首次读移到首帧后。应用累计 all 与范围 7d/30d 分开，应用/套餐各自保存范围，避免切页时串用。

原生测试不要在经过平台异步回调的假 RPC handler 中执行 Flutter 测试断言：先保存调用参数，再在测试主流程 await 完成后检查。语言/字号变化后不要持有先前 ScrollPosition，重新查当前滚动区域。普通 Flutter 单元测试中的偏好持久化 await 使用 tester.runAsync，避免停在假时钟内。
