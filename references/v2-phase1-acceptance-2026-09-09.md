# V2 Goal 阶段交付与验收证据（2026-09-09）

本阶段关闭侧栏、Composer 输入来源、用量和底层连接中的多处明确缺陷，交付 `0.1.0+4`。**全局 Goal 未完成，A/B/C 的完整官方对照与组合验收也尚未全部通过。** 后续仍按 [全局清单](v2-goal-acceptance.md) 完成所有适用范围，不将此 APK 当作最终交付。

## 可定位的安装包与代码

| 项目 | 实际结果 |
| --- | --- |
| APK | `build/artifacts/ZcodeRemote-v2-goal-phase1d-dev.apk` |
| 版本 / 包名 | `0.1.0+4` / `com.zcoderemote.zcode_remote.dev` |
| Flutter 引擎 ABI | `arm64-v8a`、`x86_64`；两台 MuMu 本次显式安装 x86_64 |
| APK SHA-256 | `373da487a8e4cee5fdbfc28019fce8494a4b4cf1b59a54717d624d80eea0926b` |
| 签名 | APK Signature Scheme v2 验证通过；证书 SHA-256 `b020bef5c510b8ce9ba783349f4170d178fc279411ca4042287b1c91151a4857`，与此前 `.dev` 包相同 |
| 基础提交 | `450164e081549c083ef2bec6c6f6e0635e08513f` 加全部保留的工作区改动；本阶段未提交或推送 |
| 源码快照 | `build/artifacts/ZcodeRemote-v2-goal-phase1d-source.zip`，含本次构建源代码、资源、测试与依赖锁；不含设备凭据、签名私钥或本机配置 |
| 源码状态 SHA-256 | `5c79c0cb24059ad74b0fc90e78d058d198ce92a8958d1ce6f40ca4063875f18e`；逐文件清单见同目录 `ZcodeRemote-v2-goal-phase1d-manifest.json` |
| 源码 ZIP SHA-256 | `ad6cc9dc4cf4ffd874caf48cae14410d47e3e5f3f3bc0dad2597a4dae102d8d5` |

## 已解决的问题及行为证据

