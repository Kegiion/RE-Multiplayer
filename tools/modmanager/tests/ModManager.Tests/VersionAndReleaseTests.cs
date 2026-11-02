using System.Text.Json;
using REMultiplayer.ModManager.Core;
using REMultiplayer.ModManager.Core.Games;
using REMultiplayer.ModManager.Core.Install;
using REMultiplayer.ModManager.Core.Releases;

namespace REMultiplayer.ModManager.Tests;

public class VersionAndReleaseTests
{
    [Theory]
    [InlineData("0.4.0", "0.3.9")]
    [InlineData("0.10.0", "0.9.0")]
    [InlineData("1.0.0", "1.0.0-beta.2")]
    [InlineData("1.0.0-beta.10", "1.0.0-beta.2")]
    [InlineData("1.0.0-rc.1", "1.0.0-beta.9")]
    [InlineData("v2.0", "1.99.99")]
    public void ComparesVersions(string newer, string older)
    {
        Assert.True(ModVersion.Parse(newer) > ModVersion.Parse(older));
        Assert.True(ModVersion.Parse(older) < ModVersion.Parse(newer));
    }

    [Fact]
    public void TrailingZerosAreEqual()
    {
        Assert.Equal(ModVersion.Parse("1.0"), ModVersion.Parse("1.0.0"));
        Assert.Equal(ModVersion.Parse("1.0").GetHashCode(), ModVersion.Parse("1.0.0").GetHashCode());
        Assert.Equal("1.2.3", ModVersion.Parse("1.2.3+abcdef").ToString());
    }

    [Theory]
    [InlineData("")]
    [InlineData("abc")]
    [InlineData("1..2")]
    [InlineData("1.2-")]
    [InlineData("-1.0")]
    public void RejectsInvalidVersions(string text) => Assert.False(ModVersion.TryParse(text, out _));

    private const string ReleasesJson = """
        [
          { "tag_name": "re0hd-v0.5.0-beta.1", "name": "RE0 Beta", "prerelease": true, "draft": false, "body": "beta",
            "assets": [ { "name": "RE0HD-Coop-0.5.0-beta.1.zip", "browser_download_url": "https://github.com/x/y/a.zip", "size": 10 } ] },
          { "tag_name": "re0hd-v0.4.0", "name": "RE0 0.4.0", "prerelease": false, "draft": false, "body": "## Neu\n- Geister",
            "published_at": "2026-11-02T10:00:00Z",
            "assets": [ { "name": "RE0HD-Coop-0.4.0.zip", "browser_download_url": "https://github.com/x/y/b.zip", "size": 20,
                          "digest": "sha256:00ff" } ] },
          { "tag_name": "re0hd-v0.6.0", "draft": true, "prerelease": false, "assets": [] },
          { "tag_name": "re2r-v0.3.1", "prerelease": false, "draft": false, "assets": [] },
          { "tag_name": "re0hd-vkaputt", "prerelease": false, "draft": false, "assets": [] },
          { "tag_name": "re0hd-v0.3.0", "prerelease": false, "draft": false, "assets": [] }
        ]
        """;

    [Fact]
    public void SelectsReleasesForPrefix()
    {
        var all = JsonSerializer.Deserialize<List<GhRelease>>(ReleasesJson)!;

        var stable = ReleaseSelector.ForPrefix(all, "re0hd-v", includePrereleases: false);
        Assert.Equal(new[] { "re0hd-v0.4.0", "re0hd-v0.3.0" }, stable.Select(r => r.Tag));
        Assert.Equal("## Neu\n- Geister", stable[0].Notes);
        var asset = stable[0].FindAsset("RE0HD-Coop-", ".zip")!;
        Assert.Equal("sha256:00ff", asset.Digest);
        Assert.Equal(20, asset.Size);

        var withBeta = ReleaseSelector.ForPrefix(all, "re0hd-v", includePrereleases: true);
        Assert.Equal("re0hd-v0.5.0-beta.1", withBeta[0].Tag);
        Assert.True(withBeta[0].Prerelease);

        Assert.Single(ReleaseSelector.ForPrefix(all, "re2r-v", false));
        Assert.Empty(ReleaseSelector.ForPrefix(all, "manager-v", true));
    }

    [Fact]
    public void ComputesGameStatus()
    {
        var game = GameCatalog.LoadEmbedded().Games.First(g => g.Id == "re0hd");
        var latest = new ModRelease("re0hd-v0.4.0", ModVersion.Parse("0.4.0"), "t", "", false, null, null, []);
        var record = new InstallRecord { Version = "0.3.0" };

        Assert.Equal(GameStatusKind.NotFound, new GameState(game, null, false, null, latest, null, true, null).Kind);
        Assert.Equal(GameStatusKind.NotInstalled, new GameState(game, "d", false, null, latest, null, true, null).Kind);
        Assert.Equal(GameStatusKind.UpdateAvailable, new GameState(game, "d", true, record, latest, null, true, null).Kind);
        // Ohne Protokoll (alter Installer) ist die Version unbekannt -> Update anbieten
        Assert.Equal(GameStatusKind.UpdateAvailable, new GameState(game, "d", true, null, latest, null, true, null).Kind);
        record.Version = "0.4.0";
        Assert.Equal(GameStatusKind.Installed, new GameState(game, "d", true, record, latest, null, true, null).Kind);
        // Kein Release erreichbar: installiert bleibt installiert
        Assert.Equal(GameStatusKind.Installed, new GameState(game, "d", true, null, null, null, true, "offline").Kind);
    }
}
