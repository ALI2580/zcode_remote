# 使用统计阶段验收（2026-09-09）

本阶段交付版本为 `0.1.0+8`，继续全局 A–F Goal。新增 Composer“更多”进入使用统计，以及应用/套餐统计的数据、缓存、图表和错误状态。355 项测试、静态分析、双端原生、构建覆盖安装和真实 ROG 同源数值验证均已完成。全量设置容器与自动重置仍未完成，本阶段不代表完整 C2 或全局验收。

## 固定官方依据

- `index-nOVzQNKW.js` 的 `Pqt/fJt/k5`：应用使用 `getAppUsageSnapshot`，累计摘要/热力图单独请求 `range: all`，图表请求 `7d` 或 `30d`；时区来自本地 IANA 标识。不能将范围摘要冒充累计统计。
- `Fqt/SJt`：套餐 `getCodingPlanUsageSnapshot` 参数包括 `preferredProviderId`、可选组织/项目、range、两个 null 自定义日期、timeZone。60 秒缓存按来源和范围隔离，失败清除对应统计，不改选其他账户。
- `wJt/EJt/TJt/DJt/jJt`：剩余额度优先 entitlement、后备同来源统计 quota；MCP 始终取独立 entitlement。累计活动、52 周热力图、7/30 天模型/工具和健康度；健康度固定 7 天。`OJt/kJt` 仅在实际积分数据存在时显示积分选项/摘要。
- `Xqt/zqt/eJt/tJt`：输入服务可返回 53 周，但页面归一化最近 **52** 个周日起始周。每日、周合计、累计三种视图；只有返回有效日期后，范围内缺席日期才按官方补无活动单元。缺失数值不填百分比。
- `AppUsageDailyModelTrendChart-BPiqhchv.js`：趋势前 6 个模型；`AppUsageModelUsagePieChart-BPS_rw4S.js`：超过 6 个模型时前 5 个加“其他”。不同统计源的累计数值不能混用。
- `CodingPlanUsageBarChart-KNbVUe4i.js` / `CodingPlanUsageLineChart-XsKXfvBp.js`：256 高图表、24 水平留白、虚线网格、无 Y 轴标签、单调曲线；模型最多同时 3 个、前 8 个图例入口、再次选择第 4 个替换最早选项且不能取消全部。带积分数据的模型图支持缓存输入/非缓存输入/输出分段。

## 实现

- `lib/protocol/usage_statistics.dart`：纯 Dart 类型解析，校验 provider/range/timeZone/source；非有限值和缺字段保持缺失，图例和点击详情不编造零。应用模型聚合、套餐序列、热力图日期和归一化独立于 Flutter。
- `lib/state/usage_statistics.dart`：页面/transport 拥有的缓存；key 包含 provider/org/project/range/IANA 时区；去重、60 秒新鲜度、重连清缓存/丢弃迟到响应。应用更新失败只保留同范围缓存，套餐更新失败清空当前快照；不在错误文案中输出原始服务端错误或凭据。
- Android `zcode_remote/platform` 提供 `TimeZone.getDefault().id`，读取失败显示重试状态，不使用 CST 等缩写猜测时区。
- `lib/ui/usage/`：两类统计、累计摘要、热力图模式、图表系列/范围选择、图表触屏明细、健康度、模型环图、积分/趋势、独立 MCP 卡片与复用重置对话框。
- `ContextUsageButton` 的“更多”先关闭弹层再打开完整页面；空/失败额度继续保留刷新操作。首次共享额度读取移到首帧之后，避免新路由构建时通知底层 Composer。

## 回归与发现

- 状态回归覆盖累计/范围分离、切换团队立即清旧显示、迟到个人响应、两个 transport 同 ID、重连同 provider、并发刷新、失败缓存口径、时区读取失败、非法数值、热力图和模型聚合。
- 实际 Channel 编码检查统计 RPC 参数；不附带 workspace/session，也不猜测其他接口字段。
- 窄屏 140% 首轮发现更新时间行右侧溢出，改为受约束可换行文本。图表明细不会被额度定时刷新抹掉。
- 原生 More 导航复现共享状态在 build 期间更新，日志 `v2-statistics-navigation-before.log` / `v2-statistics-native-phone-second.log`；改为首帧后读取并新增完整进入/返回控件回归。
- 原生测试曾将断言放在异步假 RPC 回调内，引发测试守卫异常并被显示为读取失败；将检查移到请求完成后。语言变化后旧 ScrollPosition 失效，测试改为重新定位当前滚动区域。这两项是测试用例时序问题，未改弱产品错误/隔离规则。
- 原生 `.qa` 假服务已在最终同代码的手机、平板均通过。真实远端仍只读，未运行授予、消耗或历史已读写操作。

## 剩余

