# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-09-08

### Added
- **全新项目脚手架**：clean-room 协议复刻，非 fork。继承 Zemote 的纯 Dart 协议栈（relay 配对 / rpc 帧 / Channel / Conversation V4，120 个测试锚定行为）与官方 Web 客户端逆向知识库。
- **多设备管理**：DeviceStore 支持添加（粘贴远程控制链接）、重命名、移除、最近使用排序；每台设备独立持有连接参数；Android 上 sid/hash 凭据经 Keystore AES/GCM 加密落盘。
- **官方 UI 基础体系**：ZInk 调色板（官方 CSS 变量直译）、ZRadius 圆角表、多设备首页壳。
- **官方资产抓取**：完整下载 /remote/v4 的 CSS（384KB）与 JS bundle（4.8MB）存档，整理出 `references/official-styles.md`（CSS 体系规格）、`references/official-i18n.md`（595 个 i18n 键索引）、`references/official-web-ui.md`（mention 触发/六类目/序列化格式/composer DOM 结构等逻辑解密）。
- **GitHub Actions CI**：push 触发 analyze + test + web 冒烟；tag `v*` 触发三 ABI 签名 APK 构建 + MD5 + Release 上传。

### Changed
- **更新检测机制**：复用 GitHub Releases 检查（版本号三处同步：pubspec.yaml / app_version.dart / update_checker_test.dart），仓库指向 `ALI2580/zcode_remote`。
