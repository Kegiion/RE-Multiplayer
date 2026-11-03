# Bildschirmfoto eines Spielfensters (fuer Claude: Ergebnis im Spiel selbst ansehen).
#
# Aufruf: powershell -File tools/spielfoto.ps1 -Prozess re2 -Datei C:\tmp\foto.jpg [-Skalierung 0.5]
# Das Fenster muss sichtbar sein (nicht minimiert, nicht verdeckt). Es wird der
# Bildschirmbereich des Fensters kopiert, im Vollbildmodus kann das Bild schwarz sein.
param(
    [string]$Prozess = "re2",
    [Parameter(Mandatory = $true)][string]$Datei,
    [double]$Skalierung = 0.5
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Fenster {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[Fenster]::SetProcessDPIAware() | Out-Null

$p = Get-Process -Name $Prozess -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($null -eq $p) { Write-Error "Kein Fenster von '$Prozess' gefunden"; exit 1 }

$r = New-Object Fenster+RECT
[Fenster]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left
$h = $r.Bottom - $r.Top
if ($w -le 0 -or $h -le 0) { Write-Error "Fenster hat keine Groesse (minimiert?)"; exit 1 }

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$sw = [int]($w * $Skalierung)
$sh = [int]($h * $Skalierung)
$klein = New-Object System.Drawing.Bitmap $bmp, $sw, $sh
$klein.Save($Datei, [System.Drawing.Imaging.ImageFormat]::Jpeg)
Write-Output "$Datei ($sw x $sh)"
