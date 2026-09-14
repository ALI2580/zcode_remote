# 三专项联合审计：第二轮起点

审计日期：2026-09-15。对象为性能、代码结构、手机竖屏 UI 三专项的集成源码。审计包含源码、已有报告/原始日志、当前静态检查/完整测试、针对性反例、只读设备列表及一张历史设置截图检查。本轮不实施产品修复、不构建/安装 APK、不操作真实远端。

## 1. 总判定

三个专项均有真实实现，移动端已集成，不能再按“尚未开始”的旧状态接续。但“只剩实体机/真人条件”的结论不成立：当前还存在本地可复现的实现与验收工具缺陷。

| 专项 | 已确认成果 | 本次判定 |
| --- | --- | --- |
| 性能 | rowId 索引、viewport 反向/索引映射、singleTurn 提升、代码格式化 LRU 均在当前源码；确定性计数仍生效 | 算法成果保留；设备统计口径需修复，缓存字节/对象规模边界未闭合，不能沿用全部性能门通过 |
| 结构 | settings 页面/组件、turn_projection/change_summary、conversation_state 已拆出；协议 smoke 可独立运行 | 有效的渐进拆分；结构守护在本机空跑，部分分层仍为技术债，不等于 S0–S5 全范围完成 |
| 手机 UI | mobile 组件、模型/模式底部面板、设置分类/详情、顶栏分层、终端最大化已接入当前提交 | 主要框架已形成；真实 ComposerBar 小屏、动态状态、失败重试与触控目标仍有遗漏 |

## 2. 当前源码与本轮验证

- HEAD：`76d2bd4`（完整值见 `build/optimization-audit-20260915/head.txt`），版本 `0.1.0+12`，审计开始时工作区干净。
- 交付前检测到其他任务新增 `test/ui/mobile/task_menu_gating_test.dart` 并更新两份 mobile 文档；未覆盖这些改动。本轮1020测试结果对应它们出现前的快照，未将新增测试纳入已通过数量。交付时生产源码无新增diff，A01–A09涉及的实现未变化；末态见 `status-at-delivery.txt`。
- 当前物理行数：settings_center_page 4,311；chat_page 2,051；conversation 1,885；conversation_state 398；code_renderer 1,101。行数只说明规模，不单独证明耦合改善。
- 性能核心 conversation_state SHA1 `74a2abbd5c8fc01e1f23259f6e6bae64e5f59b15`、code_renderer `833f0f99535b85e04a488fc43ca3ca7388ac3c43` 与旧冻结一致；chat_page 为移动集成后的 `a464985dd98c681721135c0a1efc19b4d7a4173f`。settings_center_page 当前 `d8b1ae181c8edb5304437b4fa9e8a0476b64a79b`，不能继续使用旧报告的 `b49e8124…` 作为当前源码身份。

| 验证 | 本轮真实结果 | 证据（均相对仓库） |
| --- | --- | --- |
| `flutter analyze --no-pub` | exit 0，No issues found | `build/optimization-audit-20260915/analyze.log` |
| `flutter test --no-pub --reporter expanded` | exit 0，1020 通过、1 跳过 | 同目录 `full-tests.log` |
| `dart run tooling/protocol_smoke.dart` | passed | 同目录 `protocol-smoke.log` |
| 当前算法基准，完整 size 顺序，3 进程×7测量轮 | 5k 行每帧 median 309/423/300μs；20k 为 224/219/273μs；每帧600 deltas | 同目录 `bench-conversation.log`、`bench-conversation-2.log`、`bench-conversation-3.log` |
| 额外审计反例，10个检查 | 3通过、7失败（预期契约被违反）；不是原有 suite 失败 | 同目录 `audit-reproductions-final.log`、`audit_contracts_test.dart`、`audit_terminal_test.dart` |

全量测试中的现有性能 harness 仍输出 code `formatCalls=0`、viewport C `indexOfScans=0`、shell `retainedMax=1`。其 wall-clock 来自并行全量测试，不能用于和旧独立测试的百分比直接比较。本轮基准显示亚毫秒量级和可见抖动，未运行隔离的旧实现 A/B，不据此宣称新的提升或回退百分比。

