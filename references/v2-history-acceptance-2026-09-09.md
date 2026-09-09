# V2 长历史与阅读恢复阶段验收

日期：2026-09-09。版本 `0.1.0+6`；D2 的分页与阅读恢复部分、F3 的完整持久恢复链路。本阶段并未完成 D2 的全部消息/工具功能或全局 Goal。

## 安装包与代码状态

- APK：`build/artifacts/ZcodeRemote-v2-history-dev.apk`，`.dev` 包名，ARM64 / x86_64 引擎。
- SHA-256：`5ef6cef49a29fdb0da635d17811e00ca79ff0d419444a9257133e2e0b92614ff`。
- 原兼容证书 SHA-256：`b020bef5c510b8ce9ba783349f4170d178fc279411ca4042287b1c91151a4857`，v2 签名验证通过。
- 160 文件源码 ZIP：`build/artifacts/ZcodeRemote-v2-history-source.zip`，SHA-256 `c77a46180cb05d63b74c6bef498e103587c6cbf08cb529d36e1f44eb53dbb826`。
- 源码状态 SHA-256：`86fa8b5d1af34d70a6b7452db37181a309a62498a4cb0643289550ce8695a068`；同目录 manifest 记录各文件哈希和基线提交。保留全部未提交工作，未提交或推送。
- 两台 MuMu 的安装包已逐字节验证与交付哈希相同，versionCode=6、x86_64：`build/visual-audit/recovery-qa/history-installed-apks.json`。

## 功能与证据

| 范围 | 实际结果 | 证据 |
| --- | --- | --- |
| 官方分页规则 | 按最旧行与全局下界判断；响应需日志代次/游标一致；新日志不混入旧页；无进展停止循环 | `protocol-map.md` 中 LTe/wb/Tb 和 60/200 固定限制；`test/protocol/conversation_test.dart` |
| 阅读恢复 | 按保存 ID 自动读取必要历史页；可取消、失败可重试；日志变化和目标消失有提示；迟到请求不写入已释放页面 | `test/state/conversation_history_test.dart` |
| 实际列表定位 | 1,000 条变高消息中定位未构建目标，构建数少于 100；换宽度、140% 字号后恢复相同可见偏移；流式/分页/折叠不拉走阅读 | `test/ui/conversation_viewport_test.dart` |
| 触屏拖动 | 文字上的拖动确实移动正文；布局完成后再记录锚点，避免旧锚点把列表拉回 | `test/ui/conversation_history_test.dart`；`v2-history-text-drag-{before,after,trace}.log` |
| 原生冷重启 | 手机和平板均从完整合成历史拖动后保存，关闭进程；以只含尾部的新进程启动，读两页后恢复第 450 行及 -84/-104dp 偏移，无发送命令 | `v2-history-{native,tablet}-{seed,verify}.log`；Android 集成记录 |
| 原生像素对照 | 排除顶栏阶段标识后，两端各自正文和 Composer 恢复前后差异均为 0 像素 | `build/visual-audit/recovery-qa/reading-pixel-comparison.json` 及 `*-reading-{seed,verify}.png` |
| 产品真实任务 | 手机 ALI 长回复中拖动后重启，正文保持同位置；平板 ROG 先加载真实历史、滑入旧页再重启，恢复同一段旧消息 | `phone-v6-reading-{before,after}-restart.png`；`tablet-v6-deep-{before,after}-restart.png` |
| 产品位置对照 | 同端、同任务重启前后，所记录的正文矩形均为 0 像素差异；排除了状态栏时间与侧栏动态内容 | `build/visual-audit/recovery-qa/product-reading-comparison.json` |
| 分析/完整测试 | 静态分析零问题，304 项完整测试通过 | `build/artifacts/v2-history-final-{analyze,tests}.log` |
| Flutter 渲染 | 五形态、深浅主题、大字号与面板/菜单等共 33 张 PNG；检查手机浅色、窄屏大字号菜单、平板面板 | `build/v2-history-preview/`；`v2-history-render.log` |
| 构建/协议纯度 | 双 ABI 构建与签名验证通过，独立 Dart 协议 smoke 通过 | `v2-history-final-{build,signature}.log`；`v2-history-protocol-smoke.log` |

本次产品验证仅进行了阅读、分页、客户端重启及本地阅读状态保存，没有发送消息、修改远程配置、停止任务或执行终端命令。验证后已使用「回到最新」恢复原阅读状态。QA 应用使用独立包名和合成远端。

以上前后位置对照验证的是恢复行为，不是官方页面视觉一致性。官方同任务/同主题完整对照、中文软键盘与 ColorOS16 系统组合，以及其余 D/E/F 功能仍以全局清单继续推进。
