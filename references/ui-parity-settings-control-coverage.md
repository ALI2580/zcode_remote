# U16 设置控件覆盖与验收记录

当前是持续执行表，未勾选为全局通过。固定官方基线见 `official-settings-catalog.json`；源码SHA256 `f5010766237b56c3f0f8e6b110624d282d5375db62e2257846e2fe90e227469c`。`resume/` 指 `build/visual-audit/ui-global-20260912-resume/`。行为、视觉、真实设备分别判定；下面“本地通过”不能替代官方同态和最终产品。

## r3终审状态（2026-09-13）

已逐项结合本表与最终源码/测试核对。r3完整928项通过、1个可选capture跳过，静态/smoke通过；本表后续历史批次中的“最终待验”由本节和主终审记录覆盖，不再表示仍存在同一个本地失败。整体仍因有效配对、官方同态与真实验证码条件保留未完成，恢复入口见 `build/visual-audit/ui-global-20260912-resume/main-final-audit.md` 的E1–E4。

Settings的17入口以健康配对合成来源完成手机/平板原生导航36图；模型空容器另2图修后通过。当前图标与五项MCP又在两端填充合成目录补验4图，主全部打开：CPU/box/pencil及导航图标可见，MCP五项按整页自然滚动，末项可命中。模型完整表单/连接动作以既有控件回归与父级联动覆盖，未把一个供应商默认图冒充所有表单同态。

Plugins快速详情失败已修，配置清除/取消/重入/来源与详情5项生命周期均在最终G通过；Skills/Commands/Subagents父级目标与候选、插件有效投影/刷新、Hooks整表/信任、MCP来源/异步、外观代码消费与复制均完成本地回归。真实远端配置写入未执行，合成成功不冒充远端写入。通知子页英文140%原生已主开；语音实际录音预览/取消/停止草稿与来源撤销另有原生证据。

## 共享行为

远端设置以当前bridge/device/workspace为作用域，setting.update后get读回，失败保留已确认值，pending去重；当前状态层15项测试覆盖常见失败与迟到，实际页相关测试已在`resume/main-u13-navigation-final.log`中运行。页面入口、选择器、滚动、返回由U13覆盖。各控件的实际消费仍须单独检查；例如已确认思考开关保存成功并不能证明聊天显示生效。

## 常规

