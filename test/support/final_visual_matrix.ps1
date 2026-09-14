param(
    [string]$RunId = 'replay',
    [switch]$SkipRun,
    [string]$ExistingRoot
)

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$wrapper = Join-Path $repo 'build/visual-audit/ui-global-20260912-resume/run-flutter-locked.ps1'
$root = if ($ExistingRoot) {
    (Resolve-Path $ExistingRoot).Path
} else {
    Join-Path $repo "build/visual-audit/ui-global-20260912-resume/final-visual-harness/$RunId"
}
$manifest = Join-Path $root 'manifest.tsv'

if (Test-Path -LiteralPath $manifest) {
    throw "Evidence already exists: $manifest"
}
New-Item -ItemType Directory -Force -Path $root | Out-Null

$head = (& git -C $repo rev-parse HEAD).Trim()
$sourceIdentity = "working-tree HEAD $head; no product source mutation by this harness"

$cases = @(
    [pscustomobject]@{
        Id = 'u01-search-behavior'
        Paths = @('test/ui/workspace_search_ui_test.dart', 'test/ui/search_repeat_acceptance_review_test.dart')
        Capture = $false
        Condition = 'U01 search result path, repeat highlight, shell scope'
        Fixture = 'synthetic search transport and task data'
        Boundary = 'no official same-data visual; no native device'
    },
    [pscustomobject]@{
        Id = 'u03-u04-behavior'
        Paths = @('test/ui/task_navigation_test.dart', 'test/ui/workspace_flow_test.dart')
        Capture = $false
        Condition = 'U03/U04 shell animation and A-B-A/device/workspace switching'
        Fixture = 'synthetic multi-device and multi-workspace sessions'
        Boundary = 'behavior only here; existing animation frames remain historical evidence'
    },
    [pscustomobject]@{
        Id = 'v2-visual'
        Paths = @('test/ui/v2_visual_test.dart')
        Capture = $true
        Condition = 'main/side; 344/390/720/834/1180; light/dark; zh100/en140; menu/pending/failure/context/settings'
        Fixture = 'synthetic official-schema conversation and settings state'
        Boundary = 'synthetic content; no official same-data comparison; no native/foldable confirmation'
    },
    [pscustomobject]@{
        Id = 'u02-device-menu'
        Paths = @('test/ui/sidebar_menu_test.dart')
        Capture = $true
        Condition = 'wide long list, short viewport, anchored device switcher'
        Fixture = 'synthetic device list'
        Boundary = 'synthetic devices; no native safe-area confirmation'
    },
    [pscustomobject]@{
        Id = 'u05-tool-chat'
        Paths = @('test/ui/tool_chat_acceptance_review_test.dart')
        Capture = $true
        Condition = 'ChatPage inline diff at 390 zh and 1180 en140'
        Fixture = 'synthetic Edit tool payload'
        Boundary = 'current replay fails before diff assertion; no screenshot accepted'
    },
    [pscustomobject]@{
        Id = 'u06-turn-summary'
        Paths = @('test/ui/turn_summary_acceptance_review_test.dart')
        Capture = $true
        Condition = '390 zh and 1180 en140 turn summary with file changes'
        Fixture = 'synthetic authoritative turnHeader.fileChanges'
        Boundary = 'synthetic content; no official same-data comparison'
    },
    [pscustomobject]@{
        Id = 'u07-u08-voice'
        Paths = @('test/ui/voice_composer_acceptance_review_test.dart')
        Capture = $true
        Condition = 'missing voice model composer recovery plus model lifecycle behavior'
        Fixture = 'synthetic model manager and missing-model state'
        Boundary = 'no microphone or native audio capture; no real download'
    },
    [pscustomobject]@{
        Id = 'u07-u08-model-manager'
        Paths = @('test/ui/voice_model_manager_test.dart', 'test/ui/voice_input_button_test.dart')
        Capture = $false
        Condition = 'voice model download cancellation/retry and enable/disable/delete'
        Fixture = 'synthetic model manager'
        Boundary = 'behavior only; no real download or microphone'
    },
    [pscustomobject]@{
        Id = 'u09-u10'
        Paths = @('test/ui/composer_menu_test.dart')
        Capture = $true
        Condition = 'mode menu and provider/model submenus, wide and narrow bounds'
        Fixture = 'synthetic composer configuration and provider catalog'
        Boundary = 'synthetic candidates; no official same-data visual comparison'
    },
    [pscustomobject]@{
        Id = 'u11-terminal'
        Paths = @('test/ui/terminal_synthetic_service_test.dart')
        Capture = $true
        Condition = 'terminal render plus resize/input/exit/dispose; keyboard control/navigation bytes'
        Fixture = 'synthetic terminal channel service'
        Boundary = 'no native IME screenshot; no real remote terminal'
    },
    [pscustomobject]@{
        Id = 'u11-terminal-keyboard'
        Paths = @('test/ui/terminal_keyboard_test.dart')
        Capture = $false
        Condition = 'keyboard control/navigation bytes with focused terminal input'
        Fixture = 'synthetic terminal client'
        Boundary = 'behavior only; no native IME screenshot'
    },
    [pscustomobject]@{
        Id = 'u12-side-panel'
        Paths = @('test/ui/side_panel_test.dart')
        Capture = $true
        Condition = 'main and side panel at 1180 plus narrow side panel'
        Fixture = 'synthetic task, summary, and side-chat state'
        Boundary = 'synthetic content; no official same-data visual comparison'
    },
    [pscustomobject]@{
        Id = 'u13-settings-embed'
        Paths = @('test/ui/settings_embed_test.dart')
        Capture = $true
        Condition = '1180 zh usage and 344 en140 devices embedded settings'
        Fixture = 'synthetic settings store and usage/device state'
        Boundary = 'synthetic data; top appbar test-font block remains visible'
    },
    [pscustomobject]@{
        Id = 'u14-model-editor'
        Paths = @('test/ui/model_editor_visual_acceptance_review_test.dart')
        Capture = $true
        Condition = '344 en140 provider editor connection error'
        Fixture = 'synthetic provider connectivity failure'
        Boundary = 'synthetic endpoint; no real provider request'
    },
    [pscustomobject]@{
        Id = 'u15-connection'
        Paths = @('test/ui/connection_review_capture_test.dart')
        Capture = $true
        Condition = 'main/settings, 390/1180, zh/en, healthy/interrupted/failed/pair-again'
        Fixture = 'synthetic degraded/recovery state machine'
        Boundary = 'no real network toggle, sleep, or native device'
    }
)