反例文件放在 build 下，避免把本轮未修复的预期失败并入常规 CI。它们有实际产品调用与期望断言，不修改生产源码。最初探针误用不存在的 setConfig 方法，已改为真实 selectMode 后重新执行；只以 `audit-reproductions-final.log` 为最终反例结果。

## 3. 必须进入下一轮的发现

### A01 / P1：结构守护空跑及 URI 解析不完整（实测）

`test/structure/boundary_guard_test.dart:19–30` 先用 `f.path.startsWith('$prefix/')` 过滤，未归一化 Windows 分隔符。探针调用原函数得到 `scanned=0`，独立枚举 `lib/protocol` 得到23个 Dart 文件；三个“通过”断言可能是在空集合上执行。

同文件 declaredUris 的单行贪婪正则把 `import 'ok.dart' if (dart.library.ui) '../ui/bad.dart';` 当作一个畸形 URI，并漏掉跨行 export。原测试声称覆盖条件导入/导出，不符合实测。应修复扫描/解析/解析路径、加入非空与负向 fixture 验证，然后重新审计真实依赖图。当前未发现实际跨层违规不等于守护有效。

### A02 / P1：设备报告的 P50 实际计算为 P95（源码与原始日志互证）

`integration_test/streaming_frame_metrics_test.dart:40–43` 和 `mobile_frame_profile_test.dart:47–50` 的 helper 固定取 `0.95`，调用方却同时标为 P50/P95。旧原始日志的 P50/P95 逐项相同与此一致。此前 P50 字段无效；P95 可保留为原实现约定下的近似值，不能凭 P50/P95 相同推断帧稳定。

两个采样器遇到 frames=0 只打印并 return，集成测试仍可能通过；需把缺样本标为失败/无效采样。回调窗口、分位方法、样本量、build/raster/totalSpan 和环境应统一。日志 refreshRate 为333.0（模拟器报告值），固定8.33/16.67ms只能作为参考阈值，不代表该设备真实刷新率达标。

### A03 / P1：真实320宽 ComposerBar 未达到移动主动作目标（实测）

`composer_toolbar.dart:59–68` 假定最小320视口仅扣8得312，以此设置 touch 门槛。但真实 ComposerBar 外层 `ConversationColumn` 已有两侧各16 padding，传给工具栏的容器宽小于门槛。使用生产 ComposerBar 的测试，在320×844得到发送目标 **28×28**；344和390宽对照均为48×48。

`test/ui/mobile/mobile_matrix_test.dart` 用单独 Toolbar + `size.width-8` 宿主，恰好绕过生产父约束。修复应重排真实小屏工具栏，不能继续降低字体/触控目标或改测试尺寸掩盖。相关 chip minWidth=44 也需核验实际最终命中框。

### A04 / P2：模式面板打开期间不跟随配置变化（实测）

`showComposerModeSheet` 只传 optionsBuilder，没有像桌面路径一样订阅 controller。调用 optionsBuilder 不会自行触发 rebuild。探针打开面板后通过 controller.selectMode 切到 plan，controller.config 已更新，面板对应 Semantics.selected 仍为 false。

需补选中态、可用性/断线、来源更换和 dispose 的动态契约，保持共享 controller；本轮没有证明错误配置被远端接受，问题首先是可见状态滞后。

### A05 / P2：模型元数据“重试”没有操作（实测）

`composer_menus.dart:87–150` builder 收到 refresh，却未传给手机行；错误状态生成 `sectionHeader: true` 的“Retry model metadata”。探针找到文案但其祖先可用 InkWell/Button 数为0；它只是一段标题。

应变为真实可点击的重试，验证一次点击发起对应读取、失败保留选择、成功恢复、来源切换拒绝迟到结果。不能要求关闭重开面板充当重试。

### A06 / P2：共享设置保存失败行窄屏溢出（实测）

`settings/settings_widgets.dart:182–198` 的 saveFailedColumn 是无弹性的 Text + 间距 + 按钮 Row。320宽、左右20 padding 的英文合成宿主出现 RenderFlex overflow（本轮默认测试字体记录421px，仅作为该fixture数值）。这是真实共享组件的错误状态缺口，应再用实际字体与真实页面核验；不把该数值泛化为真机像素。

优先在共享组件修复换行/布局并补失败后重试交互，避免各设置页复制补丁。

### A07 / P2：终端关闭目标只扩大高度（实测）

