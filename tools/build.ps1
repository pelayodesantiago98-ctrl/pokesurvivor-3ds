<#
.SYNOPSIS
  Empaqueta el juego para Nintendo 3DS: genera un .3dsx (Homebrew Launcher)
  y un .cia (instalable con FBI) a partir de la carpeta game/.

.DESCRIPTION
  Pasos:
    1. Copia game/ a build/stage y convierte assets para la 3DS:
         *.png / *.jpg  -> *.t3x   (tex3ds -f rgba)     LÖVE Potion en 3DS SOLO carga t3x
         *.ttf / *.otf  -> *.bcfnt (mkbcfnt)            y fuentes bcfnt.
       En el código Lua se cargan con la extensión de la consola:
         love.graphics.newImage("img/pikachu.t3x")   (en PC usa .png; ver src/assets.lua)
    2. .3dsx: 3dsxtool (elf + smdh + romfs de LÖVE Potion) y se le anexa el
       juego comprimido en zip (modo "fused", igual que hace el bundler oficial).
    3. .cia: romfs = romfs de LÖVE Potion + juego sin comprimir; bannertool
       genera banner e icono; makerom crea el CIA. El binario de LÖVE Potion
       está parcheado para cargar desde romfs:/ cuando corre como título instalado.

.PARAMETER Target
  3dsx | cia | all (por defecto all)