$rows = [System.Collections.Generic.List[object]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($case in $cases) {
    $captureDir = if ($case.Capture) { Join-Path $root $case.Id } else { $null }
    $log = Join-Path $root "$($case.Id).log"
    $caseFailed = $false
    if (-not $SkipRun) {
        if ($case.Capture) {
            $env:ZCODE_UI_CAPTURE_DIR = $captureDir
            $env:ZCODE_TEST_FONT = 'C:/Windows/Fonts/msyh.ttc'
            $env:ZCODE_TEST_MONO_FONT = 'C:/Windows/Fonts/consola.ttf'
            $env:ZCODE_TEST_ICON_FONT = 'D:/SoftWare/Develop/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
        } else {
            Remove-Item Env:ZCODE_UI_CAPTURE_DIR -ErrorAction SilentlyContinue
        }
        $args = @('test', '--no-pub') + $case.Paths + @('--reporter', 'expanded')
        & $wrapper -Log $log -FlutterArgs $args
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $caseFailed = $true
            $failed.Add("$($case.Id) exit=$exitCode")
        }
    } elseif (Test-Path -LiteralPath $log) {
        $caseFailed = (Get-Content -Raw -LiteralPath $log) -match 'Some tests failed|Test failed|EXCEPTION CAUGHT'
    }

    $images = if ($captureDir -and (Test-Path -LiteralPath $captureDir)) {
        @(Get-ChildItem -LiteralPath $captureDir -File -Filter '*.png' | Sort-Object Name)
    } else { @() }
    if ($images.Count -eq 0) {
        $logEvidence = if (Test-Path -LiteralPath $log) {
            (Resolve-Path $log).Path
        } else {
            "$($case.Id).log (not produced in this replay)"
        }
        $rows.Add([pscustomobject]@{
            case = $case.Id
            evidence = $logEvidence
            condition = $case.Condition
            source = $sourceIdentity
            fixture = $case.Fixture
            status = if ($caseFailed) { 'failed-or-deferred' } else { 'behavior-pass' }
            unverified = $case.Boundary
        })
    } else {
        foreach ($image in $images) {
            $rows.Add([pscustomobject]@{
                case = $case.Id
                evidence = $image.FullName
                condition = $case.Condition
                source = $sourceIdentity
                fixture = $case.Fixture
                status = if ($caseFailed) { 'captured despite test failure; inspect required' } else { 'captured; inspect required' }
                unverified = $case.Boundary
            })
        }
    }
}

Remove-Item Env:ZCODE_UI_CAPTURE_DIR,Env:ZCODE_TEST_FONT,Env:ZCODE_TEST_MONO_FONT,Env:ZCODE_TEST_ICON_FONT -ErrorAction SilentlyContinue
$rows | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Content -LiteralPath $manifest -Encoding utf8
Write-Output "manifest=$manifest"
if ($failed.Count -gt 0) {
    Write-Output ('failed=' + ($failed -join ', '))
    exit 1
}
