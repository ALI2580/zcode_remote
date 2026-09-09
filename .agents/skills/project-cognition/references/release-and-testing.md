# PowerShell 测试、原生 QA 与阶段交付

适用于当前 ZcodeRemote V2。命令是操作示例，按当前任务选择执行，不意味着自动获得安装、远端写入或正式发布授权。2026-09-09 已验证工具链为 Flutter 3.47.2 / Dart 3.13.2、Android build-tools 36.0.0；换机器先核对路径与版本。

## 1. 初始化与选择最短验证路径

```powershell
$RepoDir = 'D:\WorkSpace\ZcodeRemote'
$Flutter = 'D:\SoftWare\Develop\flutter\bin\flutter.bat'
$Dart = 'D:\SoftWare\Develop\flutter\bin\dart.bat'
$Adb = 'D:\Software\Develop\platform-tools\adb.exe'
$BuildTools = 'D:\Software\Develop\Jetbrains\AndroidSDK\build-tools\36.0.0'
$Phone = '127.0.0.1:16448'
$Tablet = '127.0.0.1:16480'
Set-Location -LiteralPath $RepoDir
git status --short
git diff --stat
```

地址是本轮基线，不是永久端口。先用 MuMu 的 extra_config.json / playerName 匹配“竖屏手机”和“平板横屏”，再核对 vm_config.json 的 ADB 映射。配置根目录当前为 `D:\SoftWare\Common\Mumu\emulator\MuMuPlayer-12.0\vms`。

| 修改内容 | 最短相关集合（仓库相对路径） |
| --- | --- |
| 协议/重连 | test/protocol + tooling/protocol_smoke.dart |
| 侧栏状态 | test/state/workspace_catalog_test.dart、app_sessions_test.dart、test/ui/task_navigation_test.dart |
| 配置/发送/队列 | test/state/composer_controller_test.dart、test/protocol/composer_transport_test.dart、test/ui/composer_ui_test.dart |
| 引用/IME | test/state/composer_references_test.dart、test/ui/composer_features_test.dart |
| 附件/恢复 | test/state/composer_attachments_test.dart、test/protocol/attachment_transport_test.dart、test/state/recovery_test.dart |
| 额度/重置 | test/state/composer_usage_test.dart、plan_resets_test.dart、test/ui/plan_reset_dialog_test.dart |
| 统计 | test/state/usage_statistics_test.dart、test/ui/usage_page_test.dart |
| 阅读/辅助功能 | test/ui/conversation_history_test.dart、conversation_viewport_test.dart、markdown_accessibility_test.dart |
| 返回/通知 | test/ui/predictive_back_test.dart、notification_navigation_test.dart、test/notifications |

```powershell
# pubspec/lock 未变化且依赖已就绪时可用 --no-pub；否则先 flutter pub get。
& $Flutter test --no-pub test/state/workspace_catalog_test.dart test/state/app_sessions_test.dart test/ui/task_navigation_test.dart --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'focused tests failed' }
& $Dart run tooling/protocol_smoke.dart
if ($LASTEXITCODE -ne 0) { throw 'protocol smoke failed' }
```

先复现、修复、跑相关回归；阶段收尾再完整检查。已通过后，只因新改动或未解决疑点扩测，不无条件重复全量构建。

## 2. 完整检查与字体化渲染

每个阶段使用新的日志/截图目录，避免覆盖旧证据。同一工作区的 Flutter/Gradle 构建和原生测试串行运行。

```powershell
$Stage = 'next-stage'
$Evidence = Join-Path $RepoDir 'build\artifacts'
New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
& $Flutter analyze *> "$Evidence\$Stage-analyze.log"
if ($LASTEXITCODE -ne 0) { throw 'analyze failed' }
& $Flutter test --reporter expanded *> "$Evidence\$Stage-tests.log"
if ($LASTEXITCODE -ne 0) { throw 'tests failed' }
& $Dart run tooling/protocol_smoke.dart *> "$Evidence\$Stage-protocol-smoke.log"
if ($LASTEXITCODE -ne 0) { throw 'protocol smoke failed' }
```

```powershell
$env:ZCODE_TEST_FONT = 'C:/Windows/Fonts/msyh.ttc'
$env:ZCODE_TEST_MONO_FONT = 'C:/Windows/Fonts/consola.ttf'
$env:ZCODE_TEST_ICON_FONT = 'D:/SoftWare/Develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
$env:ZCODE_UI_CAPTURE_DIR = "build/v2-$Stage-preview"
& $Flutter test test/ui/v2_visual_test.dart test/ui/usage_page_test.dart --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'render tests failed' }
```

