# Flutter / Android 系统集成

最新路线：纯 Flutter UI 和 Dart 业务逻辑；Android 的通知、Keystore 等系统 API 通过少量 Kotlin + MethodChannel 接入，不使用 WebView 主界面。目标系统包含 ColorOS 16 / Android 16。

2026-09-08 更新：He 已在关联会话确认 ColorOS 16 实际上岛效果可行。V2 主界面现已接入，入口为侧栏底部「设置 → 通知与上岛」，首次无设备时可从设备目录进入设置。最新进度见 [V2 实施记录](v2-implementation.md)。

## 预测性返回

- 主清单启用 `android:enableOnBackInvokedCallback="true"`。
- 主题显式使用 `PredictiveBackPageTransitionsBuilder`，当前页面经 `MaterialPageRoute` 导航。
- 不使用 `WillPopScope`；新增面板/嵌套导航时，使用框架路由或预先确定 `canPop` 的 `PopScope` / `NavigatorPopHandler`，禁止在手势结束后临时决定路由归属。
- `test/ui/predictive_back_test.dart` 直接发送 Flutter 的 Android backgesture 平台消息，验证页面随进度移动、取消后保留当前页、确认后回到前页。
- 返回页面释放页面订阅，但设备连接和全局任务索引属于 `AppSessions`，不会随路由 pop 被销毁。
- 监控任务时，根页面的系统返回将任务移到后台，保留持有 relay 的 Flutter 引擎；不能只留下没有 Dart 监听的原生通知。移除最近任务或真正结束 Activity 时清理服务，避免静止的进度。

