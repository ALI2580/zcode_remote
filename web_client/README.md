# ZcodeRemote Web 运行验证版（M0）

**历史实验，已停止作为产品路线。** 最新决策为纯 Flutter Android 应用。本目录和官方资源清单仅保留作参考，不打包进 APK、不纳入当前产品 CI。

本目录是已认可设计进入代码的第一个验证版本。使用本地缓存的官方 Web 构建，保留官方任务栏、头像小菜单、完整设置和工作页面。当前 Flutter 主入口尚未替换。

## 本次检查结果

- 入口基线：83 个公开资源，8,372,671 bytes；主脚本与旧参考副本 SHA-256 一致。
- 16 项自动测试通过，含 URL/凭据轮换、页面复用、存储隔离、启动顺序、无效来源拒绝、本地 HTTP 路由边界；已接入 CI。
- 本地首页、带启动隔离脚本的 runtime 入口和主 JS 模块均返回 HTTP 200。
- 带 `Origin: http://127.0.0.1:4173` 的官方 `/ws` 升级请求返回 101。这只验证连接入口，不代表设备已经配对；探针没有发送凭据或 RPC。
- 真实浏览器验收未完成：本轮浏览器工具因本机 Codex 配置解析错误无法启动（`config.toml` 的 features 字段类型错误）。未改动该外部配置，也未把 HTTP/单元测试结果替代视觉和真实配对验证。

```powershell
cd D:\WorkSpace\ZcodeRemote\web_client
npm run sync:official
npm test
npm run dev
```

打开 `http://127.0.0.1:4173`，粘贴远程链接。添加多台设备后，从官方左栏底部的「切换设备」选择另一台；已创建的 iframe 在切换时保留。

## 本阶段边界

- 设备记录及链接仅保留在当前 JS 页面内，不写进资源缓存或 localStorage。刷新外层页面需要重新添加。
- 每台设备的官方页面在执行入口前安装独立 localStorage/sessionStorage 命名空间，`clear()` 和存储事件按设备过滤。
- 源码里保留的官方头像 trigger 和 settings 页面全部直接运行，客户端不维护一份删减版设置；当前官方 Web 的能力门控保持原样。
- 只在官方侧栏 footer 增加设备按钮，不修改压缩 JS，不往任务 header 加控件。
- 开发服务器只绑定 `127.0.0.1`，只读允许的本地前端文件及固定官方公开资源路径，不转发凭据、会话或任意代理请求，也不记录请求 URL。
- 首次启动预缓存 83 个入口资源；懒加载资源在访问时按精确资源路径下载并记录 SHA-256。可用 `node scripts/dev-server.mjs --offline` 检查已缓存场景是否完整。
- 缓存位于仓库已忽略的 `build/official-web`。`references/official-web-baseline.json` 是入口资源基线，尚不是全部懒加载资源的离线发行清单。
- 本阶段是功能隔离，不宣称同源 iframe 是互不信任代码之间的安全边界。后续扩展 IndexedDB/Worker 等存储机制时必须补作用域和测试。

## 尚待端到端验收

- 本地 origin 的真实配对、官方头像菜单/全部设置的显示与操作。
- 两台真实桌面同时连接；当前只提供一台真实设备。
- 所有五种形态的官方界面视觉对照、断网恢复、隐藏 iframe 和手机后台行为。
- Android WebView 宿主、Keystore 持久化、更新、离线语音及客户端偏好设置。

官方设置源代码清单见 `references/official-settings-catalog.json`；15 个定义、默认 Web 门控保留 13 个（定时任务和 Computer Use 受原始门控影响）。不能强行展示桌面专属开关并让它们空运行。

不要提交设备链接、配对参数或从运行页导出的完整 HTML/日志。此验证版不适合部署为公开服务。
