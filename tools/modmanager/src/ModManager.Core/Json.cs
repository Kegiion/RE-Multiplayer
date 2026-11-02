using System.Text.Json;

namespace REMultiplayer.ModManager.Core;

/// <summary>Gemeinsame JSON-Einstellungen (games.json, Installationsprotokoll, Einstellungen).</summary>
public static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        WriteIndented = true,
    };
}
