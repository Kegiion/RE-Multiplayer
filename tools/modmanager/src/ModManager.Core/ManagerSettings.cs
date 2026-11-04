using System.Text;
using System.Text.Json;

namespace REMultiplayer.ModManager.Core;

/// <summary>Einstellungen des Managers (%LOCALAPPDATA%\RE-Multiplayer\settings.json).</summary>
public sealed class ManagerSettings
{
    /// <summary>Von Hand gewaehlte Spielordner, Schluessel = Spiel-Id.</summary>
    public Dictionary<string, string> GamePaths { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public bool IncludePrereleases { get; set; }

    /// <summary>Sprachcode ("de", "en", ...). Leer = Windows-Sprache.</summary>
    public string? Language { get; set; }

    public static ManagerSettings Load(string file)
    {
        try
        {
            if (File.Exists(file))
            {
                var s = JsonSerializer.Deserialize<ManagerSettings>(File.ReadAllText(file), Json.Options);
                if (s != null)
                {
                    s.GamePaths = new Dictionary<string, string>(s.GamePaths, StringComparer.OrdinalIgnoreCase);
                    return s;
                }
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            ManagerLog.Error("Einstellungen nicht lesbar", e);
        }
        return new ManagerSettings();
    }

    public void Save(string file)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.WriteAllText(file, JsonSerializer.Serialize(this, Json.Options));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            ManagerLog.Error("Einstellungen nicht speicherbar", e);
        }
    }
}

/// <summary>Einfaches Log des Managers (%LOCALAPPDATA%\RE-Multiplayer\manager.log).</summary>
public static class ManagerLog
{
    private const long MaxSize = 1024 * 1024;
    private static readonly object Gate = new();

    public static string? FilePath { get; set; }

    public static void Info(string message) => Write("INFO", message);

    public static void Error(string message, Exception? e = null) =>
        Write("FEHLER", e == null ? message : $"{message}: {e}");

    private static void Write(string level, string message)
    {
        var path = FilePath;
        if (path == null)
        {
            return;
        }
        lock (Gate)
        {
            try
            {
                var info = new FileInfo(path);
                if (info.Exists && info.Length > MaxSize)
                {
                    File.Move(path, path + ".1", overwrite: true);
                }
                File.AppendAllText(path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{level}] {message}{Environment.NewLine}",
                    Encoding.UTF8);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                // Log ist nur Hilfe, darf nie den Manager stoppen
            }
        }
    }
}