| ID/控件 | 初态/门控 | 操作/调用与结果 | 取消/失败/重入 | 当前独立判定 |
| --- | --- | --- | --- | --- |
| G01 界面语言 | system/zh/en，本地偏好 | 立即持久化并刷新UI | 重启load恢复 | 偏好持久化/窄屏140%已有本地回归；分组双语已接入，最终shell矩阵复核 |
| G02 继承系统终端 | terminalInheritSystemProfile | setting.update单key→get | 失败留旧值/重试 | 写入本地通过；桌面运行效应限定新会话 |
| G03 终端字体 | terminalFontFamily，可空 | 显式保存trim文本→get | 未保存取消/失败留文本 | 本地表单回归通过；手机终端是否需要同字体须按官方scope判断 |
| G04 集成Shell | system.getSystemInfo win32才显示；listIntegratedTerminalShells | auto或mode/shell/id/path/label/dialect结构保存 | 现有但未列出shell保留；读失败可重试 | 官方字段写入本地通过；当前代码Auto已双语，最终shell矩阵复核 |
| G05 增强Find/Grep | nativeSearchEnhancementsEnabled默认true | setting.update→get | 新建/恢复会话生效，当前会话不强改 | 本地写入通过，实际后端验证单列 |
| G06 HTTP代理 | httpProxy，可空 | 显式保存→get | 失败留草稿，桌面重启生效 | 表单路径本地通过 |
| G07 No proxy | httpProxyNoProxy，可空 | 显式保存→get | 同G06 | 表单路径本地通过 |
| G08 自定义CA路径 | httpProxyCaCertPath，可空 | 显式保存→get | 同G06 | 表单路径本地通过 |
| G09 自动处理问答 | askUserQuestionAutoResolutionEnabled默认true | setting.update→get | 失败原值，重入读回 | 本地保存/失败通过；不擅自回答真实问答 |
| G10 完整模型IO保留 | modelIoFullRetentionEnabled默认false | setting.update→get | 失败原值，重入读回 | 本地保存通过 |
| G11 显示思考 | messageStreamShowReasoning默认true | 保存后原聊天只保留首条或显示全部 | 主辅/切scope一致 | 原失败已修；`main-runtime-integration-after.log`55项含实际Settings→原Chat通过；最终主辅/设备矩阵待V |
| G12 显示Todo | messageStreamShowTodos默认false | 控制消息流Todo卡片 | 不删除任务数据 | 55项含真实四控件保存/返回，卡片可见且原协议行保留 |
| G13 探索工具分组 | toolGroupingExploreEnabled默认true | 连续读取/搜索分类聚合 | 展开/读位保留 | 55项含实际Settings取消分组→原Read行通过；最终视觉/读位矩阵待V |
| G14 终端分组 | toolGroupingTerminalEnabled默认true | 连续非只读终端聚合 | 与探索分类不混用 | 55项含实际Settings取消分组→原Bash行通过，分类单测通过 |
| G15 文件变更分组 | toolGroupingChangesEnabled默认false | 连续编辑工具聚合 | U05/U06摘要和内联diff继续正确 | 55项含保存开启分组→原Edit组通过，并复验inline diff/摘要 |
| G16 交互行为 | zcodeInteractionBehavior | 已确认枚举单key保存 | 失败留旧值 | 本地写入通过；消费与默认行为终审 |
| G17 自动归档 | taskAutoArchiveEnabled | 单key保存，后端处理适用任务 | 不直接触碰真实任务 | 本地写入通过 |
| G18 保留天数 | taskAutoArchiveOlderThanDays | 已确认候选天数保存 | 缺值/不可操作禁用 | 本地写入通过 |

## 外观

| ID/控件 | 初态/操作 | 作用域/反馈/重入 | 当前独立判定 |
| --- | --- | --- | --- |
| A01 界面主题 | system/light/dark立即保存 | 客户端，全UI刷新 | 偏好本地通过，最终五形态视觉待V |
| A02 UI字号 | 12–20整数px、默认14，保留旧偏好兼容 | 客户端，保存恢复 | 已修数字输入，Enter/blur有效提交、非法还原、Escape与外部reset；`main-settings-components-independent-final.log`22项包含该组独立通过 |
| A03 浅代码主题 | 官方10个候选，qyt/Oj | 客户端，真实代码与预览 | 10主题已消费；49项官方颜色独立比对零差异，最终实际切换矩阵待V |
| A04 深代码主题 | 同10候选 | 同A03 | 同A03，浅深两个独立选择器已接入 |
| A05 行号 | showLineNumbers | 预览/文件/代码块/差异 | 当前实际共享渲染消费；长行换行后第二行号主代理开图确认；不混入复制 |
| A06 长行换行 | wrapLongLines | 换行或水平滚动，内容不丢失 | 实际FileViewer/Markdown/diff消费；全选复制旧漏正文已修；本批51项通过 |
| A07 代码字号 | 官方12–20px、默认12 | 真实内容独立于UI字号 | 主验UI20时code18；系统1.4时code25.2，真实FileViewer两图已核对 |
| A08 预览 | 浅深两个真实渲染示例 | 当前值即时显示 | 两图已打开确认，数字输入和紧凑控件命中已主验；整体shell/最终设备仍待 |

## Agent能力页面

