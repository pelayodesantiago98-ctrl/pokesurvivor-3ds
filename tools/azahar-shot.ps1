# Arranca Azahar con un .3dsx/.cia, espera, captura la ventana de emulación a PNG
# (PrintWindow, funciona aunque esté tapada) y cierra el emulador.
# Deja también build\azahar-log.txt con la cola del log del emulador.
param(
    [Parameter(Mandatory = $true)][string]$Rom,
    [int]$WaitSeconds = 20,
    [string]$Out = "$PSScriptRoot\..\build\azahar.png",
    [switch]$Foreground
)
$azahar = Join-Path $env:USERPROFILE "3ds-tools\azahar\azahar.exe"
if (-not (Test-Path $azahar)) { throw "No encuentro $azahar" }
Get-Process azahar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class Win32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public static List<object[]> Windows(uint pid) {
        var list = new List<object[]>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
                RECT r; GetWindowRect(h, out r);
                list.Add(new object[] { h, sb.ToString(), (r.R - r.L) * (r.B - r.T) });
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

$p = Start-Process -FilePath $azahar -ArgumentList "`"$Rom`"" -PassThru
Start-Sleep -Seconds $WaitSeconds

$wins = [Win32]::Windows([uint32]$p.Id)
$dir = Split-Path -Parent $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$dir = (Resolve-Path $dir).Path
"Ventanas visibles del proceso:" | Out-File "$dir\azahar-windows.txt"
foreach ($w in $wins) { "  '$($w[1])' area=$($w[2])" | Out-File "$dir\azahar-windows.txt" -Append }
Get-Content "$dir\azahar-windows.txt"

if ($wins.Count -eq 0) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; throw "Azahar no mostró ventana" }
# Preferir la ventana con título (la principal); si hay varias, la de mayor área.
$best = $wins | Sort-Object { if ($_[1]) { 1 } else { 0 } }, { $_[2] } -Descending | Select-Object -First 1
$h = [IntPtr]$best[0]
if ([Win32]::IsIconic($h)) { [Win32]::ShowWindow($h, 9) | Out-Null; Start-Sleep -Milliseconds 500 }

$r = New-Object Win32+RECT
[Win32]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object Drawing.Bitmap $w, $hh
$g = [Drawing.Graphics]::FromImage($bmp)
if ($Foreground) {
    # El widget OpenGL de Azahar no sale con PrintWindow: traer al frente y copiar de pantalla.
    [Win32]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 700
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object Drawing.Size $w, $hh))
    $okPrint = "screen"
} else {
    $hdc = $g.GetHdc()
    $okPrint = [Win32]::PrintWindow($h, $hdc, 2)   # PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc)
}
$full = Join-Path $dir (Split-Path -Leaf $Out)
$bmp.Save($full, [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

$log = Join-Path $env:APPDATA "Azahar\log\azahar_log.txt"
if (Test-Path $log) { Get-Content $log -Tail 40 | Out-File "$dir\azahar-log.txt" }

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Get-Process azahar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "captura: $full ($w x $hh, PrintWindow=$okPrint, ventana='$($best[1])')"