覆盖五形态（常用宽度 344/390/720/834/1180）、深浅、中英、100/140%，再按功能补键盘/主辅/错误/空态。打开代表图实际检查；这些入口不是所有页面所有状态的完整矩阵。实际官方比较还需同远端、任务、滚动、主题、字号、等效可用宽度。

## 3. 设备预检与独立 QA

```powershell
foreach ($Target in @($Phone, $Tablet)) {
    Write-Output $Target
    & $Adb -s $Target shell wm size
    & $Adb -s $Target shell wm density
    & $Adb -s $Target shell dumpsys display | Select-String 'mCurrentOrientation'
    & $Adb -s $Target shell dumpsys package com.zcoderemote.zcode_remote.dev |
        Select-String 'versionCode=|versionName='
}
```

不要用 user_rotation 设置值代替实际方向。区分截图物理像素、Flutter logical 像素与浏览器 CSS 像素。确认操作者、连接身份及独占状态后再操作。

```powershell
$env:ZCODE_ANDROID_QA = 'true'
try {
    & $Flutter test integration_test/task_management_test.dart -d $Phone --no-uninstall --reporter expanded *> "$Evidence\$Stage-native-phone.log"
    if ($LASTEXITCODE -ne 0) { throw 'phone QA failed' }
    & $Flutter test integration_test/task_management_test.dart -d $Tablet --no-uninstall --reporter expanded *> "$Evidence\$Stage-native-tablet.log"
    if ($LASTEXITCODE -ne 0) { throw 'tablet QA failed' }
} finally {
    Remove-Item Env:ZCODE_ANDROID_QA -ErrorAction SilentlyContinue
}
```

其他按需入口：

- `usage_controls_test.dart`：合成额度机会、消费确认、自动完成/已读及控件。
- `usage_statistics_test.dart`：更多、范围、图表明细、主题/字号和返回。
- `android_system_test.dart`：读取其 guard 后验证系统能力。
- `attachment_recovery_test.dart`：`RECOVERY_QA_PHASE=seed/verify`，还需规定的 fixture/系统选择器步骤。
- `reading_recovery_test.dart`：`READING_QA_PHASE=seed/verify`，分阶段保留 QA 数据验证进程重建。

每个入口先核对包名 guard 和副作用。不能把 seed/verify 合并成清数据后的普通循环，也不能在 `.dev` 上运行这些测试。测试后仅停止指定 QA 包：

```powershell
& $Adb -s $Phone shell am force-stop com.zcoderemote.zcode_remote.qa
& $Adb -s $Tablet shell am force-stop com.zcoderemote.zcode_remote.qa
```

## 4. 产品构建、包名/签名/ABI 核对

版本变更同步 `pubspec.yaml`、`lib/update/app_version.dart`、`test/update/update_checker_test.dart`，并更新 CHANGELOG。当前 CI 已含 Android debug ARM64 编译；Kotlin/Gradle 修改仍须本地实际构建和相应安装验证。

```powershell
Remove-Item Env:ZCODE_ANDROID_QA -ErrorAction SilentlyContinue
& $Flutter build apk --debug --target lib/main.dart --target-platform android-arm64,android-x64 *> "$Evidence\$Stage-build.log"
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
$Apk = Join-Path $RepoDir 'build\app\outputs\flutter-apk\app-debug.apk'
$Badging = & "$BuildTools\aapt.exe" dump badging $Apk
$BadgingText = $Badging -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0 -or $BadgingText -notmatch "package: name='com.zcoderemote.zcode_remote.dev'") {
    throw 'unexpected product package'
}
$Badging | Select-String 'package:|native-code'
& "$BuildTools\apksigner.bat" verify --print-certs $Apk
if ($LASTEXITCODE -ne 0) { throw 'signature verification failed' }
Get-FileHash -Algorithm SHA256 -LiteralPath $Apk
```

签名需与待覆盖的开发包/冻结记录比较，不能把旧正式版证书当作开发包证书。只查看公开证书摘要，不输出 keystore 私钥或密码。旧仓库名、CI Secrets 配置和正式发布流程需现场核对，技能不自动执行推送/tag/Release。