`terminal_panel.dart:558–568` compact 关闭框是36×48；现有 terminal_drawer_touch_test 标题写48px但宽度只断言≥36。按原48×48契约补强断言后失败，实际 rect x236→272。需补两轴尺寸和目标边缘/相邻误触测试，不回退到“满高即可”。

### A08 / P2：代码缓存有条目上限，没有内存权重上限（源码确认，影响待测）

`code_renderer.dart:422–460` 顶层 LRU 最多8项，key持有完整source，value持有TextSpan树。8项不限制单项文本和span规模，连续大代码/不同流式版本可能长期保留较大对象。尚未测得泄漏或OOM，不宣称已经发生。

下一轮测单项/累计源码规模、span/token数量、驱逐与切换后的内存；建立总权重+单项准入限制，大项可不入缓存。保留缓存命中收益，不通过截断复制文本达到预算。viewport key保留及同List原位修改索引的边界可另作测量候选，未实测不先重写。

### A09 / P2：部分设备性能场景并非对应产品路径（源码确认）

`mobile_frame_profile_test.dart` 的 panel-route 推入简单 Scaffold/Text，不是 WorkspaceShell/真实审查面板；keyboard-inset 是手动MediaQuery注入，不是真实IME动画。StatefulBuilder 每次构建还 new ComposerStore，污染“仅键盘变化”的资源/状态基线。

应保留这些低层合成探针的准确标签，新增真实产品宿主与资源计数，不能继续把简单route与手动inset结果当完整产品面板/IME性能验收。

### A10 / P2：接续文件和完成条件互相矛盾（文档确认）

- optimization master CURRENT SOURCE 仍为23f0b30+dirty/0.1.0+11，当前已提交76d2bd4/0.1.0+12。
- 首次读取时，mobile 清单 CURRENT BATCH/NEXT 仍回到M1-r1且重复BLOCKERS，与后文集成/39测试/最终报告冲突。交付前其他任务已把CURRENT BATCH改为全部done并补任务菜单测试；这部分文档纠偏不再列作未处理事实，但“仅剩真人条件”的判断仍与本轮反例冲突，UPSTREAM BATCH仍留历史进行中描述。
- mobile final-report 写“任一闭环后…专项升级完成”，但列出多项必需条件；应全部适用门满足才完成。
- 结构清单 S4 没有完整独立判定，browser/indexing仍有未勾选项；S2搜索/消息动作、S3余下层次是暂缓，不能写成全目标皆完成。
- mobile design 一面写全部目标≥48×48，一面登记36×48终端和窄容器回退；本轮已证明最小手机受影响，需恢复原验收要求。

## 4. 设备与视觉证据边界

本轮 adb 当前可见16448、16480、7555及emulator别名；读取的三个TCP端点均报 abi=x86_64、uname=aarch64、qemu值空，属性并不一致。型号字符串不能证明实体机；本轮未确认独立物理设备、未更改方向或启用服务。身份记录见 `device-identity.txt`。旧文档已有7555“真机→模拟器”更正，16480的实体机/投屏认定亦应由下一轮结合运行实例映射复核，不能仅凭V2309A恢复为真机结论。

打开检查了旧证据 `build/mobile-portrait/device-qa/08-general-detail.png`：分类详情和返回入口可见，仍有AppBar/正文双标题与较大的纵向间隔；这是历史合成状态的观察，未与本轮HEAD重新成对截图，不新增视觉通过结论。下一轮优先复现失败/有数据状态，不能用断线空态代表整个设置页面。

TalkBack真实焦点/朗读、实体机手势、单手主观体验仍需对应条件；本地A01–A10无需等这些条件即可继续。

## 5. 下一轮顺序

1. 修结构守护与性能采样器，恢复验收工具可信度（A01/A02）。
2. 修真实手机宿主与共享错误状态、面板动态/重试和触控目标（A03–A07）。
3. 补缓存内存预算与真实产品采样宿主（A08/A09），测量优先，不重做已排除优化。
4. 对结构暂缓项做一次范围判定；仅提取能明确减少所有权耦合的领域。
5. 当前同源码联合验收并同步清单/证据身份（A10）；所有必需门满足才关闭专项。

执行入口：[第二轮联合长程 Prompt](optimization-round2-execution-prompt.md)。
