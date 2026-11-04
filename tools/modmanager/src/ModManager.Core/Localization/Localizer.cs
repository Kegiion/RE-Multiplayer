using System.Globalization;
using System.Reflection;
using System.Text.Json;

namespace REMultiplayer.ModManager.Core.Localization;

/// <summary>
/// Eine Sprache des Managers (tools/modmanager/lang/&lt;code&gt;.json).
/// Neue Sprache = neue JSON-Datei in lang/, kein Code noetig.
/// </summary>
public sealed class LanguagePack
{
    /// <summary>Zweibuchstabiger Sprachcode (ISO 639-1), z. B. "de".</summary>
    public string Code { get; set; } = "";

    /// <summary>Name der Sprache in der Sprache selbst, z. B. "Deutsch".</summary>
    public string Name { get; set; } = "";

    /// <summary>Weitere Ueberschriften, unter denen Patch Notes diese Sprache kennzeichnen (z. B. "German").</summary>
    public List<string> NotesHeadings { get; set; } = [];

    /// <summary>Datumsformat fuer Patch Notes.</summary>
    public string DateFormat { get; set; } = "d";

    public Dictionary<string, string> Strings { get; set; } = new();

    /// <summary>Kennzeichnet die Ueberschrift diese Sprache? (Name, Code oder NotesHeadings, ohne Gross/klein)</summary>
    public bool MatchesHeading(string heading)
    {
        heading = heading.Trim();
        return heading.Equals(Name, StringComparison.OrdinalIgnoreCase)
               || heading.Equals(Code, StringComparison.OrdinalIgnoreCase)
               || NotesHeadings.Any(h => heading.Equals(h, StringComparison.OrdinalIgnoreCase));
    }

    public static LanguagePack Parse(string json)
    {
        LanguagePack? p;
        try
        {
            p = JsonSerializer.Deserialize<LanguagePack>(json, Json.Options);
        }
        catch (JsonException e)
        {
            throw new InvalidDataException("Sprachdatei ist kein gueltiges JSON: " + e.Message, e);
        }
        if (p == null || p.Code.Length != 2 || p.Name.Length == 0 || p.Strings.Count == 0)
        {
            throw new InvalidDataException("Sprachdatei unvollstaendig (code, name, strings).");
        }
        p.Code = p.Code.ToLowerInvariant();
        return p;
    }
}

/// <summary>Texte in der gewaehlten Sprache. Fehlt ein Text, gilt Englisch, dann Deutsch, dann der Schluessel.</summary>
public sealed class Localizer
{
    public const string English = "en";
    public const string German = "de";

    private readonly Dictionary<string, LanguagePack> packs = new(StringComparer.OrdinalIgnoreCase);

    public Localizer(IEnumerable<LanguagePack> languages)
    {
        foreach (var p in languages)
        {
            packs[p.Code] = p; // spaetere (z. B. aus dem Datenordner) ersetzen eingebaute
        }
        if (packs.Count == 0)
        {
            throw new InvalidDataException("Keine Sprachen vorhanden.");
        }
        Current = packs.GetValueOrDefault(English) ?? packs.Values.First();
    }

    public LanguagePack Current { get; private set; }

    /// <summary>Alle Sprachen, nach Namen sortiert.</summary>
    public IReadOnlyList<LanguagePack> Available =>
        packs.Values.OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase).ToList();

    public CultureInfo Culture
    {
        get
        {
            try
            {
                return CultureInfo.GetCultureInfo(Current.Code);
            }
            catch (CultureNotFoundException)
            {
                return CultureInfo.InvariantCulture; // z. B. Sprachcode, den Windows nicht kennt
            }
        }
    }

    public bool Has(string code) => packs.ContainsKey(code);

    /// <summary>
    /// Sprache aus der Einstellung (Code) oder, wenn leer/unbekannt, aus der Windows-Sprache.
    /// Windows-Sprache ohne eigene Sprachdatei -> Englisch.
    /// </summary>
    public string Resolve(string? setting, CultureInfo uiCulture)
    {
        if (!string.IsNullOrWhiteSpace(setting) && Has(setting))
        {
            return setting.ToLowerInvariant();
        }
        var system = uiCulture.TwoLetterISOLanguageName;
        if (Has(system))
        {
            return system.ToLowerInvariant();
        }
        return Has(English) ? English : Current.Code;
    }

    public void Use(string code)
    {
        if (packs.TryGetValue(code, out var p))
        {
            Current = p;
        }
    }

    public string T(string key, params object?[] args)
    {
        var text = Lookup(key);
        if (args.Length == 0)
        {
            return text;
        }
        try
        {
            return string.Format(Culture, text, args);
        }
        catch (FormatException)
        {
            return text; // kaputte Uebersetzung darf nichts abstuerzen lassen
        }
    }

    private string Lookup(string key)
    {
        foreach (var code in new[] { Current.Code, English, German })
        {
            if (packs.TryGetValue(code, out var p) && p.Strings.TryGetValue(key, out var text))
            {
                return text;
            }
        }
        return key;
    }

    /// <summary>Eingebaute Sprachen (lang/*.json in der exe) plus optional weitere aus einem Ordner.</summary>
    public static Localizer Load(string? extraDir = null)
    {
        var list = new List<LanguagePack>();
        var asm = Assembly.GetExecutingAssembly();
        foreach (var name in asm.GetManifestResourceNames().Where(n => n.StartsWith("lang/", StringComparison.Ordinal)).Order())
        {
            using var s = asm.GetManifestResourceStream(name)!;
            using var r = new StreamReader(s);
            list.Add(LanguagePack.Parse(r.ReadToEnd()));
        }
        if (extraDir != null && Directory.Exists(extraDir))
        {
            foreach (var file in Directory.GetFiles(extraDir, "*.json").Order())
            {
                try
                {
                    list.Add(LanguagePack.Parse(File.ReadAllText(file)));
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException)
                {
                    ManagerLog.Error($"Sprachdatei {file} ignoriert", e);
                }
            }
        }
        return new Localizer(list);
    }
}

/// <summary>Globaler Zugriff auf die Texte (auch fuer Fehlermeldungen im Kern).</summary>
public static class L
{
    public static Localizer Instance { get; set; } = Localizer.Load();

    public static string T(string key, params object?[] args) => Instance.T(key, args);
}