| 页面/控件集合 | 入口/门控与数据 | 操作/持久化与失败 | 当前状态/详细记录 |
| --- | --- | --- | --- |
| 模型：列表、选中、刷新、排序、详情、连接方式 | 当前model-provider目录；家族模式与key一致 | getAll/getDisplayOrder/save/delete/setDisplayOrder及setting.patch | 普通连接/format/plan本地主验已过；CAPTCHA真实Settings无配置/MethodChannel路径2项通过。真实远端挑战及最终视觉待，见`resume/u14/main-review.md`和`u14-captcha/main-review.md` |
| 模型：创建/编辑供应商、API key、endpoint、format、model列表与默认配置 | 官方k8/S8/cVt draft；headers在payload中不等于存在编辑字段 | name/baseURL/API key blur提交，format立即提交；测试方法不主动save；删除/内部提交有cleanup门控 | provider保存/退出cleanup原本未刷新主辅目录，独立两项修后通过；原草稿保留。字段主体Luna76项自测是辅助证据，不代替最终逐控件视觉与G |
| 模型：model ID/name/kinds/context/maxOutput/inputModalities | D8/xVt：name可空，text输入必须，image/video/pdf可选，output固定text；reasoning/priority保留非编辑 | 正整数校验、真实model ID，不随机生成调用ID | 当前字段实现已接续，见U14 implementation；最终候选需将合并控件拆开核对，不再把历史取证缺口当当前阻塞 |
| 子智能体：scope/search/refresh/group/create/edit/delete/enable/builtin override/form | user/workspace/plugin/built-in与capability | 已确认subagents全部写法，取消/失败/迟到控制 | 主体18项主代理通过；父级B workspace/model候选与慢A→B旧失败修后在`main-command-independent-target-review.log`9项集合通过；最终shell/设备待 |
| MCP：scope/search/config/status/new/edit/delete/enable/authorization/import | 配置与status分开；插件派生只读 | mcp-sync真实写法、读回；不能将status轮询升级connect | 返工后`main-mcp-rework-final.log`31项独立通过并开after图；跨页插件刷新/原生/最终视觉待，`resume/u16-mcp/main-review.md` |
| 技能：scope/search/refresh/detail/enable/delete/new/import/diagnostics | list返回完整capability/diagnostics/metadata；plugin只读 | skills启停/删除，new为未发送skill-creator草稿，settings-sync导入 | 主代理5项state/mention/detail、3项真实scope/导航、2项空/占用draft保持均通过；已冻结主体，官方同态与插件跨页刷新待，`resume/u16-skills/main-review.md` |
| 命令：scope/search/refresh/create/edit/delete/enable/import | user/project/plugin与capability；门控按S7/zi/Yxt | wire为writeCommandFile/updateCommandFile/deleteCommandFile/setCommandEnabled；settings-sync导入 | wire与独立表单target、pending禁写、写B/刷新B而列表User、读回/插件迟到在`main-command-independent-target-review.log`9项主验；后续13项含表单/wire重放，最终视觉/卸载回调具体路径待 |
| 钩子：scope/search/refresh/row enable/new/edit/delete/import/event/type/matcher/command/timeout/advanced JSON/trust | 原配置读回，修改新会话生效；workspace信任按identity/digests | loadHooks/saveHooks整表；grantWorkspaceHookTrust无会话分支；未知字段保留，失败/取消保护 | `main-hooks-final-state-independent.log`8项通过，实际Settings trust拒绝重试/慢A→User另2项通过；整表丢更新已修。完整xZt 4395175:4401563 render链无全局hooksEnabled控件，字段仅不可用service stub，见下方门控；最终shell/设备未全通过 |
| 插件：scope/search/refresh/installed toggle/row/detail/marketplace/import | pluginManagement读当前workspace与configScope有效投影，保留user安装继承 | 启停/配置delta/清除/恢复默认/管理与市场，成功读回刷新主辅目录 | `main-plugin-effective-independent-checkpoint.log`10项与`main-plugin-parent-final-independent.log`13项主验通过；控制生命周期新增4项通过，快速detail错误已修，5项生命周期由最终G复验通过，见Plugins main-review |
| 浏览器：内置控制switch | browser-use@zcode-plugins-official安装门控 | pluginManagement启停，非setting假开关 | 本地保存通过；错误/禁用原因/重入与最终设备待验 |
| 浏览器：数据导入/清理/证书 | LZt桌面能力门控；导入只在WindowsDesktop隐藏 | web remote保留禁用导入/清缓存/清全部行+说明，安全证书switch隐藏 | 已开官方browser2图和源码确认；当前3条禁用行及原因已补入并生成matrix图，最终shell/设备复核 |
| 记忆：workspace memory开关 | memoryEnabled默认false | setting.update→get，新会话生效 | 本地写入通过；已开官方记忆图确认详情仅桌面说明，当前remote详情N/A |
| 索引：新文件夹 | repoSnapshotIndexingEnabled | 与UserConfigured:true一个patch | 本地通过，官方只有该控件时不凭原索引描述补造目录动作 |
| 索引：即时搜索 | instantGrepIndexingEnabled默认false | 单key patch→get | 本地通过，冻结源4402341附近支持 |

