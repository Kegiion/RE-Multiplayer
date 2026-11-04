# Postet die Patch Notes eines Releases ueber den RE:Multiplayer-Bot in den Discord-Channel (genutzt von .github/workflows/release.yml).
#   ./tools/release/discord-notes.ps1 -Title "Resident Evil 2 Koop 0.11.3" -Url <release-link> [-DryRun]
# Liest dist/release-notes.md (von release-meta.ps1). Bot-Token aus $env:DISCORD_BOT_TOKEN (Secret DISCORD_BOT_TOKEN),
# Channel aus $env:DISCORD_CHANNEL_ID (Repo-Variable DISCORD_PATCHNOTES_CHANNEL_ID).
# Ohne Token/Channel oder mit -DryRun wird nur die Nachricht ausgegeben. Scheitert nie (Exit 0), damit kein Release daran haengt.
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
    if ($sections.Count -eq 0) { $sections.Add(@{ Lang = ''; Lines = $rest }) }
    # Discord ist englisch: gibt es einen Abschnitt "### English", nur diesen posten
    $en = @($sections | Where-Object { $_.Lang -eq 'English' })
    if ($en.Count -gt 0) { $sections = $en }

    # Discord: Beschreibung max. 4096 Zeichen, alle Embeds zusammen max. 6000
    $max = [Math]::Min(4000, [Math]::Floor(5600 / $sections.Count) - $Title.Length - 20)
    $embeds = @()
    foreach ($s in $sections) {
        $dots = [char]0x2026  # Auslassungszeichen, als Code damit die Datei reines ASCII bleibt
        $more = "[$dots more in the release]($Url)"
        $body = ($s.Lines -join "`n").Trim()
        if (-not $body) { continue }
        $embeds += @{
            title       = $Title
            url         = $Url
            description = Limit-Text $body $max $more
            color       = 0xB71C1C
        }
    }

    $payload = @{
        content          = "**$Title** is out: $Url"
        embeds           = $embeds
        allowed_mentions = @{ parse = @() }
    }
    $json = $payload | ConvertTo-Json -Depth 6

    $token = $env:DISCORD_BOT_TOKEN
    $channel = $env:DISCORD_CHANNEL_ID
    if ($DryRun -or -not $token -or -not $channel) {
        if (-not $DryRun) { Write-Output 'Secret DISCORD_BOT_TOKEN oder Variable DISCORD_PATCHNOTES_CHANNEL_ID fehlt: nichts gepostet.' }
        Write-Output '--- Discord-Nachricht (nicht gepostet) ---'
        Write-Output $json
        exit 0
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    if ($channel -notmatch '^\d+$') { throw 'DISCORD_PATCHNOTES_CHANNEL_ID ist keine Channel-ID (nur Ziffern).' }
    $headers = @{ Authorization = "Bot $token"; 'User-Agent' = 'DiscordBot (https://github.com/Kegiion/RE-Multiplayer, 1.0)' }
    $msg = Invoke-RestMethod -Method Post -Uri "https://discord.com/api/v10/channels/$channel/messages" -Headers $headers `
        -Body $bytes -ContentType 'application/json; charset=utf-8'
    # Ankuendigungs-Channel: Nachricht zusaetzlich an folgende Server veroeffentlichen (sonst egal, Fehler wird ignoriert)
    try { Invoke-RestMethod -Method Post -Uri "https://discord.com/api/v10/channels/$channel/messages/$($msg.id)/crosspost" -Headers $headers | Out-Null } catch { }
    Write-Output "Patch Notes in Discord gepostet ($($embeds.Count) Embeds)."
} catch {
    # Token nie ausgeben, nur die Fehlermeldung
    Write-Output "::warning::Discord-Post fehlgeschlagen: $($_.Exception.Message)"
}
exit 0
