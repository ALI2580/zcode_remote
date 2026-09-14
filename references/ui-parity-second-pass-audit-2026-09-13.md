# ZcodeRemote 第二轮官方体验差异核对

核对日期：2026-09-13。范围：本次反馈的十组问题、关联 U01–U16 与必要回归。本轮只核对并编写实施 Prompt，没有修改产品代码、运行修复测试或重新安装 APK。

## 核对依据与边界

- 已读取关联 Codex 任务 `01a09624-f13c-72c1-9c8a-4e238164db73`（任务名：执行UI全局一致性契约）。该任务最后约定：ZCode 实施；Codex 在用户通知后审查一次。本轮继续这一分工。
- 已读取 Downloads 中的 `ZcodeRemote V2 — TODO-DRIVEN GLOBAL EXECUTION CONTRACT.md`，继承持续执行、证据驱动、作用域隔离、上下文恢复及最终交付要求；不继承其中过时的版本、测试数量、设备端口和起始任务。
- 当前 `ui-parity-current-todolist.md` 已记录 r5/r5b，晚于关联任务的 r3 报告。历史安装包仍使用 `0.1.0+10`，所以单看版本号不能确定实际运行的是哪轮源码。
- 官方依据：`references/official-web-baseline.json`、`assets/official/index.js`、`assets/official/index-BMndL2ru.css`、`build/official-web/assets/IntlProvider-BDZANi-i.js`、现存官方截图。
- 本轮实际计算了两个本地官方主 bundle 的 SHA-256，`assets/official/index.js` 与 `build/official-web/assets/index-nOVzQNKW.js` 均为 `f5010766237b56c3f0f8e6b110624d282d5375db62e2257846e2fe90e227469c`，与固定基线一致。
- 本轮尝试访问官方公开入口，但网页读取工具未能打开。没有新建已连接的官方会话，也没有本轮同状态官方/产品动态录像。下文区分源码确认、历史截图和待运行复现，不将旧截图称为本轮实时验收。
- 已查看官方模型页、官方对话页、r5 产品模型页、r5 产品引导弹窗。它们的主题、有效宽度或来源不同，只能辅助结构判断，不能计算同态像素差异，也不能混用两台远端的套餐数据。

## 差异结论

### U17 使用统计：Pro 套餐与“暂无编程套餐统计”

**确认：现有页面把多种来源状态折叠成同一空态。当前账号是否命中其中哪一条，仍需相同来源的运行证据。**

- `lib/ui/usage/usage_page.dart:308`：`usage.source == null || source.isStartPlan` 时直接返回“当前连接暂无可用的编程套餐统计”。此分支没有先处理 `usage.failed` 或 `sourceUnavailable`。
- `lib/state/composer_usage.dart:183`：读取套餐选择失败可以留下 `source == null`、`failed == true`。统计页因此可能把读取失败表现成无套餐。
- `lib/ui/workspace_shell.dart:135` 与 `lib/ui/settings_center_page.dart:1605`：使用统计入口复用工作区 Composer 的 `usage`。
- `lib/state/composer_controller.dart:220`：该来源由 `config['provider']` 驱动；`composer_usage.dart:124` 又只对支持的 provider 读取套餐来源。自定义模型供应商与账户套餐统计选择的耦合需要核对官方规则。
- 官方 bundle 包含 `sidebarUsageCodingPlanProviderPreference`；这提示统计来源存在独立偏好路径，需要跟踪实际调用和适用范围，不能仅凭符号名直接设计新协议。
- r5 的 ALI 模型设置截图能显示 `GLM Coding Pro`。这证明那轮该来源的设置路径取得过套餐数据，不能证明所有来源或当前统计路径均正常。
- 官方 ROG 模型截图同时出现账号 Pro 标识和“体验套餐 / ZCode Weekend Build”。因此**账号 Pro 标识、所选连接方式、Coding Plan 权益与统计接口支持情况必须分开**。

修复验收应包含：同设备同账户从套餐卡进入统计；当前模型为自定义供应商；来源读取失败再恢复；个人/团队/体验/API Key；跨来源切换与旧请求迟到。不能通过硬编码 Pro、取消门控或伪造统计值解决。

### U18 交互模式中文/英文

**确认：已有中文词表，但来源识别存在使其失效的路径。**

