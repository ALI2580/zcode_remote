# ZcodeRemote

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
- 每台设备独立持有 `ZemoteConnectionParams`，连接互不干扰。
- 凭据安全：`sid/hash` 在 Android 上经 Keystore AES/GCM 加密落盘（`CredentialCipher`）。

## 开发

```bash
flutter analyze    # 零告警门槛
flutter test       # 协议/状态/更新单元测试
flutter run -d chrome
```

## 发版前必改（铁律）

- 版本号三处同步：`pubspec.yaml`、`lib/update/app_version.dart`、`test/update/update_checker_test.dart` 的断言。
- `lib/update/app_version.dart` 里 `updateRepo` 填真实 GitHub 仓库（默认是占位符）。
