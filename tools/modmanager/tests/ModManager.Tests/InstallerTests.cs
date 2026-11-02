using System.Text;
using REMods.ModManager.Core.Games;
using REMods.ModManager.Core.Install;

namespace REMods.ModManager.Tests;

public class InstallerTests
{
    private static readonly GameCatalog Catalog = GameCatalog.LoadEmbedded();

    private static GameDefinition Re0 => Catalog.Games.First(g => g.Id == "re0hd");

    private static GameDefinition Re2 => Catalog.Games.First(g => g.Id == "re2r");

    /// <summary>Loader-Attrappe: enthaelt wie der echte Loader den Runtime-Pfad als UTF-16.</summary>
    private static byte[] OurLoader =>
        "MZ"u8.ToArray().Concat(Encoding.Unicode.GetBytes(@"remods\remods_re0.dll")).Concat(new byte[2]).ToArray();

    private static string Re0Package(TempDir tmp, string name, params string[] luaFiles)
    {
        var entries = new Dictionary<string, byte[]>
        {
            ["dinput8.dll"] = OurLoader,
            ["remods/remods_re0.dll"] = TempDir.Text("runtime"),
            ["remods/"] = [], // Ordner-Eintrag wird ignoriert
        };
        foreach (var f in luaFiles)
        {
            entries["remods/autorun/" + f] = TempDir.Text("-- " + f);
        }
        return tmp.Zip(name, entries);
    }

    [Fact]
    public void InstallUpdateUninstallRe0()
    {
        using var tmp = new TempDir();
        using var game = new TempDir();
        game.Write("re0hd.exe", "MZ");
        game.Write("dinput8.dll", "fremde Mod");
        game.Write("remods/data/settings.json", "{\"x\":1}");
        var installer = new ModInstaller(Re0, game.Path);
        Assert.False(installer.IsInstalled);

        // Installieren
        var record = installer.Install(Re0Package(tmp, "a.zip", "re0hd_coop.lua", "alt.lua"), null, "0.4.0", "re0hd-v0.4.0", "1.0.0");
        Assert.True(installer.IsInstalled);
        Assert.Equal("fremde Mod", game.Read("dinput8.dll.vor-remods"));
        Assert.True(installer.IsOurLoader(game.File("dinput8.dll")));
        Assert.True(game.Exists("remods/autorun/alt.lua"));
        Assert.Equal("0.4.0", installer.ReadRecord()!.Version);
        Assert.DoesNotContain("remods/", record.Files);

        // Aktualisieren: alt.lua gibt es nicht mehr, neu.lua ist dazugekommen
        installer.Install(Re0Package(tmp, "b.zip", "re0hd_coop.lua", "neu.lua"), null, "0.5.0", "re0hd-v0.5.0", "1.0.0");
        Assert.False(game.Exists("remods/autorun/alt.lua"));
        Assert.True(game.Exists("remods/autorun/neu.lua"));
        Assert.Equal("fremde Mod", game.Read("dinput8.dll.vor-remods")); // Sicherung nicht durch unseren Loader ersetzt
        Assert.Equal("0.5.0", installer.ReadRecord()!.Version);

        // Deinstallieren
        installer.Uninstall();
        Assert.False(installer.IsInstalled);
        Assert.Equal("fremde Mod", game.Read("dinput8.dll"));
        Assert.False(game.Exists("dinput8.dll.vor-remods"));
        Assert.False(Directory.Exists(game.File("remods/autorun")));
        Assert.Equal("{\"x\":1}", game.Read("remods/data/settings.json"));
    }

    [Fact]
    public void UninstallWithoutRecordLikeOldInstaller()
    {
        using var game = new TempDir();
        game.Write("re0hd.exe", "MZ");
        game.WriteBytes("dinput8.dll", OurLoader);
        game.Write("dinput8.dll.vor-remods", "fremde Mod");
        game.Write("remods/remods_re0.dll", "runtime");
        game.Write("remods/autorun/remods_coop/session.lua", "--");
        game.Write("remods/remods_re0.log", "log");
        game.Write("remods/data/re0hd_coop.json", "{}");

        var installer = new ModInstaller(Re0, game.Path);
        Assert.True(installer.IsInstalled);
        Assert.Null(installer.ReadRecord());

        installer.Uninstall();
        Assert.False(game.Exists("remods/remods_re0.dll"));
        Assert.False(game.Exists("remods/remods_re0.log"));
        Assert.False(Directory.Exists(game.File("remods/autorun")));
        Assert.True(game.Exists("remods/data/re0hd_coop.json"));
        Assert.Equal("fremde Mod", game.Read("dinput8.dll"));
    }

    [Fact]
    public void NeverDeletesForeignLoader()
    {
        using var game = new TempDir();
        game.Write("re0hd.exe", "MZ");
        game.Write("dinput8.dll", "andere Mod, nach uns installiert");
        game.Write("remods/remods_re0.dll", "runtime");

        new ModInstaller(Re0, game.Path).Uninstall();
        Assert.Equal("andere Mod, nach uns installiert", game.Read("dinput8.dll"));
        Assert.False(game.Exists("remods/remods_re0.dll"));
    }