#>
param(
    [ValidateSet("3dsx", "cia", "all")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"

# ---------- rutas ----------
$Root     = Split-Path -Parent $PSScriptRoot
$GameDir  = Join-Path $Root "game"
$Assets   = Join-Path $Root "assets"
$Build    = Join-Path $Root "build"
$Stage    = Join-Path $Build "stage"
$Dist     = Join-Path $Root "dist"

$Tools    = Join-Path $env:USERPROFILE "3ds-tools"
$LovePot  = Join-Path $Tools "lovepotion-cia"      # lovepotion.elf + lovepotion.3dsx + romfs\
$DkpBin   = "C:\devkitPro\tools\bin"
$Makerom  = Join-Path $Tools "bin\makerom.exe"
$Banner   = Join-Path $Tools "bin\bannertool.exe"
$Tex3ds   = Join-Path $DkpBin "tex3ds.exe"
$Mkbcfnt  = Join-Path $DkpBin "mkbcfnt.exe"
$Smdhtool = Join-Path $DkpBin "smdhtool.exe"
$3dsxtool = Join-Path $DkpBin "3dsxtool.exe"

# ---------- metadatos (lovebrew.toml) ----------
$toml = Get-Content (Join-Path $Root "lovebrew.toml") -Raw
function TomlValue($key) {
    if ($toml -match "(?m)^\s*$key\s*=\s*`"([^`"]*)`"") { return $Matches[1] }
    return ""
}
$Title       = TomlValue "title"
$Author      = TomlValue "author"
$Description = TomlValue "description"
$Version     = TomlValue "version"
$ProductCode = "CTR-P-PKSV"
$UniqueId    = "0xB4A7E"
$IconPng     = Join-Path $Assets "icon.png"
$BannerPng   = Join-Path $Assets "banner.png"
$BannerWav   = Join-Path $Assets "banner.wav"

foreach ($f in @($Makerom, $Banner, $Tex3ds, $Mkbcfnt, $Smdhtool, $3dsxtool, "$LovePot\lovepotion.elf", "$LovePot\lovepotion.3dsx", $IconPng, $BannerPng, $BannerWav)) {
    if (-not (Test-Path $f)) { throw "Falta: $f" }
}

Write-Host "== $Title v$Version ($Author) =="

# ---------- 1. staging + conversión de assets ----------
# Los assets convertidos se guardan en build\t3x-cache (misma ruta relativa) y solo
# se reconvierten si el PNG/TTF es más nuevo: con ~2000 atlas de Pokémon, convertir
# todo cada vez tardaría muchos minutos.
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force $Stage, $Dist | Out-Null
$Cache = Join-Path $Build "t3x-cache"
New-Item -ItemType Directory -Force $Cache | Out-Null
# Copia todo menos nest (solo sirve en PC) ni los PNG/TTF (van convertidos).
robocopy $GameDir $Stage /E /XD nest /XF *.png *.jpg *.jpeg *.ttf *.otf /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null

$converted = 0; $cached = 0
Get-ChildItem $GameDir -Recurse -File -Include *.png, *.jpg, *.jpeg, *.ttf, *.otf | ForEach-Object {
    $rel = $_.FullName.Substring($GameDir.Length + 1)
    $isFont = $_.Extension -in ".ttf", ".otf"
    $relOut = [IO.Path]::ChangeExtension($rel, $(if ($isFont) { ".bcfnt" } else { ".t3x" }))
    $cachePath = Join-Path $Cache $relOut
    $stagePath = Join-Path $Stage $relOut
    New-Item -ItemType Directory -Force (Split-Path -Parent $cachePath) | Out-Null
    New-Item -ItemType Directory -Force (Split-Path -Parent $stagePath) | Out-Null
    if (-not (Test-Path $cachePath) -or (Get-Item $cachePath).LastWriteTimeUtc -lt $_.LastWriteTimeUtc) {
        if ($isFont) {
            & $Mkbcfnt -o $cachePath $_.FullName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "mkbcfnt falló con $($_.FullName)" }
        } else {
            & $Tex3ds -f rgba -z auto -o $cachePath $_.FullName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "tex3ds falló con $($_.FullName)" }
        }
        $converted++
    } else { $cached++ }
    Copy-Item $cachePath $stagePath -Force
}
Write-Host "Assets convertidos: $converted (en caché: $cached)"

# ---------- helper: zip con separadores '/' (Compress-Archive de PS 5.1 usa '\' y rompe physfs) ----------
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-ForwardSlashZip($sourceDir, $zipPath) {
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    $fs  = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew)
    $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem $sourceDir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($sourceDir.Length).TrimStart('\', '/').Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        $zip.Dispose(); $fs.Dispose()
    }
}

# ---------- 2. .3dsx ----------
if ($Target -eq "3dsx" -or $Target -eq "all") {
    $smdh = Join-Path $Build "$Title.smdh"
    & $Smdhtool --create $Title $Description $Author $IconPng $smdh
    if ($LASTEXITCODE -ne 0) { throw "smdhtool falló" }

    $base3dsx = Join-Path $Build "$Title.base.3dsx"
    & $3dsxtool "$LovePot\lovepotion.elf" $base3dsx "--smdh=$smdh" "--romfs=$LovePot\romfs"
    if ($LASTEXITCODE -ne 0) { throw "3dsxtool falló" }

    $love = Join-Path $Build "game.love"
    New-ForwardSlashZip $Stage $love

    $out3dsx = Join-Path $Dist "$Title.3dsx"
    $bytes = [IO.File]::ReadAllBytes($base3dsx) + [IO.File]::ReadAllBytes($love)
    [IO.File]::WriteAllBytes($out3dsx, $bytes)
    Write-Host "OK  $out3dsx  ($([math]::Round($bytes.Length/1KB)) KB)"
}

# ---------- 3. .cia ----------
if ($Target -eq "cia" -or $Target -eq "all") {
    $romfs = Join-Path $Build "romfs"
    if (Test-Path $romfs) { Remove-Item -Recurse -Force $romfs }
    New-Item -ItemType Directory -Force $romfs | Out-Null
    Copy-Item -Recurse -Force "$LovePot\romfs\*" $romfs     # shaders + nogame de LÖVE Potion
    Copy-Item -Recurse -Force "$Stage\*" $romfs             # main.lua y el resto del juego en la raíz

    $bnr = Join-Path $Build "banner.bnr"
    $icn = Join-Path $Build "icon.icn"
    & $Banner makebanner -i $BannerPng -a $BannerWav -o $bnr | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bannertool makebanner falló" }
    & $Banner makesmdh -s $Title -l $Description -p $Author -i $IconPng -f "visible,nosavebackups" -o $icn | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bannertool makesmdh falló" }

    $v = $Version.Split('.')
    $outcia = Join-Path $Dist "$Title.cia"
    & $Makerom -f cia -o $outcia -target t -exefslogo `
        -elf "$LovePot\lovepotion.elf" -rsf (Join-Path $PSScriptRoot "app.rsf") `
        -banner $bnr -icon $icn `
        -major $v[0] -minor $v[1] -micro $v[2] `
        "-DAPP_TITLE=$Title" "-DAPP_PRODUCT_CODE=$ProductCode" "-DAPP_UNIQUE_ID=$UniqueId" "-DAPP_ROMFS=$romfs"
    if ($LASTEXITCODE -ne 0) { throw "makerom falló" }
    Write-Host "OK  $outcia  ($([math]::Round((Get-Item $outcia).Length/1KB)) KB)"
}

Write-Host "Listo. Copia dist\ a la SD: el .3dsx a /3ds/, el .cia se instala con FBI."
