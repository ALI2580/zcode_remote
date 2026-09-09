# 额度自动维护阶段验收（2026-09-09）

阶段版本为 0.1.0+9，已构建、覆盖安装并冻结交付。全局 A–F Goal 保持进行中。

## 官方依据与实现

- 固定基线 `index-nOVzQNKW.js` 的 `hXe/gXe/tXe`：挂载且可见的额度界面共用轮询；首次可见及回到前台立即检查，间隔 5 分钟，最后一个界面关闭后取消。`PlanResets` 按 transport 及供应商/组织/项目隔离，`ComposerUsage` 负责来源变更与 Android 生命周期。
- `rI/I/_Xe`：先读状态，正在重置或刚发现完成历史时跳过授予。机会请求沿用已实现的 5/10 分钟退避和幂等标识；取得机会后立即重读状态。
- `EXe/TXe/JF`：只对最新未读历史建立自动完成；手动请求仍须相对发起前历史变化才确认。新完成刷新额度、按历史标识去重已读，重连清空账户数据并抑制同一历史重复播放。既有读取早于完成时，等待旧读取结束后再查询新额度。
- `AXe/jXe/QXe/oI`：自动完成先显示 1 秒进度，再显示完成文字至 2.6 秒；10 个碎片、420–490ms 动效按官方参数实现，同一来源/类型/历史只播放一次。尊重系统减少动画设置，状态使用语义 live region。手动完成继续由重置弹窗展示。
- `RuntimeAudit`：本地 `.dev` / `.qa` 启动参数 `quotaReadOnlyAudit=true` 仅用于真实桌面只读验收，界面显示“额度只读验收”角标。该模式保留查询，阻止授予、消耗及已读三个额度写 RPC；不修改远程配置或持久化设备设置。普通启动默认启用完整自动行为。自动流程的写操作全部在合成服务验证。

## 已完成验证

- 完整 Flutter 测试 363 项通过，静态检查零问题。日志 `build/artifacts/v2-maintenance-all-tests.log`、`v2-maintenance-analyze.log`。
- 新回归覆盖多观察者轮询去重、5 分钟周期、最后关闭与迟到返回、前后台恢复、来源切换、重连、外部最新历史、单次已读、每个视图的新额度刷新、旧查询跨越重置完成、只读模式，以及两处同时展示时仅播放一次动效。
- 字体化实际 Flutter 渲染保存在 `build/v2-maintenance-preview`；包含五形态、深浅主题、中英文及 140% 字号。
- 双 MuMu 原生额度测试通过：从无机会自动获得 1 次周额度，点击两次只提交一次；服务端确认后读取新额度；模拟另一处发生 5 小时重置，展示进度和完成并标记已读一次。全过程只连接合成服务。日志 `v2-maintenance-native-phone.log` / `v2-maintenance-native-tablet.log`；12 张图 `build/visual-audit/recovery-qa/{phone,tablet}-maintenance-*.png`。
- 本次 MuMu 实例核实：手机名称“竖屏手机”、ADB 16448、1440×3200/density 522/方向 0；平板名称“平板横屏”、ADB 16480、2400×3392/density 315/方向 1。测试前产品安装版本均为 0.1.0+8。

## 剩余验证与范围

产品 More 导航及统计操作在双端原生 QA 均通过（`v2-maintenance-statistics-phone.log` / `v2-maintenance-statistics-tablet.log`）。真实 ROG 冷启动后的 More 页面读到 40.1 亿累计、8.2 亿近 7 日 Tokens；ALI 的原任务、qwen3.8-flash 和 8.9% 上下文恢复。真实 ROG 保持 100%/94%/95%、MCP 100%、周重置机会 1 次；只读弹窗的重置控件不可点击。记录 `maintenance-live-comparison.json` 及 `*-v9-*.png`。

多次 UIAutomator 查询在弹窗/页面返回后、也包括页面静止时会出现空辅助功能树；一次弹窗关闭后的后续点击未进入目标页，重启后直接进入 More 成功。该问题仍需最小复现并修正，不将实际完整导航/辅助功能验收标为通过。页面和原任务冷恢复有效，不能据此推断辅助功能正常。

真实桌面没有人为制造重置或授予，因此自动状态截图属于合成回归，不能宣称真实官方完成动效视觉一致。

C2 的 Start/团队全部真实数据组合与完整用量设置容器仍受其他阶段约束；F4 返回页面后的辅助功能树问题继续排查。其余 A/B/D/E/F 必需范围未缩减。

## 交付构建

- APK：`build/artifacts/ZcodeRemote-v2-maintenance-dev.apk`，124,853,384 字节；版本 0.1.0+9，`.dev` 包名；包含 ARM64 和 x86_64 Flutter 引擎。
- APK SHA-256：`cdbe77d204bf0a17f418ce9c278102e4ec316d0f5207414c1137811abbdd754b`。
- 签名证书 SHA-256：`b020bef5c510b8ce9ba783349f4170d178fc279411ca4042287b1c91151a4857`，沿用原开发包签名。双 MuMu 读回已安装 base.apk 与交付字节一致，见 `maintenance-installed-apks.json`。
- 180 文件源码快照：`ZcodeRemote-v2-maintenance-source.zip`，SHA-256 `fd354425243f0b546e2b050487026a7633b5ee6a6372db59cd0afcd557166977`；源码状态 `806b7d141ec523b48392eb27b98051ad87e17b1b7a5c20b59fe741fe7ee216b5`，未提交工作区，基准提交 `450164e081549c083ef2bec6c6f6e0635e08513f`。
- 完整测试 363 通过、analyze 零问题、纯 Dart smoke 成功；日志均在 `build/artifacts/v2-maintenance-*`。双端原生额度与统计分别通过。
- 两台真实产品均使用 `quotaReadOnlyAudit=true` 启动；后续实际只读验收仍须以该参数冷启动，普通启动会按官方行为自动维护额度机会与已读状态。