| 需求 / 问题 | 官方依据 | 修正与验证 | 证据 |
| --- | --- | --- | --- |
| 文件候选一直超时 | 官方 RPC `X/Ch/Sh` 物理帧限制、`a2t` 完整桥接身份、`PIe` 文件目录请求 | 接收不再误用本地发送的 512 KiB 切片大小；ACK 携带完整 generation/recoveryId。修复前同一 ROG 目录 20/60 秒超时，修复后返回 6,180 个文件/目录、15 技能、8 插件 | `test/protocol/rpc_transport_test.dart`；`official-connection-probe-ROG-STRIX-before-rpc-fix.json` 与 `official-connection-probe-ROG-STRIX.json`；`v2-goal-ROG-rpc-fixed-probe.log` |
| 切回后“已连接”但会话握手超时 | 官方 `Z4t T → C → P` | 重开失效桥接并等 Channel Initialize；不把 workspace 后端重连当作旧 Channel 复活。旧桥帧丢弃；旧 hello/失败不覆盖新握手。恢复继续到成功/释放，仅作用于失效工作区 | `bridge_recovery_test.dart`、`conversation_handshake_test.dart`、`v2-goal-recovery-tests.log`；新版 MuMu 会话/用量读取正常，更多真实断网组合仍需继续 |
| 协议目录仍依赖 Flutter | Goal 架构约束 | 纯 Dart `ProtocolNotifier/ValueSignal` 和原生/Web 条件平台识别；完整协议可以由独立 Dart VM 导入并运行投影 | `tooling/protocol_smoke.dart`；`v2-goal-phase1d-protocol-smoke.log` |
| 侧栏标题、置顶、归档和未读反复被旧数据覆盖 | 官方 `CCt/ECt/KEt` | 完整索引省略标志表示 false；按更新时间合并，旧查询不撤销较新的成员状态。独立置顶、项目/时间线、排序、折叠未读点、菜单确认/失败、切换状态与去重 | `workspace_catalog_test.dart`、`task_navigation_test.dart`；两台真实侧栏 |
| 新任务额度门控、账户缓存、Start 假 0% | 官方 `O2e/BF/NZe/ES`；Goal 缺失数据规则 | 无上下文仍显示适用套餐；API Key/非匹配来源不请求。重连清缓存，源核查失败不刷新旧账户，迟到响应隔离，空账户与网络失败区分，Start 缺值显示 `--` | `composer_usage_test.dart`、`entitlement_test.dart`、`composer_features_test.dart` |
| 上下文、套餐与 MCP 混淆风险 | 官方 `NZe/AZe/NF/cZe/fZe` | 上下文总量/字符来源、GLM 套餐、MCP aggregate 独立。真实 ROG 展示 5 小时 67%、每周 94%、工具 95%、MCP 100%（本次截图时点）；缺 breakdown 不合成分类 | `tablet-ROG-phase1d-usage.png`；假数据布局/缺值回归 |
| 加号、引用、首发与附件 | 官方 `gRe/UA/Yx/Xx/Qx/gke/TTe/BAe` | 真目录候选、作用域失效、文件优先排序/路径关键词、选择与焦点、原子删除和序列化；附件首发一次、取消、失败重试、超时不重发、同 ID 设备隔离 | `composer_references_test.dart`、`composer_features_test.dart`、`composer_attachments_test.dart`；手机实际引用/选择器打开取消 |
| 441px 时模型名提前折叠 | 官方 `chat-composer-region @container/composer` 位于带 padding 的 surface 外 | LayoutBuilder 查询外层 composer region，工具条内部仍按实际可用宽度限制文本；维持 384/576/672，主辅独立。窄模式图标也保留完全访问橙色 | `surface padding does not move...` 回归；ALI 同任务官方图与新版手机图 |
| 图标错误与英文大字号溢出 | 官方图标模块真实转导出；官方 CSS | 信息/删除图标不再错误解析；补向下箭头；修复侧栏长文案与 MCP 行溢出 | `tooling/extract_shell_icons.py --check`；五形态渲染与实际用量图 |

以上测试文件位于 `test/state`、`test/ui` 或 `test/protocol`；日志与 JSON 探针结果位于 `build/artifacts`。测试写入均使用合成数据或假传输；没有向真实桌面发送消息、停止任务、执行终端命令、删除任务或修改模型配置。

## MuMu 环境及实际操作

每次部署前重新核实了实例配置中的名称和转发端口，并使用显式 `adb -s`。实例 2 是竖屏手机，实例 3 是平板横屏。初始两台均从复制的记录恢复 ALI，已在平板释放该连接并选中 ROG-STRIX。通过保存的 machineId 与原链接 mid 匹配，并核对实际工作区目录，避免仅凭可编辑显示名认定身份。

| 实例 | 远端 / 原显示名 | 本轮参数 | 安装结果 |
| --- | --- | --- | --- |
| 竖屏手机 | ALI / 公司 | `127.0.0.1:16448`；1440×3200，522dpi，rotation 0；应用约 441×956dp；API 32 | `install -r --abi x86_64` 成功；versionCode 4；更新时间 2026-09-09 03:04:30；已启动、连接及读取会话 |
| 平板横屏 | ROG-STRIX / 测试 | `127.0.0.1:16480`；实际横屏 3392×2400，315dpi，rotation 1；应用约 1723×1195dp；API 32 | 同一 APK 覆盖成功；versionCode 4；相同更新时间；会话及真实 GLM/MCP 用量读取成功 |

环境原始汇总：`build/visual-audit/goal-2026-09-09/phase1d-android-environment.json`。设备记录保持加密，未卸载、清除应用数据或删除已保存设备。其他连接中的实体设备未操作。

