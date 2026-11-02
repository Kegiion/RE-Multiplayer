using System.Globalization;
using System.Text.Json;
using REMods.ModManager.Core.Install;

namespace REMods.ModManager.Core.Games;

/// <summary>Ein unterstuetztes Spiel (Eintrag aus games.json).</summary>
public sealed class GameDefinition
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public int SteamAppId { get; set; }
    public string Exe { get; set; } = "";
    public string ProcessName { get; set; } = "";

    /// <summary>Release-Tags dieser Mod beginnen damit, z. B. "re0hd-v" fuer "re0hd-v0.4.0".</summary>
    public string TagPrefix { get; set; } = "";

    /// <summary>Name des ZIP-Assets im Release beginnt damit, z. B. "RE0HD-Coop-".</summary>
    public string AssetPrefix { get; set; } = "";

    /// <summary>Gibt es diese Datei, gilt die Mod als installiert (auch ohne Protokoll, z. B. alter Installer).</summary>
    public string InstalledMarker { get; set; } = "";

    /// <summary>Installationsprotokoll des Managers (relativ zum Spielordner).</summary>
    public string RecordPath { get; set; } = "";

    /// <summary>Werden nie geloescht oder ueberschrieben (Einstellungen des Spielers).</summary>
    public List<string> KeepPaths { get; set; } = [];

    /// <summary>Zum Deinstallieren ohne Protokoll (Installation per Hand oder alter Installer).</summary>
    public List<string> LegacyFiles { get; set; } = [];

    public List<string> LegacyDirs { get; set; } = [];

    public LoaderRule? Loader { get; set; }

    public FrameworkRule? Framework { get; set; }

    /// <summary>PE-Zeitstempel der unterstuetzten exe-Versionen (hex). Leer = keine Pruefung.</summary>
    public List<string> SupportedExeTimestamps { get; set; } = [];

    public List<string> Logs { get; set; } = [];

    public string? Hint { get; set; }

    public bool IsExeSupported(uint? timestamp)
    {
        if (SupportedExeTimestamps.Count == 0)
        {
            return true;
        }
        return timestamp != null && SupportedExeTimestamps.Any(t =>
            uint.TryParse(t.Replace("0x", "", StringComparison.OrdinalIgnoreCase), NumberStyles.HexNumber,
                CultureInfo.InvariantCulture, out var v) && v == timestamp.Value);
    }

    public bool IsKept(string relativePath) =>
        KeepPaths.Any(k => GamePaths.IsUnder(relativePath, k));
}

/// <summary>
/// Eigener Loader (z. B. dinput8.dll bei RE0). Eine fremde Datei gleichen Namens wird
/// vor dem Ueberschreiben gesichert und beim Deinstallieren wiederhergestellt.
/// </summary>
public sealed class LoaderRule
{
    public string File { get; set; } = "";

    /// <summary>Text, der als UTF-16 in unserem Loader steht (daran erkennen wir ihn).</summary>
    public string OwnMarker { get; set; } = "";

    public string BackupSuffix { get; set; } = ".vor-remods";
}

/// <summary>Fremdes Framework, das die Mod braucht (z. B. REFramework bei RE2).</summary>
public sealed class FrameworkRule
{
    public string Name { get; set; } = "";

    /// <summary>GitHub-Repo, aus dessen neuestem Release geladen wird.</summary>
    public string Repo { get; set; } = "";

    public string Asset { get; set; } = "";

    /// <summary>Diese Dateien werden aus dem ZIP in den Spielordner kopiert.</summary>
    public List<string> Files { get; set; } = [];
}

/// <summary>Liste aller unterstuetzten Spiele (games.json).</summary>
public sealed class GameCatalog
{
    public const int SupportedSchema = 1;

    public int Schema { get; set; }

    public List<GameDefinition> Games { get; set; } = [];

    public static GameCatalog Parse(string json)
    {
        GameCatalog? catalog;
        try
        {
            catalog = JsonSerializer.Deserialize<GameCatalog>(json, Json.Options);
        }
        catch (JsonException e)
        {
            throw new InvalidDataException("games.json ist kein gueltiges JSON: " + e.Message, e);
        }
        if (catalog == null)
        {
            throw new InvalidDataException("games.json ist leer.");
        }
        catalog.Validate();
        return catalog;
    }

    /// <summary>Die in die exe eingebaute Spiele-Liste.</summary>
    public static GameCatalog LoadEmbedded()
    {
        using var stream = typeof(GameCatalog).Assembly.GetManifestResourceStream("games.json")
                           ?? throw new InvalidDataException("games.json fehlt in der exe.");
        using var reader = new StreamReader(stream);
        return Parse(reader.ReadToEnd());
    }

    private void Validate()
    {
        if (Schema != SupportedSchema)
        {
            throw new InvalidDataException($"games.json hat Schema {Schema}, dieser Manager kennt nur {SupportedSchema}.");
        }
        if (Games.Count == 0)
        {
            throw new InvalidDataException("games.json enthaelt keine Spiele.");
        }
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var g in Games)
        {
            if (string.IsNullOrWhiteSpace(g.Id) || string.IsNullOrWhiteSpace(g.Name) || string.IsNullOrWhiteSpace(g.Exe)
                || string.IsNullOrWhiteSpace(g.TagPrefix) || string.IsNullOrWhiteSpace(g.AssetPrefix)
                || string.IsNullOrWhiteSpace(g.InstalledMarker) || string.IsNullOrWhiteSpace(g.RecordPath))
            {
                throw new InvalidDataException($"games.json: Spiel \"{g.Id}\" ist unvollstaendig.");
            }
            if (!ids.Add(g.Id))
            {
                throw new InvalidDataException($"games.json: Spiel \"{g.Id}\" ist doppelt.");
            }
            var paths = new List<string> { g.Exe, g.InstalledMarker, g.RecordPath };
            paths.AddRange(g.KeepPaths);
            paths.AddRange(g.LegacyFiles);
            paths.AddRange(g.LegacyDirs);
            paths.AddRange(g.Logs);
            if (g.Loader != null)
            {
                paths.Add(g.Loader.File);
            }
            if (g.Framework != null)
            {
                paths.AddRange(g.Framework.Files);
            }
            foreach (var p in paths)
            {
                if (!GamePaths.TryNormalize(p, out _))
                {
                    throw new InvalidDataException($"games.json: ungueltiger Pfad \"{p}\" bei \"{g.Id}\".");
                }
            }
        }
    }
}
