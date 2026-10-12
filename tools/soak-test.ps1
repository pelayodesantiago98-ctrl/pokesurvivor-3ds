# Prueba de resistencia en PC: N segundos de partida automática acelerada (x8), con el
# jugador dando vueltas solo y eligiendo cartas solo. Caza errores de jefes, mareas,
# grietas, eventos y clima. Imprime SOAK_OK, SOAK_STUCK (atasco) o el error con traceback.
#   .\tools\soak-test.ps1 [-Seconds 600] [-TimeoutSec 600] [-GameArgs "--mortal --stage=3"] [-Tag a]
# -Tag separa los ficheros de salida para lanzar varias pruebas en paralelo.
param([int]$Seconds = 600, [int]$TimeoutSec = 600, [string]$GameArgs = "", [string]$Tag = "")
$Root = Split-Path -Parent $PSScriptRoot
$love = Join-Path $env:USERPROFILE "3ds-tools\love\lovec.exe"
$sfx = if ($Tag) { "-$Tag" } else { "" }
$out = Join-Path $env:TEMP "pokesurvivor-soak$sfx.txt"
$trace = Join-Path $Root "build\smoke-trace$sfx.txt"
$tagArg = if ($Tag) { "--tag=$Tag" } else { "" }
Remove-Item $trace, $out -ErrorAction SilentlyContinue
$p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$love`" `"$Root\game`" --soak=$Seconds $tagArg $GameArgs > `"$out`" 2>&1`"" -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    # Sólo el proceso de esta prueba (puede haber otras en paralelo).
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Write-Host "TIMEOUT (posible cuelgue)"
}
$text = Get-Content $out -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^\[Sprites\]' }
$text | Select-Object -Last 25
Write-Host "--- traza:"
if (Test-Path $trace) { Get-Content $trace | Select-Object -Last 30 }
if (($text -join "`n") -match "SOAK_OK") { Write-Host "RESULTADO: OK"; exit 0 }
Write-Host "RESULTADO: FALLO"; exit 1