| 场景 | 操作 / 预期 | 实际与状态 | 截图 |
| --- | --- | --- | --- |
| 手机会话与窄栏 | 打开 ALI 的 bike_refund_group 当前已有任务，检查正文、composer 和图标 | 读取正常，441dp 下显示模型名、思考条与橙色访问图标；本场景通过，完整像素一致性未通过 | `phone-ALI-phase1d-task.png` |
| 手机加号与引用 | 加号打开 @ / / / $ / 附件；选择真实候选，应回到草稿焦点且不发送 | 真实候选读取、选择、焦点与原子移除在本轮安装版本中实测；4 版再核菜单与选择器；排序/迟到/组合输入由同源回归覆盖 | `phone-ALI-phase1d-plus.png`；`phone-ALI-phase1c-reference-selected.png`（3 版选中记录） |
| Android 文件选择器取消 | 打开系统选择器，再按返回取消，应不创建附件或发送输入 | 4 版打开/取消正常，返回同一任务，发送保持禁用；读取文件字节、上传/发送实机链路仍待使用合成远端验证 | `phone-ALI-phase1d-file-picker.png`、`phone-ALI-phase1d-picker-cancel.png` |
| 平板用量 | 打开 ROG 已有 GLM 任务，点击用量入口，应分开展示上下文和套餐/MCP | 数据及重置时间正常，MCP 独立行，信息图标已修正；读取场景通过 | `tablet-ROG-phase1d-usage.png` |
| 中文软键盘 | 在手机临时启用硬键盘连接时显示 IME，聚焦空草稿 | 搜狗 IME 报告 mInputShown=true，但当前 MuMu 未呈现软键盘占用区；仅验证直接按键进入草稿，不能作为中文组合/候选确认验收。已删除测试字母并恢复原设置 0 | `phone-ALI-phase1d-keyboard.png`、`phone-ALI-phase1d-ime-input.png`；待继续 |

## 渲染与官方比较

- `flutter analyze --no-pub`：零问题。`flutter test --no-pub --reporter expanded`：267 项全部通过。日志为 `v2-goal-phase1d-analyze.log`、`v2-goal-phase1d-tests.log`。
- `flutter build apk --debug --no-pub --target-platform android-arm64,android-x64` 成功；`v2-goal-phase1d-build.log`、`v2-goal-phase1d-signature.log`。
- 当前代码生成 33 张真实 Flutter PNG：`build/v2-goal-phase1d-preview/`，五形态、深浅主题、大字号及主辅/菜单。它们是合成数据渲染回归，不代替官方同数据验收。
- 官方对照均按单远端串行持有连接：先保存应用画面并停止对应客户端进程，确认没有 PID/自动重连，再打开官方；完成后关闭官方 tab、恢复浏览器尺寸，再启动应用。另一台连接不同远端继续工作。
- `official-ALI-light-task-441.png`：同一 ALI 任务、浅色、441×956 CSS px、正文末尾。此前据此发现 composer 容器位置错误，已修正；顶栏结构、正文排版、反馈/时间行、浮层与完整逐像素对齐仍有差异。
- `official-ROG-dark-1723.png`：ROG 真实页面，1723×1195 CSS px，但任务和主题与当时应用截图不同，仅作结构依据，不作成对像素评分。`official-ALI-dark-441.png` 是官方手机任务总览，不能冒充会话对照。
- 浏览器 DOM/AX 读取经常需要约 42 秒，早期 30 秒调用超时。直接 screenshot 与延长单次观察窗口可取得真实图；未据超时推断链接失效。
- Android UI dump 可能退出成功却未写新树，现使用每次独立路径防止复用旧树。早期 `*-coldstart.png` 黑屏/启动中截图保留为过程证据，不算成功画面。

## 后续仍需完成

全局清单全部保留。优先继续 A/B/C 完整原生附件及菜单/输入/字体/主题/主辅面板组合与官方同态对照；再完成 D 的顶栏/完整审查终端/交互请求与队列剩余操作、E 全量远控适用设置及账户供应商插件管理、F 离线语音/更新安装/进程重启恢复。ColorOS 16 既有上岛确认继续有效，新 V2 页面与真机返回/折叠/键盘的组合验证仍待完成。
