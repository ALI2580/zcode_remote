# V2 composer 协议核对（2026-09-08）

依据仓库内已抓取的官方资产，不使用真实设备写入探测：

- `assets/official/index.js`：`Lle/Rle/Vc` 配置选项 schema、`wue` 命令 schema、`kue` 回执、`pf` 模型引用解析、`Nce` injected 过滤、`FI` 模式图标、`VI/zI/HZe` 思考排序与工具栏、pane 的模型/模式/停止回调。
- `build/official-web/assets/src-DHgFesxz.js`：官方共享 schema。导出 `Jc/Kc/Vc/qc/Gc` 分别对应 control、availability、inputRouting、config、queue。
- `assets/official/index-BMndL2ru.css`：composer 容器 24/36/42rem，即 384/576/672；不能用整个屏幕宽度代替主对话或辅助对话的容器宽度。

## 读取配置

`zcode-task.prepareWorkspace([scope])` 返回 `configOptions`。按 `type=select` 与 `category/id` 查 model、mode、thought_level；模型 option 包含 `modelProviderId/Name`、可选 `modelThoughtLevels`、`modelDefaultThoughtLevel`、`origin`。显式空 thought levels 表示不支持思考选择；单选项保留显示但不打开选择器。

模型值包含 `provider/model` 与 `custom:<URI-encoded-provider>:<URI-encoded-model>` 两类；兼容官方旧 builtin custom 写法。去掉 injected 和非 native 的 custom-model 注入项，供应商组遵循官方 builtin 优先级。思考项按官方 rank 排序，未知值保持相对顺序，不硬编码可选模型或默认档位。

已有任务读取 `snapshot.config = {provider, model, thought, thoughtLevels, mode, followupMode}`，不回退到另一会话的配置。模型/思考切换需 `availability.switchModelConfig.allowed`；模式没有对应的 availability 字段，使用返回的模式选项、连接与会话就绪状态，命令 schema 限定 build/edit/plan/yolo。

## 写入及回执

| 操作 | 已核对字段/门控 |
| --- | --- |
| 新任务首条文本 | `createSession`，envelope.sessionId=null，payload `{workspaceId, firstInput:{text}, config?}`。返回 result.sessionId 后迁移身份，不再调用 sendText。 |
| 模型与思考 | `switchModelConfig {provider, model, thought}`，CAS baseRevision。仅用已返回的能力与思考等级，不猜测档位重试。 |
| 协作模式 | `switchCollaborationMode {mode}`，CAS baseRevision。 |
| 已有任务发送 | `sendText {text, heldQueueDisposition?, expectedHeldQueueItemIds?}`。普通发送交给服务端 inputRouting；本轮不发送 requestedDelivery 覆盖值。 |
| 停止 | `control.canStop`、`control.stopState`；从 activeWorks 读取 foregroundExecutionId，传 `stop {expectedForegroundExecutionId?}`。 |
| 队列 | `queue.items` 的 queueItemId/text/dispatch.state；queued 可操作，reserved/promoting 锁定。`queueEdit` 控制移除及 autoDrain，`sendQueuedNow` 控制立即发送。 |

官方回执 status 是 accepted/rejected/stale/duplicate/noop/failed。普通发送只以 accepted/duplicate 为成功；配置/停止/队列还接受 noop。`confirmationRequired` 是官方 UI 返回值，**不是协议 status**：服务端 `reasonCode=guard.heldQueueConfirmationStale` 才触发重新确认。

`inputRouting.mode` 的 startNow/enqueue/guide 由服务端决定如何接收输入；reject 禁止发送。choice 先明确选择保留或清空队列，并提交确认时的 queueItemIds；确认期间队列变化时重新确认。队列状态继续使用服务端推送，不根据点击伪造任务完成。

健康连接超时不重发。沿用断线等待恢复后的单次重放时保留原 commandId/clientId/issuedAt，让服务端按同一操作去重；断线不等于原请求从未到达。CAS stale 的一次重试仍以明确拒绝的回执为前提。

## 有意差异与后续

- 按已确认产品要求，草稿只在 device/workspace 内共享自己的选择；已有任务按 session 隔离。不实现官方 workspace draft 主动收敛到其他 pane 的推送行为。
- 菜单使用 Flutter 弹出菜单，供应商分组选择已可用；官方供应商家族合并、连接方式管理及完整设置仍待迁移。
- 工具栏保留紧凑图标/模型文本/供应商前缀/思考条，触发器最小高度为 32dp（官方基本尺寸 28px），并允许大字号适配；没有同字体同数据官方截图，不能声明像素一致。
- 队列最小闭环已实现；编辑、重排、投递方式快捷键及交互请求表单仍属于后续功能。
