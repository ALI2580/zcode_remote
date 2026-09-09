# ZcodeRemote

## 重建进度

开发路线已确定为 **纯 Flutter 界面与业务逻辑 + Android 系统能力接口**，主要支持 Android 手机、折叠屏和平板。官方 Web 只作视觉与协议参考；`web_client/` 已停止作为产品路线。

本轮接入应用级多设备连接、任务列表监听、Android 预测性返回、ColorOS 16 / Android 16 Live Updates 请求、通知点击定位任务及 Keystore 凭据存储。系统接入说明见 [references/flutter-android-integration.md](references/flutter-android-integration.md)，布局目标见 [references/design-draft-v2.md](references/design-draft-v2.md)。完整官方 UI 与全部设置仍在原生重建中。

V2 主工作界面已接入产品入口：项目/任务侧栏、左下设备与头像菜单、客户端设置、五种屏幕布局、Markdown、辅助对话和阅读状态恢复。最近一批的验证与待迁移项见 [V2 实施记录](references/v2-implementation.md)。ColorOS 16 上岛已获真机反馈确认，完整终端、审查、官方远程设置和离线语音仍在后续迁移范围内。

**手机/平板上的 ZCode 桌面远程控制客户端** — 干净的协议复刻实现（clean-room protocol reimplementation）。

## 与 Zemote 的关系

本项目**不是 Zemote 的 fork**，而是从零另起炉灶的独立项目。它继承了 Zemote 两个最有价值的资产，其余全部重构：

| 资产 | 处理方式 | 说明 |
|---|---|---|
| `lib/protocol/` | ✅ 照搬 | 纯 Dart 协议栈（relay 配对 / rpc 帧 / Channel / Conversation V4），120 个测试锚定行为 |
| `references/` | ✅ 照搬 | 官方 Web 客户端逆向知识库（样式规格、协议映射、踩坑记录） |
| `lib/ui/` | 🔧 重构 | 不继承任何旧 UI 代码；按官方样式从零写，`chat_page.dart` 不再有 7000+ 行巨石 |
| `lib/state/` | 🔧 重构 | 多设备管理从零设计 |
| `lib/update/` | ✅ 借鉴 | 保留 GitHub Releases 更新检测机制（仓库名已参数化为 `updateRepo`） |

## 架构

```
lib/
├── protocol/            ★ 核心：纯 Dart 协议栈（自底向上依赖）
│   ├── connection_params.dart   远程控制 URL 解析（sid/hash/t）→ relay WS
│   ├── proof.dart               配对证明 HMAC-SHA256
│   ├── relay_client.dart        relay WebSocket + 心跳 + 重连状态机
│   ├── rpc_transport.dart       rpc-frame 分片/重组/CRC32/ack
│   ├── ipc_codec.dart           IPC 值编解码 + 13 字节帧
│   ├── channel_client.dart      channel RPC（reqType 100-103）
│   ├── conversation.dart        Conversation V4 快照 + 增量
│   └── zemote_client.dart       门面：relay→配对→bootstrap→bridge→channel
├── state/               🔧 重构中：DeviceStore（多设备）、凭据加密
├── ui/                  🔧 重构中：官方配色 ZInk 体系 + 多设备首页
└── update/              GitHub Releases 更新检测（参数化 repo）
```

## 多设备（核心目标）

- `DeviceStore` 管理多台桌面：添加（粘贴远程控制链接）、重命名、移除、最近使用排序。
- `AppSessions` 持有每台设备的连接与工作区监听；页面返回时不销毁连接。
- 通知按设备/工作区/任务定位；设备本地 UUID 与配对凭据分离。
- 凭据安全：`sid/hash` 在 Android 上经 Keystore AES/GCM 加密落盘（`CredentialCipher`）。

## 开发

```bash
flutter analyze    # 零告警门槛
flutter test       # 协议/状态/更新单元测试
flutter run        # Android
flutter build apk --debug
```

## 发版前必改（铁律）

- 版本号三处同步：`pubspec.yaml`、`lib/update/app_version.dart`、`test/update/update_checker_test.dart` 的断言。
- `lib/update/app_version.dart` 里 `updateRepo` 填真实 GitHub 仓库（默认是占位符）。
