using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;

namespace REMods.ModManager.Core.Reports;

/// <summary>
/// "Fehler melden": Logs einsammeln und ein vorausgefuelltes GitHub-Issue bauen.
/// Kein Token: Der Spieler schickt das Issue selbst im Browser ab.
/// </summary>
public static partial class BugReport
{
    /// <summary>Laengere Adressen schneiden manche Browser bzw. GitHub ab.</summary>
    public const int MaxUrlLength = 7500;

    [GeneratedRegex(@"\b(?:\d{1,3}\.){3}\d{1,3}\b")]
    private static partial Regex Ipv4();

    /// <summary>Entfernt Benutzerordner und IP-Adressen (ausser localhost) aus Texten.</summary>
    public static string Sanitize(string text, string? userProfile)
    {
        if (!string.IsNullOrEmpty(userProfile) && userProfile.Length > 3)
        {
            text = text.Replace(userProfile, "%USERPROFILE%", StringComparison.OrdinalIgnoreCase);
            text = text.Replace(userProfile.Replace('\\', '/'), "%USERPROFILE%", StringComparison.OrdinalIgnoreCase);
        }
        return Ipv4().Replace(text, m => m.Value is "127.0.0.1" or "0.0.0.0" ? m.Value : "x.x.x.x");
    }

    public static string Tail(string text, int lines)
    {
        var all = text.Replace("\r\n", "\n").TrimEnd('\n').Split('\n');
        return string.Join('\n', all.Skip(Math.Max(0, all.Length - lines)));
    }

    /// <summary>Liest eine Datei, auch wenn das Spiel sie gerade offen hat.</summary>
    public static string ReadShared(string path)
    {
        using var f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var r = new StreamReader(f, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        return r.ReadToEnd();
    }

    /// <summary>Adresse fuer ein neues Issue mit Titel und Text. Zu lange Texte werden gekuerzt.</summary>
    public static string BuildIssueUrl(string repo, string title, string body, int maxLength = MaxUrlLength)
    {
        var baseUrl = $"https://github.com/{repo}/issues/new?title={Uri.EscapeDataString(title)}&body=";
        var url = baseUrl + Uri.EscapeDataString(body);
        const string cut = "\n\n… (gekürzt, alles steht in der ZIP-Datei)";
        while (url.Length > maxLength && body.Length > 0)
        {
            body = body[..(int)(body.Length * 0.85)];
            url = baseUrl + Uri.EscapeDataString(body + cut);
        }
        return url;
    }

    /// <summary>
    /// ZIP mit info.txt und den angegebenen Dateien (Texte bereinigt). Fehlende Dateien
    /// werden in info.txt vermerkt statt einen Fehler auszuloesen.
    /// </summary>
    public static void CreateZip(string zipPath, string infoText, IEnumerable<string> files, string? userProfile)
    {
        var missing = new List<string>();
        if (File.Exists(zipPath))
        {
            File.Delete(zipPath);
        }
        using var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create);
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "info.txt" };
        foreach (var file in files)
        {
            string content;
            try
            {
                content = ReadShared(file);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                missing.Add($"{Path.GetFileName(file)}: {e.Message}");
                continue;
            }
            var name = Path.GetFileName(file);
            for (var i = 2; !used.Add(name); i++)
            {
                name = $"{Path.GetFileNameWithoutExtension(file)}-{i}{Path.GetExtension(file)}";
            }
            WriteEntry(zip, name, Sanitize(content, userProfile));
        }
        if (missing.Count > 0)
        {
            infoText += "\n\nNicht lesbar:\n" + string.Join('\n', missing);
        }
        WriteEntry(zip, "info.txt", Sanitize(infoText, userProfile));
    }

    private static void WriteEntry(ZipArchive zip, string name, string text)
    {
        var entry = zip.CreateEntry(name, CompressionLevel.Optimal);
        using var w = new StreamWriter(entry.Open(), new UTF8Encoding(false));
        w.Write(text);
    }
}
