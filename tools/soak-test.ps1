# Prueba de resistencia en PC: N segundos de partida automática acelerada (x8), con el
# jugador dando vueltas solo y eligiendo cartas solo. Caza errores de jefes, mareas,
# grietas, eventos y clima. Imprime SOAK_OK o el error con traceback.
#   .\tools\soak-test.ps1 [-Seconds 600] [-TimeoutSec 600]
param([int]$Seconds = 600, [int]$TimeoutSec = 600, [string]$GameArgs = "")
$Root = Split-Path -Parent $PSScriptRoot
$love = Join-Path $env:USERPROFILE "3ds-tools\love\lovec.exe"
$out = Join-Path $env:TEMP "pokesurvivor-soak.txt"
$trace = Join-Path $Root "build\smoke-trace.txt"
Remove-Item $trace -ErrorAction SilentlyContinue
$p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$love`" `"$Root\game`" --soak=$Seconds $GameArgs > `"$out`" 2>&1`"" -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit($TimeoutSec * 1000)) { Get-Process lovec -ErrorAction SilentlyContinue | Stop-Process -Force; Write-Host "TIMEOUT" }
$text = Get-Content $out | Where-Object { $_ -notmatch '^\[Sprites\]' }
$text | Select-Object -Last 25
Write-Host "--- traza:"
if (Test-Path $trace) { Get-Content $trace | Select-Object -Last 30 }
if (($text -join "`n") -match "SOAK_OK") { Write-Host "RESULTADO: OK"; exit 0 }
Write-Host "RESULTADO: FALLO"; exit 1