依据：[Flutter 预测性返回](https://docs.flutter.dev/platform-integration/android/predictive-back)。

## 任务通知与“上岛”

- 首页「任务通知与上岛设置」显式启用；Android 13+ 等待真实通知权限结果后才启用。
- `TaskNotificationController` 汇总所有已打开工作区的 sessions-index。作用域为 deviceId + workspaceKey + sessionId；A 完成不会停止 B 的运行通知。
- 常驻任务通知使用 `NotificationCompat.ProgressStyle`、`setRequestPromotedOngoing(true)`、低重要性渠道和标准布局；清单声明 `POST_PROMOTED_NOTIFICATIONS`。
- 没有可计算进度时使用不确定进度，不伪造百分比。等待确认、完成、失败和停止使用不同语义。
- 完成/待处理普通通知与运行通知携带不含 sid/hash 的 `TaskTarget`。冷启动先保留点击目标，设备数据加载完再恢复工作区与任务；设备已移除时显示明确提示。
- 运行通知的「停止显示」只关闭客户端监控展示，不发送停止桌面任务的 RPC。用户取消后不重发。
- `dataSync` 前台服务只在应用可见时新建，已有服务可在后台更新；`START_NOT_STICKY` 避免进程重启后展示没有监听源的旧状态；`onTimeout` 停止服务和通知。
- 不支持 Live Updates 的系统使用普通任务通知。ColorOS 16 是否实际上岛由系统权限、渠道与厂商条件决定，需要真机验收。

依据：[Android Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update)。此能力跟踪用户主动开启监控的正在执行任务，不用于给普通聊天消息常驻上岛。

## 多设备和凭据

- `DeviceStore` 使用本地 UUID；旧 sid 主键在加载时迁移，通知 payload 不使用配对凭据做标识。
- Android URL 经 Keystore AES-256-GCM 保存。运行时持有解密后的 URL；加密失败不提交记录、不回退明文。重导入同 origin/mid 的新链接保留本地身份、替换凭据。
- `DeviceSession` 共用正在进行的连接操作；失败或连接中释放时关闭临时客户端；每工作区缓存一个 bridge。
- `WorkspaceMonitor` 的订阅随 AppSessions 保留，重连由原协议订阅恢复逻辑处理；监控失败会重试。
- 草稿和导航由 `RecoveryJournal` 加密持久化，恢复文本、引用、附件状态、配置草稿、任务位置和面板；深历史恢复按消息 ID 读取必要页并恢复可见偏移，同时保存日志代次。后台与提交前会等待保存；写入失败保留上次有效快照并显示重试入口，较新 schema 不被旧版覆盖。
- 原生选择器将文件复制到私有缓存并校验 SHA-256；重启后的预览从缓存读取，不依赖原内容 URI 的临时权限。发送中断保留不确定状态，恢复不自动发送或创建会话；显式重试复用已保存的暂存会话，文件不可用时阻止静默提交。

## 附件与恢复原生 QA（2026-09-09）

`integration_test/attachment_recovery_test.dart` 使用独立 `.qa` 包、真实 DocumentsUI / 私有文件 / Keystore / SharedPreferences；远端为合成传输。测试启动先断言包名，不能接触产品 `.dev` 的设备或草稿。

```powershell
$env:ZCODE_ANDROID_QA='true'
flutter test integration_test/attachment_recovery_test.dart --no-pub --no-uninstall -d <指定目标> --dart-define=RECOVERY_QA_PHASE=seed
# 系统选择器中仅选择 integration_test/fixtures/recovery-fixture.txt 对应的测试文件。
# seed 完成后关闭进程，再以 verify 模式重新启动并读取同一缓存。
flutter test integration_test/attachment_recovery_test.dart --no-pub --no-uninstall -d <指定目标> --dart-define=RECOVERY_QA_PHASE=verify
```

- 必须使用 `--no-uninstall`：当前 Flutter 集成测试默认结束后卸载应用，会删除待验证的持久数据。产品构建移除本进程中的 QA 环境变量后回到 `.dev`。
- 测试运行期间用 ADB 原生截图和点击操作选择器；不运行 uiautomator，以免它临时开启无障碍导致测试退出时留下 SemanticsHandle。
- 手机和平板原生 seed / verify 均通过；日志 `build/artifacts/v2-recovery-{native,tablet}-{seed,verify}.log`，预览 `build/visual-audit/recovery-qa/{phone,tablet}-restored-preview.png`。覆盖失败后保留、进程关闭后恢复、再次预览原文件、无自动提交，以及显式重试一次。平板使用最终恢复竞态修复后的代码。
- 中文键盘模式仍待验证：Windows 窗口工具两次无法展开最小化的 MuMu 手机窗口，已请求协助；不能将超时计为通过。合成编辑器回归仍覆盖 composing 和 Android 换行规则。

## 长历史原生 QA（2026-09-09）

`integration_test/reading_recovery_test.dart` 也仅允许 `.qa` 包。使用 `READING_QA_PHASE=seed/verify`，仍需 `ZCODE_ANDROID_QA=true` 和 `--no-uninstall`。seed 在变高消息上真实拖动并保存；verify 从只含尾部的合成快照启动，通过 200 行分页恢复目标，再检查行 ID 与实际可见偏移。

- 手机恢复第 450 行、偏移 -84dp；平板恢复第 450 行、偏移 -104dp，均只读取两页，无发送命令。
- 日志 `build/artifacts/v2-history-{native,tablet}-{seed,verify}.log`；原生截图 `build/visual-audit/recovery-qa/{phone,tablet}-reading-{seed,verify}.png`。
- 排除顶栏 seed/verify 标记后，两端各自恢复前后的正文及 Composer 像素完全相同：`reading-pixel-comparison.json`。此为合成数据原生恢复对照，不是官方视觉对齐证据。
- 验证期间发现并修复拖动后锚点在布局前记录、随后被拉回的问题；文字组件保持原样，真实拖动位移已纳入断言。

## 开发与验收

```powershell
flutter analyze
flutter test
flutter build apk --debug
flutter test integration_test/android_system_test.dart -d emulator-5554
```

- 调试包名 `com.zcoderemote.zcode_remote.dev`，名称 `ZcodeRemote Dev`；正式包名保持不变。
- 本轮手机测试包：`build/artifacts/ZcodeRemote-native-dev.apk`，包含 ARM64，使用 `lib/main.dart` 产品入口（不是集成测试入口）。首页进入「任务通知与上岛设置」开启监控，再打开设备与工作区。
- Android 集成测试只用合成数据，验证 Keystore、已有通知权限下的服务和通知显示，然后清理测试通知；不请求真实桌面连接、不执行任务命令。
- 当前模拟器为 Android API 32，适合验证旧系统回退，不能替代 ColorOS 16 真机上岛和系统手势动画验收。
- 最终静态检查零问题，162 项 Flutter 测试通过，Android APK 编译通过。
- Android API 32 模拟器集成测试通过：真实 Keystore 加解密/随机 IV、前台任务通知注册显示、根页面返回后台后引擎保留与通知继续更新。测试通知已清理；没有使用真实桌面凭据。
- ColorOS 16 / Android 16 的实际上岛效果已由 He 在关联会话确认；预测返回手势动画与新 V2 页面组合仍需真机进一步验收，API 32 回退测试不替代该项。

## 仍在重建的范围

完整官方 UI / 设置、五形态视觉校准、右侧工作面板、离线语音与更新安装链路仍需继续迁移。旧 Web 验证目录保留为研究参考，不参与产品运行。当前系统能力接入不代表所有 1:1 UI 已完成。


## 0.1.0+7：额度控件原生 QA 与产品安装

`integration_test/usage_controls_test.dart` 在独立 `.qa` 包分别通过手机 16448 与平板 16480。直接使用完整 composer 浮层与重置弹窗，合成传输未建立真实远控；普通中文浅色、深色英文 140% 和打开中主题变化均有截图。双击仅记录一次 `useCodingPlanReset`，新历史确认后周额度回满；未产生 conversation command 或消息。

最终产品 `.dev` APK 与阶段 manifest 同源，versionCode 7，ARM64/x86_64。两台覆盖安装后读回 base APK 哈希均为 `9706a27ef6df893441ab30d6020e93817f5ddb446bb941b6cd14e12c2cff7ecb`；既有 ALI/ROG 分配和任务恢复保留。真实 ROG 的额度与重置弹窗只读查看，未执行消耗。详见 `v2-quota-acceptance-2026-09-09.md`。


## 0.1.0+8 使用统计原生验证

最终 `.qa` 在手机 127.0.0.1:16448、平板 127.0.0.1:16480 均通过：IANA 时区、Composer 更多、30 天套餐、7 天应用/累计分离、图表触屏明细、深色 140% 和返回。最终 `.dev`8 两台实际 base.apk 均匹配 `22bfcb9cca03cd6a87e2a16d428e2c419606839937816c49624e807163068f7b`，安装于 2026-09-09 09:35。完整证据见 v2-statistics-acceptance-2026-09-09.md。

真实 ROG 返回统计页之前的正文完全相同（比较区域 5,830,160 像素差异 0）；UIAutomator 返回空语义树的既有现象仍会出现，待继续排查 Android 辅助功能重注册，不能代替 F4 验收。真实远端未发送消息、使用重置、授予机会或修改已读状态。

## 0.1.0+9 自动额度维护原生验证

双端 `.qa` 通过自动授予、重复点击只消耗一次、外部完成先处理再完成、一次已读和 More 全流程；12 张额度图与原生测试日志见 v2-maintenance-acceptance-2026-09-09.md。`.dev`9 均覆盖安装，实际 base.apk SHA-256 为 `cdbe77d204bf0a17f418ce9c278102e4ec316d0f5207414c1137811abbdd754b`。

真实桌面验收冷启动必须带 `--ez quotaReadOnlyAudit true`，角标可见，保留读取且禁用额度授予/消耗/已读。普通启动启用完整自动维护。实际重复 UIAutomator 查询在弹窗/导航之后及页面静止时仍可得到空树；记录了关闭弹窗后的点击未进入 More、冷重启后直接 More 成功的区别，F4 尚未通过。

## 0.1.0+10 当前状态

上述辅助功能缺陷已通过独立 `.qa` 的可选富文本链接案例定位，产品正文改为 SelectionArea/Text.rich。双端合成页面重复查询正常；真实 ROG +10 进入用量页返回后为 85/85 个语义标签，不再依赖冷重启恢复。侧栏连续长按改为抬起后打开菜单，辅助功能 action 保留。

双端原生任务管理（含确认、失败、取消与深色英文 140% 菜单）通过，368 项完整测试、零静态问题、153 张渲染；两台 `.dev`10 实际安装 SHA-256 均为 `02bfd62a64cee65bf9e64af660da3515973d5847a6086090f19e775346468813`，183 文件源码已归档。其余 F4 系统组合和 ColorOS 真机验证继续保持待完成。

按要求暂时停止功能开发，接续使用 [详细进度与测试手册](D:/WorkSpace/ZcodeRemote/references/v2-progress-todolist-2026-09-09.md)。额度 audit 仅限制三个额度写 RPC，并非全应用写入保护。
