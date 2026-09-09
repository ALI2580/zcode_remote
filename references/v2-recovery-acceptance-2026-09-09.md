# V2 附件与恢复阶段验收

日期：2026-09-09。对应全局 Goal 的 B2 / F3，并补充 B1 / D4 回归；其余适用范围继续推进。本阶段不声明完整官方视觉或全局 Goal 完成。

## 构建与代码状态

- APK：`build/artifacts/ZcodeRemote-v2-recovery-dev.apk`，版本 `0.1.0+5`，包名 `com.zcoderemote.zcode_remote.dev`，ARM64 与 x86_64 Flutter 引擎。
- APK SHA-256：`3f831adb11979d2b29038fd521aebe2b7cdf8b234b53e9bc608408b51069e817`。
- 签名证书 SHA-256：`b020bef5c510b8ce9ba783349f4170d178fc279411ca4042287b1c91151a4857`，与前阶段相同；v2 签名验证通过。
- 源码 ZIP：`build/artifacts/ZcodeRemote-v2-recovery-source.zip`，SHA-256 `96bf6520621d85efbd38c20419fcef743c8202aa6ebac0837d0c0f0bb4862a17`。包含 151 个源码/资源/测试/构建文件，不包含本机凭据和密钥。
- 逐文件 manifest：`build/artifacts/ZcodeRemote-v2-recovery-manifest.json`；源码状态 SHA-256 `6ebdd6ccbc43f7e3dbc4be5dfad44cb0517db19164d89c65fb259c28813857e9`。基于 `450164e081549c083ef2bec6c6f6e0635e08513f` 上的未提交工作区，未提交或推送。

## 行为结果

| 场景 | 方法与实际结果 | 证据 |
| --- | --- | --- |
| 静态分析/完整测试 | 零问题；289 项通过 | `build/artifacts/v2-recovery-final-{analyze,tests}.log` |
| Android 编译/签名 | 双 ABI 调试 APK 成功，兼容签名 | `build/artifacts/v2-recovery-final-{build,signature}.log` |
| Channel 上传 | 实际 IPC 编码的 begin/chunk/commit、SHA、取消 abort、非法响应中止、已提交去重、超大预检 | `test/protocol/attachment_transport_test.dart` |
| 草稿恢复 | 同 ID 设备隔离；引用/附件/配置/导航/阅读/面板恢复；发送不确定不重发；写入合并与错误；备份/较新格式保护 | `test/state/recovery_test.dart` |
| 移除竞态 | 恢复读取期间及之前删除设备，不复活旧草稿、附件和导航；先复现再修复 | `build/artifacts/v2-recovery-hydration-{before,after}.log` |
| 路由与失败提示 | 导航等待恢复；系统返回先关闭恢复的面板；保存失败可见，重试不发送 | `test/ui/recovery_navigation_test.dart` |
| 手机原生附件 | `.qa` 系统选择测试文件，私有缓存校验，合成发送拒绝后保存；新进程恢复原引用/文件并预览，零自动提交，显式发送一次 | `build/artifacts/v2-recovery-native-{seed,verify}.log` |
| 平板原生附件 | 使用最终竞态修复后的代码；同上链路通过 | `build/artifacts/v2-recovery-tablet-{seed,verify}.log` |
| 双端覆盖安装 | 竖屏手机 1440×3200 / density522；平板横屏 3392×2400 / density315；两台 versionCode=5、x86_64，安装的 base.apk 均与交付哈希一致 | `build/visual-audit/recovery-qa/installed-apks.json` |
| 产品冷重启 | 手机 ALI 的 bike_refund_group 原任务、平板 ROG 的「比较CLAUDE.md和AGETNS.md差异」各输入一条不同本地标记，后台后 force-stop，再启动：任务与草稿分别恢复，平板面板保持打开 | `build/visual-audit/recovery-qa/{phone,tablet}-v5-{before,after}-restart.png` |
| 清理 | 仅删除本次两条本地标记，发送按钮重新禁用；真实远端未发送消息/终端命令/停止/配置修改 | `build/visual-audit/recovery-qa/{phone,tablet}-v5-clean.png` |

原生附件预览 PNG 位于 `build/visual-audit/recovery-qa/{phone,tablet}-restored-preview.png`。其数据为合成服务，实际 Android 渲染证明系统链路可用；不能代替官方同任务视觉对照。

## 待继续

- 深历史：已保存锚点，仍需在冷启动时补齐历史页并定位未构建消息。
- 中文真实输入法：手机 MuMu 窗口无法激活，测试超时已保留；等待窗口可操作后继续，不计为通过。
- 其余形态、深浅主题/140%/主辅/键盘的最终组合及官方匹配对照；ColorOS16 新页面组合。
- 完整 D/E/F 范围（终端/diff/请求/设置/语音/更新等）继续以全局验收清单跟踪。
