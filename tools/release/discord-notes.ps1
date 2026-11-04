# Postet die Patch Notes eines Releases per Webhook in den Discord-Channel (genutzt von .github/workflows/release.yml).
#   ./tools/release/discord-notes.ps1 -Title "Resident Evil 2 Koop 0.11.3" -Url <release-link> [-DryRun]
# Liest dist/release-notes.md (von release-meta.ps1). Webhook-URL aus $env:DISCORD_WEBHOOK (Secret DISCORD_PATCHNOTES_WEBHOOK).
# Ohne Webhook oder mit -DryRun wird nur die Nachricht ausgegeben. Scheitert nie (Exit 0), damit kein Release daran haengt.
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Url,
    [string]$NotesFile = (Join-Path $PSScriptRoot '../../dist/release-notes.md'),
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

# Kuerzt an einer Zeilengrenze und haengt einen Link zum Release an
function Limit-Text([string]$text, [int]$max, [string]$more) {
    if ($text.Length -le $max) { return $text }
    $cut = $text.Substring(0, $max - $more.Length - 2)
    $nl = $cut.LastIndexOf("`n")
    if ($nl -gt $max / 2) { $cut = $cut.Substring(0, $nl) }
    return $cut.TrimEnd() + "`n`n" + $more
}

try {
    $text = (Get-Content -Path $NotesFile -Raw -Encoding utf8).Replace("`r`n", "`n").Trim()

    # Abschnitte "### Deutsch" / "### English" trennen; ohne diese Ueberschriften ein einziger Abschnitt
    $sections = [System.Collections.Generic.List[object]]::new()
    $current = $null
    $rest = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $text -split "`n") {
        if ($line -match '^###\s+(Deutsch|English)\s*$') {
            $current = @{ Lang = $Matches[1]; Lines = [System.Collections.Generic.List[string]]::new() }
            $sections.Add($current)
        } elseif ($current) { $current.Lines.Add($line) } else { $rest.Add($line) }
    }
    if ($sections.Count -eq 0) { $sections.Add(@{ Lang = 'Deutsch'; Lines = $rest }) }

    # Discord: Beschreibung max. 4096 Zeichen, alle Embeds zusammen max. 6000
    $max = [Math]::Min(4000, [Math]::Floor(5600 / $sections.Count) - $Title.Length - 20)
    $embeds = @()
    foreach ($s in $sections) {
        $de = $s.Lang -eq 'Deutsch'
        $dots = [char]0x2026  # Auslassungszeichen, als Code damit die Datei reines ASCII bleibt
        $more = if ($de) { "[$dots mehr im Release]($Url)" } else { "[$dots more in the release]($Url)" }
        $flag = if ($de) { 'Deutsch' } else { 'English' }
        $body = ($s.Lines -join "`n").Trim()
        if (-not $body) { continue }
        $embeds += @{
            title       = "$Title ($flag)"
            url         = $Url
            description = Limit-Text $body $max $more
            color       = 0xB71C1C
        }
    }

    $payload = @{
        username         = 'RE:Multiplayer'
        content          = "**$Title** ist da / is out: $Url"
        embeds           = $embeds
        allowed_mentions = @{ parse = @() }
    }
    $json = $payload | ConvertTo-Json -Depth 6

    $hook = $env:DISCORD_WEBHOOK
    if ($DryRun -or -not $hook) {
        if (-not $hook -and -not $DryRun) { Write-Output 'Kein Secret DISCORD_PATCHNOTES_WEBHOOK gesetzt: nichts gepostet.' }
        Write-Output '--- Discord-Nachricht (nicht gepostet) ---'
        Write-Output $json
        exit 0
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Invoke-RestMethod -Method Post -Uri $hook -Body $bytes -ContentType 'application/json; charset=utf-8' | Out-Null
    Write-Output "Patch Notes in Discord gepostet ($($embeds.Count) Embeds)."
} catch {
    # Webhook-URL nie ausgeben, nur die Fehlermeldung
    Write-Output "::warning::Discord-Post fehlgeschlagen: $($_.Exception.Message)"
}
exit 0