1. 自动重置机会、历史已读、完成提示联动仍属于 C2 后续工作；当前维护 RPC 仍未自动触发。
2. 完整远程设置容器和账户入口（E1/E2）还需将该页面纳入；当前从 Composer“更多”可达。
3. 页面容器与官方设置侧栏尚未合并，目前内容宽 848，而官方 832；重置次数徽章到期展示继续在 C2 校准。不能宣称整页像素对齐。
4. 其余 A/B/D/E/F、ColorOS 真机和中文软键盘验证仍保持原清单状态。


## 最终验证与安装

- `flutter test`：**355 项通过**，日志 `build/artifacts/v2-statistics-all-tests.log`；`flutter analyze` 无问题，日志 `v2-statistics-analyze.log`；纯 Dart 协议 smoke 通过，日志 `v2-statistics-protocol-smoke.log`。
- 实际 Flutter 渲染 `build/v2-statistics-preview-final/`：120 张统计页（五形态×中英文×两主题×100/140%×顶部/底部/应用）及 33 张原有 V2 界面图。
- 两台 MuMu 独立 `.qa` 最终测试通过，日志 `v2-statistics-native-phone-final.log`、`v2-statistics-native-tablet-final.log`；包含真实原生 IANA 时区、More 导航、套餐 30 天后应用仍独立 7 天、图表点击明细、累计请求、深色/140% 和返回。8 张 `phone-statistics-*` / `tablet-statistics-*` 截图位于 `build/visual-audit/recovery-qa/`。
- 时间范围共享缺陷先由 `v2-statistics-range-before.log` 复现，再由 `v2-statistics-range-after.log`、完整测试和原生检查验证；已拆分 `_appRange` / `_codingRange`。
- 2026-09-09 09:35 两台覆盖安装最终同一 APK，实际 base.apk 字节 SHA-256 均与交付文件相同；记录 `statistics-installed-apks.json`。手机为 ALI，平板为 ROG-STRIX，独占分配保持。

## 真实 ROG 对照与限制

- 官方之前保存的同 ROG 数据：`official-ROG-usage-page-1723.png` / `official-ROG-app-usage-page-1723.png`；本次产品为 `tablet-ROG-v8-statistics-plan.png` / `tablet-ROG-v8-statistics-application.png`。
- 套餐：累计 **40.1 亿**、单日峰值 **3.8 亿**、使用时长 **3 天 10 小时 35 分钟**、连续 **12/51 天**；近 7 天合计 **8.2 亿**（GLM-5.3 **2.8 亿**、Flash **5.4 亿**）。额度 **100/94/95/MCP100%**，日期与独立服务源一致。
- 应用：累计 **33.6 亿**、单日峰值 **6.3 亿**、最长会话 **5 小时 14 分钟**、连续 **13/13 天**；近 7 天模型总量 **14.9 亿**、近 30 天 **33.6 亿**。两种统计口径确实不同。
- 实际从应用 30 天切回套餐仍为套餐 7 天、合计 8.2 亿，截图 `tablet-ROG-v8-statistics-range-isolation.png`。
- 返回后对话正文区域 5,830,160 像素中变化 **0**。UIAutomator 此时再次返回空语义树，与第 7 阶段已记录现象一致；实际界面恢复、原生控件返回测试通过，辅助功能重注册仍需独立排查，不据此宣称 F4 通过。随后重启平板客户端恢复正常检查状态，未停止远程任务。
- `statistics-live-comparison.json` 保存范围、数据、返回像素比较和限制。官方截图时间较早，刷新时间不同；当前设置容器宽度/侧栏尚未完成，只验收同源聚合与功能结构，未宣称整页像素一致。

## 冻结交付

- APK：`build/artifacts/ZcodeRemote-v2-statistics-dev.apk`，`0.1.0+8`，`com.zcoderemote.zcode_remote.dev`，124,827,424 字节，Flutter 引擎包含 ARM64 与 x86_64。
- APK SHA-256：`22bfcb9cca03cd6a87e2a16d428e2c419606839937816c49624e807163068f7b`。
- 兼容签名 SHA-256：`b020bef5c510b8ce9ba783349f4170d178fc279411ca4042287b1c91151a4857`，构建/验签日志 `v2-statistics-build.log` / `v2-statistics-signature.log`。
- 178 个源码文件冻结于 `ZcodeRemote-v2-statistics-source.zip`，源码 ZIP SHA-256：`cd67829025dd74c8149c88e393929eeaf573534e72a9de8ae446160ac0487696`。
- 代码状态 SHA-256：`84a4b57d79e5040140b0edd9433d3d1abd335b8cd814b6fc1a2c15eee82549ee`；基准提交 `450164e081549c083ef2bec6c6f6e0635e08513f` 加已有未提交改动。逐文件记录位于 `ZcodeRemote-v2-statistics-manifest.json`，未创建提交或推送。
