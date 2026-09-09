# 协议层地图（改 lib/protocol/ 前必读）

## 分层与依赖方向

```
connection_params ─→ proof ─→ relay_client ─→ rpc_transport ─→ ipc_codec
                                                                  │
                             zemote_client (门面) ←─ channel_client
                                     │
                              conversation (V4)
```

协议目录全部使用纯 Dart；2026-09-09 已将 conversation、bridge、relay 的通知对象替换为
`observable.dart`，平台识别使用条件导入的 `dart:io` / Web 兜底。UI 层仍由自己的
ChangeNotifier / 页面监听持有业务状态。`dart run tooling/protocol_smoke.dart` 编译完整协议依赖图并验证投影。

## 与官方 Web 客户端的对应关系

官方 Web 端代码是混淆过的，本项目实现时在注释里标注了镜像来源：

| 本项目 | 官方 Web 端 | 说明 |
|---|---|---|
| `ZemoteClient` 整体流程 | `otn()` | relay connect → pair → bootstrap → bridge → channel |
| `ZemoteClient.request()` + matcher | `k()` | 请求/响应按 matcher 匹配，**响应不保证回带 requestId**，每个 payload 要过所有 pending matcher |
| `ChannelClient` | `Pne` | channel RPC 请求/响应编解码 |
| `sendMobileViewState()` | `N()` | 上报当前视图状态 |
| `BridgeSession.conversation()` 缓存 | `wD` | 每 service 握手一次，按 scope 缓存；transport 换栈时清除缓存重新握手 |

## 关键帧格式

- **rpc-frame**（relay payload 上的分片传输）：字段 `bridgeSessionId` / `seq` /
  `messageSeq` / `fragmentIndex` / `fragmentCount` / `messageBytes` / `dataBase64`；
  接收方需回 `rpc-frame-ack`；CRC32 校验（`crc32.dart`）。
- **Channel 请求头数组**：`[reqType, reqId, channelName, name]` + 参数值。
  reqType：`100` promise 调用、`101` 取消、`102` 事件订阅、`103` 订阅释放。
- **Channel 响应头数组**：`[respType, reqId]` + 数据值。
  respType：`200` Initialize、`201` 成功、`202/203` 失败、`204` 事件触发。
  **`[200]` 是单元素合法 Initialize 帧**（曾因误判畸形导致全部 RPC 超时）。
- **IPC 编码**（`ipc_codec.dart`）：值编解码 + 13 字节 IPC 帧。注意：workspace bridge
  上的 rpc-frame 消息体**就是**一个 ChannelClient body（value-stream），不走 13 字节
  IPC 分帧；13 字节帧用于别的通道路径。别把两条路径的分帧规则搞混。
- **Conversation V4**：快照 + 增量（delta）；`sessions-index` 订阅 + workspace-list
  推送双源合并；历史分页用已加载的最旧消息作游标。

### 历史分页（2026-09-09 基线核查）

- `index-nOVzQNKW.js` 的 `wb` 判断 `window[0].rowId > rows.firstRowId`，`firstRowId` 是全局下界，不能分页后改成当前页首行，也不能用 `totalCount > window.length` 替代。
- `LTe.loadOlder` 请求 `rowsRange`，只在 `atLogEpoch == 当前 logEpoch` 且请求的最旧游标仍等于当前游标时合并；`Tb` 只保留 ID 小于当前头部的行，旧响应不能覆盖实时尾部。`atSeq` 不替换订阅序列。
- `src-DHgFesxz.js` 的固定限制为普通尾部 60 行、最大范围 200 行。阅读恢复只循环到保存的消息，无进展或失败可显式重试，不进行无限空页循环。
- `ConversationState.applyHistoryPage` 与 `ConversationHistory` 分别处理协议校验和页面生命周期。新日志清理旧页及耗尽标记；页面释放后的结果不写入其他作用域。

## 连接状态机与恢复

### Coding Plan 重置与统计（2026-09-09）