- 官方 `FYe` / `IYe` 和 i18n 含中文及英文标签、说明，例如 GLM 的“完全访问”“计划模式”。
- `lib/ui/composer/composer_mode_metadata.dart:28` 通过 provider 名称包含 claude/codex/gemini/opencode/glm 等字符串推断模式家族。
- `lib/ui/composer/composer_menus.dart:62` 与工具栏把 `config['provider']` 传给这一判断；若它是自定义模型供应商 ID，家族可能为空。
- `modeLabel` / `modeDescription` 在家族未知时回退服务端 name/description，因而可以在中文界面保留 `Full access`、`Plan mode`。

应查明官方用于翻译的 Agent 类型/能力目录标识，从真实元数据传入；切换 UI 语言同时更新按钮、菜单、说明与 Tooltip。协议 mode value 不得翻译。未知自定义模式仍需保留可靠原文。

### U19 设置中心右侧宽度

**确认：所有设置内容统一套用左对齐的 864 上限。**

- `lib/ui/settings_center_page.dart:1943`：右侧 Expanded 内是 `Align(topLeft)` → `ConstrainedBox(maxWidth: 864)`。
- 官方模型截图中的主内容在右侧工作区居中，外部面板和内部表单并非同一个宽度概念。
- 模型列表/详情又在 `settings_center_page.dart:3014` 用 720 断点、240 宽列表和 16 间隔；外层宽度会改变内部布局。

应测量外壳、导航、右侧面板、内容容器和内部列宽，修复共享约束。官方允许内部阅读上限，不能把整个右侧外壳都压缩，也不能不分页面全部拉满。

### U20 对话顶栏按钮与对话可用宽度

**源码确认高风险布局结构；精确位置需最终渲染验证。**

- `lib/ui/shell/shell_layout.dart:300` 标题使用 `Expanded`，操作区在 `:349` 附近又使用 `Flexible` 包裹横向滚动行。
- 同级两个 flex 默认同权重，但操作区采用松约束；按钮较少时可在标题分配宽度之后提前结束，右侧剩余空间留白，与“按钮落在中间约 2/3”相符。
- 官方已查看的对话截图将对应窗口级操作放在右上边缘；应按真实标题、按钮数量及辅助面板开关测量。
- `lib/ui/conversation_layout.dart:6` 已实现官方 864/1280 分段阅读宽度；官方 `g5e/_5e` 本身也有正文 max-width。因此不能把正文留白全部判为缺陷。

验收必须分别测量：完整聊天外壳、顶栏操作区、消息阅读列、Composer、辅助面板。顶栏不能继承正文窄列。关闭辅助面板后不能残留空白占位。

### U21 审查先文件列表，再右侧 Diff

**确认：当前摘要展开会自动选中首个文件并内联展开 Diff。**

- `lib/ui/chat_page.dart:2199` 展开变更摘要后立即构建 review body。
- `lib/state/file_changes_review.dart:185` 在未选文件时默认选中第一项。
- `lib/ui/chat_page.dart:2358` 的文件行调用 `review.select`；`:2585` 附近直接 `if (selected) _buildDiff(ink)`，所以文件选择在聊天内展开红绿内容。
- 文件列表之外另有 `onOpenReview` 的右侧打开路径，形成两套不同交互。

应统一为“摘要/审查入口 → 文件列表 → 点击某文件 → 右侧该文件 Diff”，返回列表和关闭面板应保持会话读位与选中状态。工具调用行自身的内联编辑 Diff 属于 U05，不能因修改审查路径而全部删除。

### U22 修改后的审查、撤销可发现性

**确认代码已有能力，尚不能把反馈归结为‘完全没实现’。**

- `chat_page.dart:2040` 仅在非 running、未 reverted 且 `actions.canRewindFiles == true` 时展示撤销。
- 文件行的“审查”还受 `FileChangesReviewHost` / `onOpenReview` 是否接线影响；摘要头部没有统一显式审查按钮。
- 已有撤销预检、应用路径及历史 r4 变更条截图。仍需检查首发完成、历史加载、重连、不同 Agent 行类型和当前安装包是否都提供同一入口。

修复重点是实际产品入口、回合/文件作用域和能力门控。不能只补两个无行为按钮，也不能绕开远端 capability 强制显示可执行撤销。验证撤销应使用可控假服务/独立 QA，证明预检范围、冲突和重复点击语义。

### U23 模型设置列表、编辑、新增

