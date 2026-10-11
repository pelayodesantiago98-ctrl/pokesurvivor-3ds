# Arranca el juego en PC (LÖVE + nest), espera, captura su ventana a PNG y lo cierra.
#   .\tools\pc-shot.ps1 [-WaitSeconds 8] [-Out build\pc.png] [-GameArgs "--run --scale1"]
# Sirve para ver qué hay en pantalla cuando el juego se cuelga o no responde.
param(
    [int]$WaitSeconds = 8,
    [string]$Out = "$PSScriptRoot\..\build\pc.png",
    [string]$GameArgs = ""
)
$Root = Split-Path -Parent $PSScriptRoot
$love = Join-Path $env:USERPROFILE "3ds-tools\love\love.exe"
Get-Process love, lovec -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class WinShot {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static List<object[]> Windows(uint pid) {
        var list = new List<object[]>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
                RECT r; GetWindowRect(h, out r);
                list.Add(new object[] { h, sb.ToString(), r.L, r.T, r.R - r.L, r.B - r.T });
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@
[WinShot]::SetProcessDPIAware() | Out-Null
$argList = "`"$Root\game`""
if ($GameArgs) { $argList += " " + $GameArgs }
$p = Start-Process -FilePath $love -ArgumentList $argList -PassThru
Start-Sleep -Seconds $WaitSeconds
$dir = Split-Path -Parent $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$full = Join-Path ((Resolve-Path $dir).Path) (Split-Path -Leaf $Out)
if ($p.HasExited) { Write-Host "El proceso terminó solo (exit $($p.ExitCode))"; exit 0 }
$wins = [WinShot]::Windows([uint32]$p.Id)
foreach ($w in $wins) { Write-Host ("ventana '{0}' {1}x{2}" -f $w[1], $w[4], $w[5]) }
$best = $wins | Sort-Object { $_[4] * $_[5] } -Descending | Select-Object -First 1
if ($best) {
    [WinShot]::SetForegroundWindow([IntPtr]$best[0]) | Out-Null
    Start-Sleep -Milliseconds 600
    $bmp = New-Object Drawing.Bitmap $best[4], $best[5]
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($best[2], $best[3], 0, 0, (New-Object Drawing.Size $best[4], $best[5]))
    $bmp.Save($full, [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "captura: $full"
} else { Write-Host "sin ventana visible" }
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
