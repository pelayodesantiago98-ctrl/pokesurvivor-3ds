# Ejecuta el juego en el PC con LÖVE 11.5 + nest (simula las dos pantallas de la 3DS).
# Controles en PC (nest): WASD = circle pad, flechas = cruceta, Z=A, X=B, C=X, V=Y,
# Enter = START, Shift dcho = SELECT, Q/E = L/R. Clic en la pantalla inferior = toque.
param([switch]$Console)

$Root = Split-Path -Parent $PSScriptRoot
$LoveDir = Join-Path $env:USERPROFILE "3ds-tools\love"
$exe = if ($Console) { Join-Path $LoveDir "lovec.exe" } else { Join-Path $LoveDir "love.exe" }
if (-not (Test-Path $exe)) { throw "No encuentro LÖVE en $LoveDir" }
& $exe (Join-Path $Root "game") @args