**确认存在结构差距，完整表单逐控件一致性尚未完成本轮动态审查。**

- 官方截图为一体式边框容器、内部导航分隔线、品牌图标、详情与模型操作行。
- 当前 `settings_center_page.dart:3014` 由两张独立卡片和 16 间距组合；BigModel 家族头/导航仍有通用 `box` 图标，与官方品牌图标不同。
- 当前供应商配置编辑经 `_editProviderConfiguration` 弹 Dialog；新增经 `_ProviderCreateDialog`；需要与官方对应入口逐一核对内联/弹窗形态，不能仅凭“有表单”判通过。
- r5b 已修正 unplug 测试按钮、pending 与结果徽章。应保留并复验这部分，不能拿它代替列表、API 格式、端点、密钥、模型新增/编辑/删除全过程验收。
- 当前还记录 r5-1：ROG 设置读取失败。该缺陷本地可继续定位，不能统称官方对照外部阻塞。

### U24 引导欢迎页与多步骤流程

**确认：现有引导入口映射错误；官方向导不等于导入设置弹窗。**

- `settings_center_page.dart:3404` 直接 `SettingsImportDialog.show`，与已查看的 r5 引导截图一致。
- 官方 bundle `L$t` 包含欢迎页、开始按钮、迁移入口、品牌视觉区；`A$t` 包含 session、skills-import、mcp-import、commands-import、agents-file、migration 步骤。
- `M$t` 渲染步骤导航；footer 包含 `onBackStep` / `onNextStep` / `onBeginMigration`；i18n 有欢迎、各步骤和完成状态文案。
- 本次反馈特别要求第一步的左侧图。固定源码中欢迎页视觉区在右半区，向导步骤导航在左侧；**不能未经确认将两者认定为同一页面**。实施需实际打开对应版本、对应“第一步”定位该图并取资源依据，保留用户要求为待核对验收项，不能以旧源码片段删除它。

### U25 语音模型大小与连续下载反馈

**确认缺少大小数据；百分比已有实现，但有停滞和卡顿风险。**

- `lib/voice/voice_models.dart:1` 未提供大小字段；管理页没有模型大小或“已下载/总大小”显示。
- `voice_model_manager.dart:249` 已有确定型进度条和百分比，不能重复创建后称为修复完成。
- `voice_model_store_native.dart:191` 将进度初始化为 0；只有响应 `contentLength > 0` 时逐块更新。总长未知时可能持续显示 0%，而不是未知总长的动态反馈。
- 同文件 `:221` 附近同步读取压缩包、BZip2 解压和 Tar 解码；大模型解压存在 UI 阻塞风险，需要连续帧/耗时证据。
- 每个进度事件触发管理页 `_refresh` 遍历模型读取可用性；应核查通知频率和最终代次校验是否使显示更新饥饿，不能仅测试 fake progress=0.5。

应建立 downloading/extracting/verifying/ready 状态；下载大小有可信来源，未知大小不编造；已知总量显示字节、百分比和连续变化，未知总量动态指示。取消、重试、退出再入及切换模型均验证。

### U26 通知与上岛内嵌设置右栏

**确认：当前是二次导航，未内嵌。**

- `settings_center_page.dart:1972` 仅显示 ListTile；点击后 `Navigator.push(MaterialPageRoute(...NotificationSettingsPage))`。
- 用户要求将该页面主体置于设置右侧内容区，应参考已有 appearance/usage/device 的 embedded 接口复用主体，保留窄屏合理导航。
- 这是 Android 客户端能力的明确产品要求，不能伪称官方 Web 已有同名通知/上岛页。

## 建议执行次序与交付

1. 建立本轮来源/包身份和失败场景；优先定位 U17 与 r5-1。
2. 修复共享几何 U19/U20，嵌入 U26；再确定页面内部宽度。
3. 修复 U18，再推进 U21/U22 的完整审查与撤销路径。
4. 对齐 U23 模型完整操作流，重建 U24 引导流程，完善 U25 下载状态。
5. 回归原 U01–U16 与新增 U17–U26，按相同来源、状态、主题、字号、有效宽度逐项对照，最后冻结新安装包。

可直接交给 ZCode 的完整实施契约见 `ui-parity-second-pass-execution-contract.md`。本轮没有把上述项目写成已修复或验收通过，也没有更改旧清单的勾选状态。