    [Fact]
    public void RejectsZipSlip()
    {
        using var tmp = new TempDir();
        using var game = new TempDir();
        game.Write("re0hd.exe", "MZ");
        var zip = tmp.Zip("boese.zip", new Dictionary<string, byte[]>
        {
            ["remods/ok.lua"] = TempDir.Text("ok"),
            ["../draussen.txt"] = TempDir.Text("x"),
        });

        var e = Assert.Throws<InstallException>(() =>
            new ModInstaller(Re0, game.Path).Install(zip, null, "1.0.0", "t", "1.0.0"));
        Assert.False(e.NeedsAdmin);
        Assert.False(game.Exists("remods/ok.lua")); // nichts geschrieben
        Assert.False(File.Exists(Path.Combine(Path.GetDirectoryName(game.Path)!, "draussen.txt")));
    }

    [Theory]
    [InlineData("../x")]
    [InlineData("a/../../x")]
    [InlineData("/etc/passwd")]
    [InlineData("C:/Windows/x.dll")]
    [InlineData("a//b")]
    [InlineData("")]
    public void RejectsBadPaths(string path) => Assert.False(GamePaths.TryNormalize(path, out _));

    [Fact]
    public void NormalizesBackslashes()
    {
        Assert.True(GamePaths.TryNormalize(@".\remods\autorun\a.lua", out var n));
        Assert.Equal("remods/autorun/a.lua", n);
        Assert.True(GamePaths.IsUnder("REMODS/Data/x.json", "remods/data"));
        Assert.False(GamePaths.IsUnder("remods/database.lua", "remods/data"));
    }

    [Fact]
    public void Re2InstallsFrameworkAndRemovesOnlyWhatItInstalled()
    {
        using var tmp = new TempDir();
        using var game = new TempDir();
        game.Write("re2.exe", "MZ");
        var pkg = tmp.Zip("RE2R-Coop-0.3.1.zip", new Dictionary<string, byte[]>
        {
            ["reframework/plugins/remods_coopnet.dll"] = TempDir.Text("plugin"),
            ["reframework/autorun/re2r_coop.lua"] = TempDir.Text("--"),
            ["reframework/autorun/re2r_coop/ghost.lua"] = TempDir.Text("--"),
        });
        var fw = tmp.Zip("RE2.zip", new Dictionary<string, byte[]>
        {
            ["dinput8.dll"] = TempDir.Text("REFramework"),
            ["openvr_api.dll"] = TempDir.Text("vr"),
        });

        var installer = new ModInstaller(Re2, game.Path);
        Assert.False(installer.FrameworkPresent);
        installer.Install(pkg, fw, "0.3.1", "re2r-v0.3.1", "1.0.0");
        Assert.True(installer.FrameworkPresent);
        Assert.False(game.Exists("openvr_api.dll")); // nur die gelisteten Dateien
        Assert.True(installer.ReadRecord()!.FrameworkInstalledByManager);

        // Update ohne Framework-ZIP behaelt die Framework-Angaben
        installer.Install(pkg, null, "0.3.2", "re2r-v0.3.2", "1.0.0");
        Assert.True(installer.ReadRecord()!.FrameworkInstalledByManager);

        game.Write("reframework/data/re2r_coop.json", "{}");
        installer.Uninstall();
        Assert.False(game.Exists("dinput8.dll"));
        Assert.False(game.Exists("reframework/plugins/remods_coopnet.dll"));
        Assert.False(Directory.Exists(game.File("reframework/autorun")));
        Assert.True(game.Exists("reframework/data/re2r_coop.json"));
    }

    [Fact]
    public void Re2KeepsFrameworkInstalledByUser()
    {
        using var tmp = new TempDir();
        using var game = new TempDir();
        game.Write("re2.exe", "MZ");
        game.Write("dinput8.dll", "REFramework vom Spieler");
        var pkg = tmp.Zip("p.zip", new Dictionary<string, byte[]>
        {
            ["reframework/plugins/remods_coopnet.dll"] = TempDir.Text("plugin"),
        });
        var installer = new ModInstaller(Re2, game.Path);
        Assert.True(installer.FrameworkPresent);
        installer.Install(pkg, null, "0.3.1", "re2r-v0.3.1", "1.0.0");
        installer.Uninstall();
        Assert.Equal("REFramework vom Spieler", game.Read("dinput8.dll"));
    }

    [Fact]
    public void ReadsPeTimestamp()
    {
        using var tmp = new TempDir();
        var pe = new byte[0x100];
        pe[0] = (byte)'M';
        pe[1] = (byte)'Z';
        BitConverter.GetBytes(0x80).CopyTo(pe, 0x3C);
        "PE\0\0"u8.ToArray().CopyTo(pe, 0x80);
        BitConverter.GetBytes(0x6799D40Fu).CopyTo(pe, 0x88);
        var exe = tmp.WriteBytes("re0hd.exe", pe);

        var ts = PeTimestamp.Read(exe);
        Assert.Equal(0x6799D40Fu, ts);
        Assert.True(Re0.IsExeSupported(ts));
        Assert.False(Re0.IsExeSupported(0x12345678));
        Assert.False(Re0.IsExeSupported(null));
        Assert.True(Re2.IsExeSupported(null)); // keine Liste = keine Pruefung
        Assert.Null(PeTimestamp.Read(tmp.Write("kaputt.exe", "kein PE")));
    }
}
