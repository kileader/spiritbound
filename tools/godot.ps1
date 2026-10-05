[CmdletBinding()]
param(
    [ValidateSet('play', 'test', 'check', 'web', 'windows')]
    [string]$Action = 'play',
    [string]$GodotPath = $env:SPIRITBOUND_GODOT
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $GodotPath) {
    $localEngine = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $localEngine) {
        $GodotPath = $localEngine
    } else {
        $installedEngine = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($installedEngine) { $GodotPath = $installedEngine.Source }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot was not found. Pass -GodotPath <path-to-Godot> or set SPIRITBOUND_GODOT. Use Godot 4.7.2 Standard.'
}

switch ($Action) {
    'play' { & $GodotPath --path $projectRoot }
    'test' {
        foreach ($testScript in @('tests/run_room.gd', 'tests/run_animation.gd', 'tests/run_splash.gd')) {
            & $GodotPath --headless --path $projectRoot --script $testScript
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    }
    'check' { & $GodotPath --headless --path $projectRoot --editor --import --quit }
    'web' {
        New-Item -ItemType Directory -Path (Join-Path $projectRoot 'builds\web') -Force | Out-Null
        & $GodotPath --headless --path $projectRoot --export-release 'Web'
    }
    'windows' {
        New-Item -ItemType Directory -Path (Join-Path $projectRoot 'builds\windows') -Force | Out-Null
        & $GodotPath --headless --path $projectRoot --export-release 'Windows Desktop'
    }
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
