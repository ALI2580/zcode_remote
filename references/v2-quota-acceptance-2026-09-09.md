# 额度与团队来源阶段验收（2026-09-09）

本阶段为 0.1.0+7，继续全局 A–F Goal。完成当前上下文/额度显示和手动重置闭环；完整使用统计页面、自动机会刷新/历史已读联动及其提示动效仍待实现，不据此将 C2 或全局 Goal 标为完成。

## 官方依据

- 固定基线主包 `index-nOVzQNKW.js`：`fT/pT/xB/A2e/k2e` 解析个人/团队来源，旧 `:0` 或项目键须解析为实际组织/项目后查询。
- `NZe/MZe/DZe/OZe/AZe/jZe`：有效上下文必须 used/total 都大于零；总容量采用本地化紧凑数字，百分比最多一位小数；来源 chars 的相对占比仅铺在已使用容量内。无分项数据仍显示总占用条，缓存命中率门槛为 0.78。
- `fZe/cZe/dZe`：5 小时、周、工具以及独立 MCP；日期随语言变化，三张主卡时 MCP 全宽显示。数值缺失不补 0/100，无有效日期不生成 1970 年提示。
- `rI/eI/EXe/DXe/OXe/GF`：重置状态按来源隔离，状态读缓存 1,500ms；手动请求带唯一 `idempotencyKey` 和 `FIVE_HOUR`/`WEEK`，0/250/750/1500ms 查询确认。旧历史不确认本次请求；失败保留请求标识，服务端已受理但未确认时只查询状态。
- `sZe/mI` 与 `catalogTree-P8S5ypDb.js` 的 `nT/tT`：480px 模态窗口，窄屏视口减 32px；3 列额度卡、手机单列；次数、过期倒计时、忙碌/完成状态。背景黑 60%、4px 模糊，标题/操作行不受平台默认 48px 触摸占位撑高。

## 本阶段实现和证据

- `entitlement.dart` / `ComposerUsage`：实际组织和项目解析、源切换清旧显示、60 秒缓存、断线清旧账户。旧格式、订阅续期更换产品 ID、解析失败和迟到切换均有回归。
- `PlanResets`：同一 transport 共用状态/进行中请求；不同设备和项目分离。重置次数筛除过期/非法日期；双击去重、超时同标识、已受理未确认不重复消耗。只有新服务端历史能触发余额投影，旧的额度查询不能提前清掉投影。
- `plan_reset_dialog_test.dart`：可用/满额/过期、切换来源、双击、未确认状态和五形态×两主题×中英文×140% 字号布局检查。
- 原生截图发现菜单打开后切换主题仍保持旧白底；新增回归复现后修正 `showComposerPopover` 的颜色、字体、锚点与安全区域读取。覆盖 Scaffold 消费 IME inset 的场景。修复前日志 `v2-reset-theme-before.log`，修复后 `v2-reset-theme-after.log`。
- `integration_test/usage_controls_test.dart`：独立 `.qa` 包在指定手机与平板运行；真实 Flutter 原生控件、触屏点击、合成额度服务，检查一次手动请求及确认后余额；未连接真实远程。
- `tooling/remote_feature_probe.dart` 的统计只读模式：ROG 实际有效来源为 BigModel，5 小时重置次数 0、周重置次数 1；重置状态、Coding Plan 统计及应用统计 RPC 均可用。报告只保留字段形状、聚合数字，不保存身份或凭据。
- 初次探针访问了未连接的 Z.ai 来源，错误为 `zai_coding_plan_api_key_required`；加入有效 entitlement 校验后读到正确 BigModel 数据。这是探针筛选问题，不是协议方法缺失。完整探针成功证据：`build/artifacts/official-usage-statistics-probe-ROG-STRIX.json` 与 `v2-statistics-probe-ROG.log`。

## 实际对照范围

- 官方 ROG 同任务、浅色、100%：`official-ROG-light-usage-1723.png`、`official-ROG-quota-reset-dialog.png`。
- 官方“更多”跳转个人套餐，包含剩余额度、活跃度、Token 活动、近 7/30 日模型/工具消耗及系统健康度；应用用量使用另一套本地统计。截图 `official-ROG-usage-page-1723.png` 与 `official-ROG-app-usage-page-1723.png`。
- 官方 DOM viewport 为 1723×1195，截图后端输出裁至 1664×1195，右边缘被裁。弹窗完整可见，可比较其自身尺寸和结构；不能作为全页面等宽像素一致证据。
- Native QA 截图以 `phone-usage-*` / `tablet-usage-*` 保存；属于真实 Flutter 原生渲染和合成数据的行为回归。真实产品同任务对照及构建信息在本文件下方继续补齐。

## 仍需继续

1. C2 的“更多”完整使用统计页，以及自动机会查询、历史已读和完成提示联动；相应维护 RPC/状态逻辑已实现，尚未接入自动运行，真实只读验收未调用授予、消耗或已读写入。
2. 真实团队/Start 数据的最终 UI 对照，其他形态/主辅面板组合；没有条件的项目继续保持待验证。
3. 其余 A/B/D/E/F 必需范围，尤其中文软键盘、完整工作面板/设置、离线语音和更新安装。


## 已交付构建与最终验证

- APK：`build/artifacts/ZcodeRemote-v2-quota-dev.apk`，0.1.0+7，ARM64 / x86_64；`.dev` 包名及兼容签名。
- APK SHA-256：`9706a27ef6df893441ab30d6020e93817f5ddb446bb941b6cd14e12c2cff7ecb`；源码状态：`c4b1f0a6c26dd4dd67e7f1a9766d1131f142f207df931f68453797755b04d97a`（169 文件、未提交工作区）；源码 ZIP SHA-256：`f0de2aea722d422ec74b1136ef0f86eee1dc412f0f533c9f455d3cc0aa714548`。
- 两台指定 MuMu 覆盖安装成功并启动；从设备读回安装 APK 验证与交付文件字节完全一致。记录 `build/visual-audit/recovery-qa/quota-installed-apks.json`。
- 最终完整 Flutter 测试 **339 项通过**；静态检查零告警；独立纯 Dart 协议 smoke、33 张现有页面渲染及双 ABI 构建通过。日志 `v2-reset-all-tests.log`、`v2-reset-analyze.log`、`v2-reset-protocol-smoke.log`、`v2-reset-build.log`、`v2-reset-signature.log`。
- 两台独立 QA 均通过普通浅色中文弹窗、深色英文 140% 字号、打开中主题变化、可达按钮、一次提交和服务端确认后余额。最新原生日志 `v2-reset-native-phone.log` / `v2-reset-native-tablet.log`；截图 `phone-usage-*` / `tablet-usage-*`，包含 `reset-large`。
- 真实 ROG 同任务读到上下文 140,794 / 1,000,000、14.1%、缓存 93.8%，套餐 5h 100% / 周 94% / 工具 95%，MCP 100% 与 9 月 10 日，周重置机会 1 次，与官方记录一致。已打开真实重置弹窗，只读取并关闭，未点击消耗按钮。
- 真实产品图 `tablet-ROG-v7-usage.png` / `tablet-ROG-v7-reset-dialog.png`；ALI 当前任务上下文和缓存图 `phone-ALI-v7-usage.png`。比较范围和差距写入 `quota-live-comparison.json`。没有宣称整页视觉一致。

本阶段不改变剩余必需项目。特别是“更多”完整页面和自动维护联动仍明确列为待实现，继续推进。
