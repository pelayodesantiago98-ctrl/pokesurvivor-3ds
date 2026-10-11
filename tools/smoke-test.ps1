# Prueba de humo en PC: arranca el juego con LÖVE + nest en modo --smoke.
# El juego imprime SMOKE_OK y cierra tras 90 frames, o SMOKE_ERROR + traceback y sale con 1.
# Nota: hay que lanzar lovec.exe a través de cmd; Start-Process con -RedirectStandardOutput
# no captura la salida de LÖVE.
$Root = Split-Path -Parent $PSScriptRoot
$love = Join-Path $env:USERPROFILE "3ds-tools\love\lovec.exe"
$out  = Join-Path $env:TEMP "pokesurvivor-smoke.txt"
if (-not (Test-Path $love)) { throw "No encuentro $love" }

$trace = Join-Path $Root "build\smoke-trace.txt"
Remove-Item $trace -ErrorAction SilentlyContinue
# Con tope de tiempo: si el juego se cuelga, se mata y se enseña la traza.
$p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$love`" `"$Root\game`" --smoke > `"$out`" 2>&1`"" -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(90000)) {
    Get-Process lovec -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "TIMEOUT: el juego no terminó en 90 s. Traza:"
    if (Test-Path $trace) { Get-Content $trace | Select-Object -Last 15 }
    Write-Host "RESULTADO: FALLO"; exit 1
}
$text = Get-Content $out -Raw
Write-Host $text
if ($text -notmatch "SMOKE_OK" -and (Test-Path $trace)) { Write-Host "Traza:"; Get-Content $trace | Select-Object -Last 15 }
if ($text -match "SMOKE_OK") { Write-Host "RESULTADO: OK"; exit 0 }
Write-Host "RESULTADO: FALLO"; exit 1
