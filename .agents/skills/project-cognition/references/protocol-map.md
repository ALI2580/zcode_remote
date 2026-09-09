# 当前协议地图与历史纠正

协议细节集中维护在 [仓库协议地图](../../../../references/protocol-map.md)，改协议前读取该文件及相应源码，避免在技能里保留第二份过时地图。

必须保持：

- 整个 `lib/protocol` 纯 Dart，使用 observable/平台条件导入，不能恢复旧版 Flutter foundation 依赖。
- Initialize `[200]` 合法，早到 bridge 帧缓冲，旧代次响应丢弃。
- bridge 恢复新建栈并等待 Initialize，然后通知重新订阅；不能把 workspace 后端重连误当 bridge 已恢复。
- 恢复持续到成功或生命周期释放，不恢复旧版 15 次上限。
- Channel body 与其他路径的 13 字节 IPC 帧不可混用；分片预算和 ACK 身份按官方核对。
- 状态双来源合并、分页 logEpoch/游标、重置幂等与使用统计范围分别遵守对应协议。
- 自动额度维护从 V2 +9 起已接入，不能引用旧“尚未接入”记录。真实验证策略见 [开发规则](development-rules.md)。

验证入口：`test/protocol/`、`tooling/protocol_smoke.dart`；具体命令见 [测试与交付](release-and-testing.md)。当前完整任务范围在仓库验收表，不从本地图推定功能完成。
