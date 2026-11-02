# Liest Version und Patch Notes fuer ein Release (genutzt von .github/workflows/release.yml).
#   ./tools/release/release-meta.ps1 -Mod re0hd
# Schreibt dist/release-notes.md und die Step-Outputs version, tag, title, asset.
param([Parameter(Mandatory)][ValidateSet('re0hd', 're2r', 'manager')][string]$Mod)
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mods = @{
    're0hd'   = @{ Source = 'games/re0hd/lua/autorun/re0hd_coop.lua'; Pattern = '^local MOD_VERSION = "([^"]+)"'
                   Changelog = 'games/re0hd/CHANGELOG.md'; Title = 'Resident Evil 0 HD Koop'; Asset = 'RE0HD-Coop-{0}.zip' }
    're2r'    = @{ Source = 'games/re2r/coop/autorun/re2r_coop.lua'; Pattern = '^local MOD_VERSION = "([^"]+)"'
                   Changelog = 'games/re2r/CHANGELOG.md'; Title = 'Resident Evil 2 Koop'; Asset = 'RE2R-Coop-{0}.zip' }
    'manager' = @{ Source = 'tools/modmanager/Directory.Build.props'; Pattern = '<Version>([^<]+)</Version>'
                   Changelog = 'tools/modmanager/CHANGELOG.md'; Title = 'RE:Multiplayer Mod-Manager'; Asset = 'RE-Multiplayer.exe' }
}
$m = $mods[$Mod]

$match = Select-String -Path (Join-Path $root $m.Source) -Pattern $m.Pattern | Select-Object -First 1
if (-not $match) { throw "Keine Version in $($m.Source) gefunden." }
$version = $match.Matches[0].Groups[1].Value.Trim()
if ($version -notmatch '^\d+(\.\d+){1,3}(-[0-9A-Za-z.]+)?$') { throw "Ungueltige Version '$version' in $($m.Source)." }

# Patch Notes: Abschnitt "## <Version>" (gern mit Datum dahinter) bis zur naechsten "## "-Ueberschrift
$heading = '^##\s+\[?' + [regex]::Escape($version) + '\]?(\s|$)'
$notes = [System.Collections.Generic.List[string]]::new()
$inside = $false
foreach ($line in Get-Content (Join-Path $root $m.Changelog) -Encoding utf8) {
    if ($line -match '^##\s') {
        if ($inside) { break }
        if ($line -match $heading) { $inside = $true }
        continue
    }
    if ($inside) { $notes.Add($line) }
}
$text = ($notes -join "`n").Trim()
if (-not $text) { throw "In $($m.Changelog) fehlt der Abschnitt '## $version'. Bitte zuerst Patch Notes eintragen." }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
Set-Content -Path (Join-Path $dist 'release-notes.md') -Value $text -Encoding utf8NoBOM

$tag = "$Mod-v$version"
$out = @(
    "version=$version"
    "tag=$tag"
    "title=$($m.Title) $version"
    "asset=$($m.Asset -f $version)"
)
if ($env:GITHUB_OUTPUT) { $out | Add-Content -Path $env:GITHUB_OUTPUT -Encoding utf8 }
$out | ForEach-Object { Write-Output $_ }
Write-Output '--- Patch Notes ---'
Write-Output $text