aapt 可能因依赖列出 32 位 ABI，必须检查实际 Flutter 引擎：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
try {
    $Engines = @($Zip.Entries.FullName | Where-Object { $_ -match '^lib/[^/]+/libflutter\.so$' })
    $Engines
    foreach ($Required in @('lib/arm64-v8a/libflutter.so', 'lib/x86_64/libflutter.so')) {
        if ($Engines -notcontains $Required) { throw "missing engine: $Required" }
    }
} finally {
    $Zip.Dispose()
}
```

## 5. 覆盖安装、只读启动与读回哈希

仅在已授权验证设备上执行，先保存当前任务/阅读/草稿/主题。下面显式选择手机，平板需显式换目标。遇到安装失败先查原因，不改成卸载清数据。

```powershell
$Target = $Phone
& $Adb -s $Target shell am force-stop com.zcoderemote.zcode_remote.dev
& $Adb -s $Target install -r --abi x86_64 $Apk
if ($LASTEXITCODE -ne 0) { throw 'install failed' }
& $Adb -s $Target shell am start -n com.zcoderemote.zcode_remote.dev/com.zcoderemote.zcode_remote.MainActivity --ez quotaReadOnlyAudit true
if ($LASTEXITCODE -ne 0) { throw 'launch failed' }
```

`--abi x86_64` 针对当前 MuMu；ARM64 真机按其实际 ABI 安装。audit 只阻止额度授予/消费/已读三个 RPC，不保护其他写操作；普通启动自动维护额度。不要将这个开关视为全应用安全隔离。

```powershell
$PackagePaths = @(& $Adb -s $Target shell pm path com.zcoderemote.zcode_remote.dev)
if ($LASTEXITCODE -ne 0) { throw 'package lookup failed' }
$BasePaths = @($PackagePaths | Where-Object { $_.Trim() -match '/base\.apk$' })
if ($BasePaths.Count -ne 1) { throw 'expected one installed base APK' }
$RemoteApk = $BasePaths[0].Trim() -replace '^package:', ''
$InstalledApk = Join-Path $Evidence "$Stage-installed-base.apk"
& $Adb -s $Target pull $RemoteApk $InstalledApk
if ($LASTEXITCODE -ne 0) { throw 'APK readback failed' }
$ExpectedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Apk).Hash
$InstalledHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $InstalledApk).Hash
if ($ExpectedHash -ne $InstalledHash) { throw 'installed APK does not match' }
```

读回后仍需启动和关键交互验证；安装 Success 不能证明正确文件和流程均已验收。

## 6. 截图、专项诊断、只读探针

```powershell
python tooling/android_ui_probe.py --adb $Adb --target $Tablet --capture "build/visual-audit/$Stage/tablet-ROG-ready.png"
if ($LASTEXITCODE -ne 0) { throw 'UI capture failed' }
```

先看本次截图/节点再点；该工具只输出带文字/描述的节点，空结果需结合截图和前台包判断。测试驱动器运行时不并发扫同一 Flutter 树。辅助功能专项单独构建诊断入口：

```powershell
$env:ZCODE_ANDROID_QA = 'true'
try {
    & $Flutter build apk --debug --target tooling/accessibility_probe.dart --target-platform android-x64
    if ($LASTEXITCODE -ne 0) { throw 'diagnostic build failed' }
} finally {
    Remove-Item Env:ZCODE_ANDROID_QA -ErrorAction SilentlyContinue
}
```

诊断会覆盖通用 app-debug.apk 路径；不允许随后把该文件当产品交付，必须重新以 lib/main.dart 构建并核对包名。诊断 APK 含故意复现 SDK 问题的对照页面。

真实只读探针是 `tooling/remote_feature_probe.dart`，需要运行时安全注入 `ZEMOTE_PROBE_URL`；不得把链接写入此文档或脚本。窄模式为 `ZCODE_PROBE_CONNECTION_ONLY` / `ZCODE_PROBE_FILES_ONLY` / `ZCODE_PROBE_STATISTICS_ONLY`，一次只选与问题相关的模式，另设 `ZCODE_PROBE_ALIAS`。同端应用/浏览器先释放，探针结束释放连接并清除临时凭据变量。

## 7. 阶段冻结与完成标准

```powershell
# $Stage 必须是新的小写字母/数字/连字符阶段标识。
if (-not $ExpectedHash) { throw 'verify and read back the product APK first' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Apk).Hash -ne $ExpectedHash) {
    throw 'APK changed since verification; rebuild and verify the product entrypoint'
}
$StageApk = Join-Path $Evidence "ZcodeRemote-v2-$Stage-dev.apk"
if (Test-Path -LiteralPath $StageApk) { throw 'choose a new stage; do not overwrite evidence' }
Copy-Item -LiteralPath $Apk -Destination $StageApk
python tooling/freeze_stage.py --stage $Stage
if ($LASTEXITCODE -ne 0) { throw 'source freeze failed' }
```

freeze_stage 生成源码 ZIP、逐文件 manifest 和 SHA 文件，同阶段重新核验只允许源码与 APK 相同。根目录文档另行保存并链接；不要静默覆盖不同代码的旧阶段。

交付记录写明官方依据、行为/视觉/原生证据、APK 包名/版本/签名/哈希、实际安装读回及代码状态。当前阶段通过不能关闭仍有必需项未完成的全局目标。平台条件不足单列，明确哪些已验证、哪些没有。
