# Ende-zu-Ende-Test der Manager-exe ohne Fenster (laeuft in der CI):
# Fake-RE0-Ordner mit fremder dinput8.dll und Einstellungen, Fake-Paket installieren,
# dann deinstallieren und pruefen, dass alles wie vorher ist.
param([Parameter(Mandatory)][string]$Exe)
$ErrorActionPreference = 'Stop'

$exe = (Resolve-Path $Exe).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'remods-manager-e2e'
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
$pkg = Join-Path $tmp 'pkg'
$game = Join-Path $tmp 'Resident Evil 0'
New-Item -ItemType Directory -Force "$pkg/remods/autorun", "$game/remods/data" | Out-Null

# Paket wie dist/RE0HD-Coop. Der Loader enthaelt den Runtime-Pfad als UTF-16 (daran erkennt ihn der Manager).
[IO.File]::WriteAllBytes("$pkg/dinput8.dll", [Text.Encoding]::Unicode.GetBytes('remods\remods_re0.dll'))
Set-Content "$pkg/remods/remods_re0.dll" 'runtime'
Set-Content "$pkg/remods/autorun/re0hd_coop.lua" '-- mod'
$zip = Join-Path $tmp 'RE0HD-Coop-9.9.9.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($pkg, $zip)

Set-Content "$game/re0hd.exe" 'MZ'
Set-Content "$game/dinput8.dll" 'fremde Mod'
Set-Content "$game/remods/data/settings.json" '{}'

$log = Join-Path $env:LOCALAPPDATA 'REMods/manager.log'
function Invoke-Manager([string]$argList) {
    $p = Start-Process $exe -ArgumentList $argList -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        if (Test-Path $log) { Get-Content $log | Select-Object -Last 30 }
        throw "Manager $argList endete mit Exit-Code $($p.ExitCode)"
    }
}

Invoke-Manager "--install re0hd --path `"$game`" --package `"$zip`" --version 9.9.9"
foreach ($f in 'dinput8.dll', 'dinput8.dll.vor-remods', 'remods/remods_re0.dll', 'remods/autorun/re0hd_coop.lua', 'remods/remods-install.json') {
    if (-not (Test-Path (Join-Path $game $f))) { throw "$f fehlt nach der Installation" }
}
$record = Get-Content (Join-Path $game 'remods/remods-install.json') -Raw | ConvertFrom-Json
if ($record.version -ne '9.9.9') { throw "Falsche Version im Installationsprotokoll: $($record.version)" }

Invoke-Manager "--uninstall re0hd --path `"$game`""
if (Test-Path (Join-Path $game 'remods/remods_re0.dll')) { throw 'Runtime nach der Deinstallation noch da' }
if (Test-Path (Join-Path $game 'remods/autorun')) { throw 'autorun nach der Deinstallation noch da' }
if ((Get-Content (Join-Path $game 'dinput8.dll')) -ne 'fremde Mod') { throw 'Fremde dinput8.dll nicht wiederhergestellt' }
if (-not (Test-Path (Join-Path $game 'remods/data/settings.json'))) { throw 'Einstellungen wurden geloescht' }

# Falscher Aufruf muss mit 3 enden
$p = Start-Process $exe -ArgumentList '--install re0hd --path C:\gibtsnicht' -Wait -PassThru
if ($p.ExitCode -ne 3) { throw "Falscher Aufruf: Exit-Code $($p.ExitCode) statt 3" }

Write-Output 'Mod-Manager E2E ok'
