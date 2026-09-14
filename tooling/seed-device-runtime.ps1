param(
  [Parameter(Mandatory = $true)][string]$Target,
  [Parameter(Mandatory = $true)][string]$ObjectivePath,
  [Parameter(Mandatory = $true)][string]$LogPath
)
$ErrorActionPreference = 'Stop'
$raw = Get-Content -LiteralPath $ObjectivePath -Raw
$match = [regex]::Match($raw, 'https://zcode\.z\.ai/remote/v4\?[^)\s]+')
if (-not $match.Success) { throw 'remote link not found' }
$url = $match.Value -replace '\\', ''
$seedPath = Join-Path $env:TEMP 'zcode-a2.3-seed.json'
try {
  @{ZCODE_SEED_DEVICE_URL = $url; ZCODE_SEED_DEVICE_LABEL = 'ROG-STRIX'} |
    ConvertTo-Json -Compress | Set-Content -LiteralPath $seedPath -Encoding UTF8
  & 'D:\SoftWare\Develop\flutter\bin\flutter.bat' test integration_test/seed_device_store_test.dart `
    -d $Target --dart-define-from-file=$seedPath --no-uninstall --reporter compact 2>&1 |
    Tee-Object -FilePath $LogPath
  if ($LASTEXITCODE -ne 0) { throw 'device seed failed' }
} finally {
  if (Test-Path -LiteralPath $seedPath) { Remove-Item -LiteralPath $seedPath -Force }
}
