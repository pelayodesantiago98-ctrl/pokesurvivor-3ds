# Captura desde DENTRO del juego (love.graphics.captureScreenshot): no necesita traer
# la ventana al frente, así no molesta si se está usando el PC.
#   .\tools\game-shot.ps1 -Seconds 15 -GameArgs "--demo" -Out build\shot.png
param([int]$Seconds = 10, [string]$GameArgs = "", [string]$Out = "$PSScriptRoot\..\build\shot.png")
$Root = Split-Path -Parent $PSScriptRoot
$love = Join-Path $env:USERPROFILE "3ds-tools\love\love.exe"
$save = Join-Path $env:APPDATA "LOVE\pokesurvivor3ds\shot.png"
Remove-Item $save -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $love -ArgumentList "`"$Root\game`" --shot=$Seconds $GameArgs" -PassThru -WindowStyle Minimized
if (-not $p.WaitForExit(($Seconds + 30) * 1000)) { Stop-Process -Id $p.Id -Force }
if (Test-Path $save) {
    $dir = Split-Path -Parent $Out
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    Copy-Item $save $Out -Force
    Write-Host "captura: $((Resolve-Path $Out).Path)"
} else { Write-Host "no se generó la captura" }