- `usage-stats.getCodingPlanResetStatus([{preferredProviderId, organizationId?, projectId?}])`，纯只读；返回 `availableFiveHourResets/availableWeekResets`（条目含 `expireAt`）、两类 `latest*ResetHistory.usedAt`、`hasUnreadHistory`。
- `useCodingPlanReset` 在同一参数对象加入 `idempotencyKey` 与 `resetType:'FIVE_HOUR'|'WEEK'`。失败重试保留同一标识；已受理但后续状态未确认只查状态。手动成功以不同于请求前基线的服务端 `usedAt` 为证据。
- `requestCodingPlanResetOpportunity` 在同一来源加入 `idempotencyKey`；5/10 分钟协调重试，瞬断沿用标识。`markCodingPlanResetHistoryRead` 使用同一来源。从 0.1.0+9 起，可见额度界面已接入 5 分钟共享轮询、前台恢复、外部完成、额度重查与已读去重；真实核查使用启动级 `quotaReadOnlyAudit`，仅阻止额度授予/消耗/已读，不是全应用只读沙箱。
- `getCodingPlanUsageSnapshot` 使用 `range:'7d'|'30d'`、`customStartDate/customEndDate:null`、`preferredProviderId`、组织/项目和 IANA `timeZone`；`getAppUsageSnapshot` 使用独立的 `range/timeZone`。官方 `SJt` 套餐页面默认 7d；`Fqt/Mqt` 按来源、周期缓存 60 秒。
- ROG 只读探针已确认三种读取 RPC 可用。应先校验当前来源的 entitlement，未连接的其他家族即使保留 familySelectedKeys，仍可能返回 `zai_coding_plan_api_key_required`，不能据此误判方法不存在。

`RelayClient` 状态：`connecting → paired`，断开进入 `reconnecting` / `error`。
心跳超时先探测（`poke()`）再重连。

`ZemoteClient` 监听 relay 状态：

1. relay 进入 `reconnecting/error` → 立即把所有活动 bridge 标记
   `degraded`（命令发送经 `waitHealthy()` 阻塞排队，而不是在死 socket 上超时）。
2. relay 重新 `paired` → 仅对 degraded bridge 恢复，失败每 3s 继续尝试直到成功或释放：
   - 按官方 `Z4t T → C → P` 重新 `workspace-bridge-open`（新 bridgeSessionId、generation +1、
     同一恢复周期的 recoveryId），把 transport/channels **换入同一个 BridgeSession**。
   - 等待 Channel Initialize 后再宣布健康；不能把 `workspace-reconnect-request` 成功当作
     旧 Channel 栈已经复活，该方法是重连工作区后端的独立入口。
3. 恢复成功 → `session.recovered.value += 1`。所有订阅方监听该计数器重新订阅
   （服务端订阅状态随旧 bridge 一起死亡）。
4. 桌面主动下发 `bridge-degraded` 或针对活动桥接的 `workspace-bridge-error` → 同样进恢复循环；不重开其他健康工作区。
5. 换栈前移除旧路由，旧桥的迟到帧直接丢弃。Conversation handshake 按代次和 Channel 实例校验；旧 hello/失败不得覆盖新 connectionId 或清掉新的进行中握手。

## 已知的竞态点（写新代码时要主动对齐）

- **Initialize 先到**：桌面对端可能在 `openBridge` 的 await 续体注册路由之前推送
  rpc-frame。未知 bridge 的帧缓冲进 `_pendingBridgePayloads`，注册后 flush。
- **并发重连覆盖**：多个重连请求并发时，旧 WebSocket 的事件不得覆盖新连接状态
  （0.5.1-beta.2 修过）。重连路径要带 generation / 独占保护。
- **被踢下线的误判**：连接冲突（在别处打开）会被服务端表现成认证失败；认证阶段先做一次
  干净重连再判定，不要直接报"永久被踢"。
- **订阅初始化失败要清理**：事件监听器和定时器要拆干净，异常分片不得中断整个订阅。
- **回显不保证 requestId**：`request()` 的 matcher 按内容匹配（type + requestId +
  其他键），新增请求类型时 matcher 要收窄到能唯一定位该响应，又不能依赖服务端会回显
  我们没发过的字段。

## 调试入口

应用内三个调试器页（`ui/log_page.dart`、`rpc_explorer_page.dart`、
`channel_explorer_page.dart`）+ 协议日志开关。排查协议问题优先打开 relay/IPC/V4 帧日志。
