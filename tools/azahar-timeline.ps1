# Diagnóstico: arranca Azahar con un ROM y registra cada 2 s los títulos de ventana del
# proceso (el título cambia a "Azahar | <juego> | FPS" cuando emula) durante -Seconds.
# Guarda capturas de pantalla (ventana al frente) en build\timeline-<t>.png.
param(
    [Parameter(Mandatory = $true)][string]$Rom,
    [int]$Seconds = 30,
    [int[]]$ShotAt = @(4, 10, 20)
)
$azahar = Join-Path $env:USERPROFILE "3ds-tools\azahar\azahar.exe"
Get-Process azahar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class W2 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
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
$build = Join-Path (Split-Path -Parent $PSScriptRoot) "build"
New-Item -ItemType Directory -Force $build | Out-Null
$p = Start-Process -FilePath $azahar -ArgumentList "`"$Rom`"" -PassThru
$t = 0
while ($t -lt $Seconds) {
    Start-Sleep -Seconds 2; $t += 2
    if ($p.HasExited) { Write-Host "t=$t proceso terminado exit=$($p.ExitCode)"; break }
    $wins = [W2]::Windows([uint32]$p.Id)
    $desc = ($wins | ForEach-Object { "'$($_[1])' $($_[4])x$($_[5])" }) -join " ; "
    Write-Host "t=$t  $desc"
    if ($ShotAt -contains $t -and $wins.Count -gt 0) {
        $w = $wins | Sort-Object { $_[4] * $_[5] } -Descending | Select-Object -First 1
        [W2]::SetForegroundWindow([IntPtr]$w[0]) | Out-Null
        Start-Sleep -Milliseconds 600
        $bmp = New-Object Drawing.Bitmap $w[4], $w[5]
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($w[2], $w[3], 0, 0, (New-Object Drawing.Size $w[4], $w[5]))
        $bmp.Save("$build\timeline-$t.png", [Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Write-Host "   captura build\timeline-$t.png"
    }
}
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Get-Process azahar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
