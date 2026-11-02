using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using REMultiplayer.ModManager.Core;
using REMultiplayer.ModManager.Core.Games;
using REMultiplayer.ModManager.Core.Releases;
using REMultiplayer.ModManager.Core.Reports;

namespace REMultiplayer.ModManager.Tests;

public class CatalogTests
{
    [Fact]
    public void EmbeddedCatalogIsValid()
    {
        var c = GameCatalog.LoadEmbedded();
        Assert.Contains(c.Games, g => g.Id == "re0hd" && g.SteamAppId == 339340 && g.Exe == "re0hd.exe");
        Assert.Contains(c.Games, g => g.Id == "re2r" && g.SteamAppId == 883710 && g.Framework != null);
    }

    [Fact]
    public void RejectsUnknownSchemaAndBadPaths()
    {
        Assert.Throws<InvalidDataException>(() => GameCatalog.Parse("{\"schema\": 99, \"games\": []}"));
        Assert.Throws<InvalidDataException>(() => GameCatalog.Parse("kein json"));
        const string bad = """
            { "schema": 2, "games": [ { "id": "x", "name": "X", "exe": "x.exe", "tagPrefix": "x-v", "assetPrefix": "X-",
              "installedMarker": "a", "recordPath": "b", "legacyDirs": [ "../../Windows" ] } ] }
            """;
        Assert.Throws<InvalidDataException>(() => GameCatalog.Parse(bad));
    }
}

public class BugReportTests
{
    [Fact]
    public void SanitizesProfileAndIps()
    {
        var text = BugReport.Sanitize(@"Pfad C:\Users\Jonas\Desktop\a, Peer 192.168.1.20:27350, lokal 127.0.0.1",
            @"C:\Users\Jonas");
        Assert.Equal(@"Pfad %USERPROFILE%\Desktop\a, Peer x.x.x.x:27350, lokal 127.0.0.1", text);
    }

    [Fact]
    public void TailKeepsLastLines()
    {
        Assert.Equal("c\nd", BugReport.Tail("a\r\nb\r\nc\r\nd\r\n", 2));
        Assert.Equal("a", BugReport.Tail("a", 5));
    }

    [Fact]
    public void IssueUrlIsEncodedAndShortened()
    {
        var url = BugReport.BuildIssueUrl("Kegiion/RE-Multiplayer", "[re0hd] Absturz & mehr", "Zeile 1\nZeile 2");
        Assert.StartsWith("https://github.com/Kegiion/RE-Multiplayer/issues/new?title=%5Bre0hd%5D%20Absturz%20%26%20mehr&body=", url);
        Assert.Contains("Zeile%201%0AZeile%202", url);

        var longUrl = BugReport.BuildIssueUrl("Kegiion/RE-Multiplayer", "t", new string('ä', 20000));
        Assert.True(longUrl.Length <= BugReport.MaxUrlLength);
        Assert.Contains(Uri.EscapeDataString("gekürzt"), longUrl);
    }

    [Fact]
    public void ZipContainsSanitizedLogsAndInfo()
    {
        using var tmp = new TempDir();
        var log = tmp.Write("remultiplayer_re0.log", "verbunden mit 10.0.0.5");
        var zipPath = tmp.File("bericht.zip");
        BugReport.CreateZip(zipPath, "Manager 1.0.0", [log, tmp.File("fehlt.log")], null);

        using var zip = ZipFile.OpenRead(zipPath);
        Assert.Equal("verbunden mit x.x.x.x", Read(zip, "remultiplayer_re0.log"));
        Assert.StartsWith("Manager 1.0.0", Read(zip, "info.txt"));
        Assert.Contains("fehlt.log", Read(zip, "info.txt"));
    }

    private static string Read(ZipArchive zip, string name)
    {
        using var r = new StreamReader(zip.GetEntry(name)!.Open());
        return r.ReadToEnd();
    }
}

public class SelfUpdaterTests
{
    [Fact]
    public async Task SwapsExeAndCleansUp()
    {
        using var tmp = new TempDir();
        var exe = tmp.Write("RE-Multiplayer.exe", "alt");
        var neu = tmp.Write("RE-Multiplayer.exe.new", "neu");

        SelfUpdater.Swap(exe, neu);
        Assert.Equal("neu", File.ReadAllText(exe));
        Assert.Equal("alt", File.ReadAllText(SelfUpdater.OldPath(exe)));
        Assert.False(File.Exists(neu));

        await SelfUpdater.CleanupAsync(exe);
        Assert.False(File.Exists(SelfUpdater.OldPath(exe)));
    }
}

public class DownloadTests
{
    private sealed class FakeHandler(byte[] body) : HttpMessageHandler
    {
        public Uri? LastUri { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastUri = request.RequestUri;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(body) });
        }
    }

    private static readonly byte[] Body = "Paketinhalt"u8.ToArray();

    private static GhAsset Asset(string? digest, long size = 0, string url = "https://github.com/Kegiion/RE-Multiplayer/releases/download/x/a.zip") =>
        new() { Name = "a.zip", DownloadUrl = url, Size = size == 0 ? Body.Length : size, Digest = digest };

    [Fact]
    public async Task AcceptsMatchingDigest()
    {
        using var tmp = new TempDir();
        using var gh = new GitHubClient("test", new FakeHandler(Body));
        var digest = "sha256:" + Convert.ToHexString(SHA256.HashData(Body)).ToLowerInvariant();
        var dest = tmp.File("a.zip");
        await gh.DownloadAsync(Asset(digest), dest);
        Assert.Equal(Body, File.ReadAllBytes(dest));
    }

    [Fact]
    public async Task RejectsWrongDigestWrongSizeAndForeignHost()
    {
        using var tmp = new TempDir();
        using var gh = new GitHubClient("test", new FakeHandler(Body));
        var dest = tmp.File("a.zip");

        await Assert.ThrowsAsync<GitHubException>(() => gh.DownloadAsync(Asset("sha256:00"), dest));
        await Assert.ThrowsAsync<GitHubException>(() => gh.DownloadAsync(Asset(null, size: 999), dest));
        await Assert.ThrowsAsync<GitHubException>(() => gh.DownloadAsync(Asset(null, url: "https://example.com/a.zip"), dest));
        await Assert.ThrowsAsync<GitHubException>(() => gh.DownloadAsync(Asset(null, url: "http://github.com/a.zip"), dest));
        Assert.False(File.Exists(dest));
        Assert.False(File.Exists(dest + ".part"));
    }
}
