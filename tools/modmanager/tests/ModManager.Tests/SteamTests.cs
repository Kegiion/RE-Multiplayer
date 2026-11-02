using REMods.ModManager.Core.Steam;

namespace REMods.ModManager.Tests;

public class SteamTests
{
    [Fact]
    public void ParsesNewLibraryFoldersFormat()
    {
        const string vdf = """
            "libraryfolders"
            {
                "0"
                {
                    "path"		"C:\\Program Files (x86)\\Steam"
                    "label"		""
                    "apps"
                    {
                        "339340"		"12345"
                    }
                }
                "1"
                {
                    "path"		"D:\\SteamLibrary"
                }
            }
            """;
        var root = Vdf.Parse(vdf);
        var folders = root["libraryfolders"]!;
        Assert.Equal(@"C:\Program Files (x86)\Steam", folders["0"]!["path"]!.Value);
        Assert.Equal(@"D:\SteamLibrary", folders["1"]!["path"]!.Value);
        Assert.Equal("12345", folders["0"]!["apps"]!["339340"]!.Value);
    }

    [Fact]
    public void ParsesCommentsAndEscapes()
    {
        var root = Vdf.Parse("// Kommentar\n\"a\" { \"b\" \"x\\\"y\" }");
        Assert.Equal("x\"y", root["a"]!["b"]!.Value);
    }

    [Fact]
    public void FindsGameInSecondLibrary()
    {
        using var steam = new TempDir();
        using var lib = new TempDir();
        steam.Write("steamapps/libraryfolders.vdf",
            $"\"libraryfolders\" {{ \"0\" {{ \"path\" \"{Escape(steam.Path)}\" }} \"1\" {{ \"path\" \"{Escape(lib.Path)}\" }} }}");
        lib.Write("steamapps/appmanifest_339340.acf",
            "\"AppState\" { \"appid\" \"339340\" \"installdir\" \"Resident Evil 0\" }");
        lib.Write("steamapps/common/Resident Evil 0/re0hd.exe", "MZ");

        var libs = SteamLocator.LibraryFolders(steam.Path);
        Assert.Equal(2, libs.Count); // Steam-Ordner nicht doppelt

        var dir = SteamLocator.FindGame(libs, 339340, "re0hd.exe");
        Assert.Equal(Path.Combine(lib.Path, "steamapps", "common", "Resident Evil 0"), dir);
    }

    [Fact]
    public void IgnoresManifestWithoutExe()
    {
        using var steam = new TempDir();
        steam.Write("steamapps/appmanifest_883710.acf", "\"AppState\" { \"installdir\" \"RE2\" }");
        Assert.Null(SteamLocator.FindGame([steam.Path], 883710, "re2.exe"));
    }

    [Fact]
    public void ParsesOldLibraryFoldersFormat()
    {
        using var steam = new TempDir();
        steam.Write("steamapps/libraryfolders.vdf",
            "\"LibraryFolders\" { \"TimeNextStatsReport\" \"123\" \"1\" \"E:\\\\Games\" }");
        var libs = SteamLocator.LibraryFolders(steam.Path);
        Assert.Equal(new[] { steam.Path, @"E:\Games" }, libs);
    }

    private static string Escape(string path) => path.Replace("\\", "\\\\");
}