## 内嵌与本地扩展

| 页面/控件 | 作用域与操作 | 当前状态 |
| --- | --- | --- |
| 设备：添加链接/编辑链接/命名/移除/连接/返回 | DeviceStore加密本地存储；删除先确认；连接沿已有路由 | U13内嵌与返回独立通过；设备管理既有用例与最终包复验 |
| 统计：应用/套餐tab、range、refresh、图表/明细 | bridge/device/workspace；隐藏停止计时；保存浏览状态 | 63项集合覆盖内嵌/来源晚到/重入；真实官方同态与最终设备待验 |
| 语音：模型下载/导入/选择/删除/设置入口/错误引导 | 本地模型；未配置不自动开始/发送 | U07/U08已有模型与真实FFI证据；真实mic及实际Composer预览/取消/停止草稿/来源隔离已原生通过 |
| 通知：系统权限/总开关/声音/提醒范围/测试入口 | 本地Android能力，任务跳转保留scope | 既有回归待G按当前依赖复验，不能称官方同名页 |
| 更新：Beta开关/检查/下载/安装/进度/错误 | 已有客户端更新流程；与发布授权区分 | 无当前改动，既有有效测试在G复用/必要复验；不新增发布 |
| 账户入口：usage/upgrade/disconnect/语言主题 | scoped monitor和本地偏好 | 原账户回归已通过；断开不是退出账号，保留原语义 |

## 当前版本不适用项

自动化：官方cb()当前排除，目录中webDefaultVisible=false。电脑控制：desktop/Mac/Windows且cuaGrayEnabled门控，当前web remote基线不可见。MCP/技能的本地→SSH/WSL远程资源同步：`m1`对web-remote-replayable返回false；外部Agent导入不是这个同步入口，仍属必需本地实现。详细出处见`resume/u16-mcp-skills-design.md`。

Hooks全局开关：主代理完整读取冻结`resume/u16-hooks-page-body.txt`的xZt 4395175:4401563，页内form分支、scope/count/search、workspace信任提示、错误/加载/空态及aZt行集合均已枚举，只有逐hook toggle。bundle唯一hooksEnabled来自4742209附近不可用hooksService stub的loadHooks默认值，不是本页可操作字段；因此不新增全局开关。此结论限定当前3.11.2 web remote页面。

## 历史批次后续记录（以r3终审为准）

Settings整体shell、Plugins快速详情错误、441中文语言卡和通知详情英文均已修复。Plugins 5个完整生命周期用例在主代理完整G中通过；真实IME与profile mic、Composer草稿联动已有原生证据。手机第二轮paired合成来源18图已全部主开；平板原生与语音可见预览的横屏键盘返修仍在执行。最终V/G和产品身份以 `resume/main-final-audit.md` 收口，不用本表存在或历史批次数量代替验收。
