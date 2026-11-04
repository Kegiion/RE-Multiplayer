using System.Globalization;
using System.Text.RegularExpressions;
using REMultiplayer.ModManager.Core.Games;
using REMultiplayer.ModManager.Core.Localization;

namespace REMultiplayer.ModManager.Tests;

public partial class LocalizationTests
{
    private static readonly Localizer Loc = Localizer.Load();

    /// <summary>tools/modmanager (vom Testordner aus nach oben gesucht).</summary>
    private static string ManagerDir()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "tools", "modmanager", "games.json")))
        {
            dir = dir.Parent;
        }
        return Path.Combine(dir?.FullName ?? throw new DirectoryNotFoundException("Repo nicht gefunden"), "tools", "modmanager");
    }

    [Fact]
    public void GermanAndEnglishAreEmbedded()
    {
        Assert.True(Loc.Has("de"));
        Assert.True(Loc.Has("en"));
        Assert.Equal(new[] { "Deutsch", "English" }, Loc.Available.Select(p => p.Name));
    }

    [Fact]
    public void AllLanguagesHaveTheSameKeysAndPlaceholders()
    {
        var en = Loc.Available.Single(p => p.Code == "en");
        foreach (var pack in Loc.Available)
        {
            Assert.Empty(en.Strings.Keys.Except(pack.Strings.Keys));
            Assert.Empty(pack.Strings.Keys.Except(en.Strings.Keys));
            foreach (var (key, text) in pack.Strings)
            {
                Assert.True(Placeholders(text).SetEquals(Placeholders(en.Strings[key])), $"{pack.Code}: {key}");
            }
        }
    }

    [GeneratedRegex(@"\{(\d+)")]
    private static partial Regex Placeholder();

    private static HashSet<string> Placeholders(string text) =>
        Placeholder().Matches(text).Select(m => m.Groups[1].Value).ToHashSet();

    [GeneratedRegex(@"L\.T\(""([^""]+)""|\{l:T ([^}\s]+)\}")]
    private static partial Regex KeyUse();

    [Fact]
    public void EveryKeyUsedInCodeExists()
    {
        var en = Loc.Available.Single(p => p.Code == "en");
        var src = Path.Combine(ManagerDir(), "src");
        var used = Directory.EnumerateFiles(src, "*.*", SearchOption.AllDirectories)
            .Where(f => f.EndsWith(".cs", StringComparison.Ordinal) || f.EndsWith(".xaml", StringComparison.Ordinal))
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}"))
            .SelectMany(f => KeyUse().Matches(File.ReadAllText(f)))
            .Select(m => m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value)
            .Distinct()
            .ToList();
        Assert.True(used.Count > 50, $"nur {used.Count} Schluessel gefunden");
        Assert.Empty(used.Where(k => !en.Strings.ContainsKey(k)));
    }

    [Fact]
    public void ResolvePicksWindowsLanguageElseEnglish()
    {
        Assert.Equal("de", Loc.Resolve(null, new CultureInfo("de-AT")));
        Assert.Equal("en", Loc.Resolve(null, new CultureInfo("en-US")));
        Assert.Equal("en", Loc.Resolve(null, new CultureInfo("fr-FR")));
        Assert.Equal("en", Loc.Resolve("", CultureInfo.InvariantCulture));
        Assert.Equal("de", Loc.Resolve("de", new CultureInfo("en-US")));
        Assert.Equal("en", Loc.Resolve("xx", new CultureInfo("en-US"))); // unbekannte Einstellung -> automatisch
    }

    [Fact]
    public void TranslatesFormatsAndFallsBack()
    {
        var l = new Localizer(
        [
            new LanguagePack { Code = "de", Name = "Deutsch", Strings = { ["a"] = "Hallo {0}", ["nur.de"] = "nur deutsch" } },
            new LanguagePack { Code = "en", Name = "English", Strings = { ["a"] = "Hello {0}", ["kaputt"] = "{0" } },
            new LanguagePack { Code = "fr", Name = "Français", Strings = { ["a"] = "Bonjour {0}" } },
        ]);
        l.Use("de");
        Assert.Equal("Hallo Welt", l.T("a", "Welt"));
        l.Use("fr");
        Assert.Equal("Bonjour x", l.T("a", "x"));
        Assert.Equal("nur deutsch", l.T("nur.de"));   // fehlt in fr und en -> de
        Assert.Equal("{0", l.T("kaputt", 1));          // kaputtes Format stuerzt nicht ab
        Assert.Equal("gibt.es.nicht", l.T("gibt.es.nicht"));
        Assert.Equal("fr", l.Resolve(null, new CultureInfo("fr-CA")));
    }

    [Fact]
    public void ExtraLanguageFolderAddsLanguages()
    {
        using var tmp = new TempDir();
        tmp.Write("fr.json", """{ "code": "fr", "name": "Français", "strings": { "header.refresh": "Vérifier" } }""");
        tmp.Write("kaputt.json", "{ nicht json");
        var l = Localizer.Load(tmp.Path);
        Assert.True(l.Has("fr"));
        l.Use("fr");
        Assert.Equal("Vérifier", l.T("header.refresh"));
        Assert.Equal("Uninstall", l.T("card.uninstall")); // Rest aus Englisch
    }

    // ---- Patch Notes -------------------------------------------------------------

    private const string Bilingual = """
        **Wichtig fuer alle:** 1.2.0

        ### Deutsch

        - Neu: Sprache
        #### Details
        - mehr

        ### English

        - New: language
        """;

    [Fact]
    public void PatchNotesShowOnlyTheChosenLanguage()
    {
        var de = PatchNotes.ForLanguage(Bilingual, "de", Loc.Available);
        Assert.Contains("Neu: Sprache", de);
        Assert.Contains("#### Details", de);
        Assert.DoesNotContain("New: language", de);
        Assert.StartsWith("**Wichtig fuer alle:**", de);
        Assert.DoesNotContain("### Deutsch", de);

        var en = PatchNotes.ForLanguage(Bilingual, "en", Loc.Available);
        Assert.Contains("New: language", en);
        Assert.DoesNotContain("Neu: Sprache", en);
        Assert.StartsWith("**Wichtig fuer alle:**", en);
    }

    [Fact]
    public void PatchNotesFallBackToEnglishThenGermanThenWhole()
    {
        Assert.Contains("New: language", PatchNotes.ForLanguage(Bilingual, "fr", Loc.Available));
        var onlyGerman = "### Deutsch\n- nur deutsch";
        Assert.Equal("- nur deutsch", PatchNotes.ForLanguage(onlyGerman, "en", Loc.Available));
        // Alte Releases ohne Sprachabschnitte bleiben unveraendert
        var old = "- **Fett** alt\n### Bekannte Probleme\n- keine";
        Assert.Equal(old, PatchNotes.ForLanguage(old, "en", Loc.Available));
        Assert.Equal("", PatchNotes.ForLanguage(null, "en", Loc.Available));
    }

    [Fact]
    public void PatchNotesAcceptOtherHeadingSpellings()
    {
        var notes = "### german\r\n- a\r\n### ENGLISH ###\r\n- b\r\n### en\r\n- c";
        Assert.Equal("- a", PatchNotes.ForLanguage(notes, "de", Loc.Available));
        Assert.Equal("- b", PatchNotes.ForLanguage(notes, "en", Loc.Available));
    }

    [Fact]
    public void ManagerChangelogNewestSectionIsBilingual()
    {
        var lines = File.ReadAllLines(Path.Combine(ManagerDir(), "CHANGELOG.md"));
        var start = Array.FindIndex(lines, l => l.StartsWith("## ", StringComparison.Ordinal));
        var end = Array.FindIndex(lines, start + 1, l => l.StartsWith("## ", StringComparison.Ordinal));
        var section = string.Join("\n", lines[(start + 1)..(end < 0 ? lines.Length : end)]);
        var de = PatchNotes.ForLanguage(section, "de", Loc.Available);
        var en = PatchNotes.ForLanguage(section, "en", Loc.Available);
        Assert.NotEqual(de, en);
        Assert.NotEmpty(de);
        Assert.NotEmpty(en);
    }

    [Fact]
    public void GameHintsPerLanguage()
    {
        var re0 = GameCatalog.LoadEmbedded().Games.Single(g => g.Id == "re0hd");
        Assert.Equal(re0.Hint, re0.HintFor("de"));
        Assert.StartsWith("In the game", re0.HintFor("en"));
        Assert.StartsWith("In the game", re0.HintFor("fr"));
        var plain = new GameDefinition { Hint = "nur deutsch" };
        Assert.Equal("nur deutsch", plain.HintFor("en"));
    }
}
