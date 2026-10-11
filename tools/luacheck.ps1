# Comprueba la SINTAXIS de ficheros Lua usando el intérprete de LÖVE (no hay luac).
#   .\tools\luacheck.ps1 game\src\world.lua game\src\fx.lua
#   .\tools\luacheck.ps1 -All          # todos los .lua de game\
# Imprime "OK <fichero>" o "ERR <fichero>: <mensaje>" y devuelve 1 si hay errores.
param(
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files,
    [switch]$All
)
$root = Split-Path -Parent $PSScriptRoot
$lovec = Join-Path $env:USERPROFILE "3ds-tools\love\lovec.exe"
if (-not (Test-Path $lovec)) { throw "No encuentro $lovec" }
if ($All) { $Files = Get-ChildItem (Join-Path $root "game") -Recurse -Filter *.lua | Where-Object { $_.FullName -notmatch '\\nest\\' } | ForEach-Object { $_.FullName } }
if (-not $Files -or $Files.Count -eq 0) { throw "Indica ficheros o -All" }
$abs = $Files | ForEach-Object { (Resolve-Path $_).Path -replace '\\', '/' }
$tmp = Join-Path $env:TEMP ("luacheck-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
$list = ($abs | ForEach-Object { '"' + $_ + '"' }) -join ",`n"
@"
io.stdout:setvbuf("no")
local files = { $list }
local bad = 0
for _, p in ipairs(files) do
    local f, err = loadfile(p)
    if f then print("OK  " .. p) else print("ERR " .. tostring(err)); bad = bad + 1 end
end
print("LUACHECK_DONE " .. bad)
function love.load() love.event.quit(bad > 0 and 1 or 0) end
"@ | Out-File (Join-Path $tmp "main.lua") -Encoding utf8
$out = Join-Path $tmp "out.txt"
cmd /c "`"$lovec`" `"$tmp`" > `"$out`" 2>&1"
$text = Get-Content $out -Raw
Write-Output $text
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
if ($text -match 'LUACHECK_DONE (\d+)' -and [int]$Matches[1] -gt 0) { exit 1 }
if ($text -notmatch 'LUACHECK_DONE') { Write-Output "FALLO: el comprobador no terminó"; exit 1 }
exit 0
