using System.Text.RegularExpressions;

namespace REMultiplayer.ModManager.Core.Localization;

/// <summary>
/// Zweisprachige Patch Notes. Format im CHANGELOG (siehe tools/modmanager/README.md):
///
///   ## 1.2.0
///   (optional: Text fuer alle Sprachen)
///   ### Deutsch
///   - ...
///   ### English
///   - ...
///
/// Eine "### "-Ueberschrift gilt als Sprachabschnitt, wenn sie zu einer Sprachdatei passt
/// (Name, Code oder notesHeadings). Ohne Sprachabschnitte bleibt der Text unveraendert (alte Releases).
/// </summary>
public static partial class PatchNotes
{
    [GeneratedRegex(@"^###\s+(.+?)\s*#*\s*$")]
    private static partial Regex LanguageHeading();

    public static string ForLanguage(string? notes, string code, IReadOnlyList<LanguagePack> languages)
    {
        if (string.IsNullOrWhiteSpace(notes))
        {
            return notes ?? "";
        }
        var preamble = new List<string>();
        var sections = new List<(string Code, List<string> Lines)>();
        foreach (var line in notes.Replace("\r", "").Split('\n'))
        {
            var m = LanguageHeading().Match(line.TrimStart());
            var lang = m.Success ? languages.FirstOrDefault(l => l.MatchesHeading(m.Groups[1].Value)) : null;
            if (lang != null)
            {
                sections.Add((lang.Code, []));
            }
            else if (sections.Count > 0)
            {
                sections[^1].Lines.Add(line);
            }
            else
            {
                preamble.Add(line);
            }
        }
        if (sections.Count == 0)
        {
            return notes.Trim();
        }
        var pick = Find(code) ?? Find(Localizer.English) ?? Find(Localizer.German) ?? sections[0];
        var head = string.Join("\n", preamble).Trim();
        var body = string.Join("\n", pick.Lines).Trim();
        return head.Length == 0 ? body : head + "\n\n" + body;

        (string Code, List<string> Lines)? Find(string c) =>
            sections.Where(s => s.Code.Equals(c, StringComparison.OrdinalIgnoreCase))
                .Select(s => ((string, List<string>)?)s).FirstOrDefault();
    }
}
