using System.Runtime.Versioning;
using System.Security;
using Microsoft.Win32;

namespace REMods.ModManager.Core.Steam;

/// <summary>Findet Steam, alle Steam-Bibliotheken und darin installierte Spiele.</summary>
public static class SteamLocator
{
    /// <summary>Steam-Ordner aus der Registry (HKCU SteamPath, sonst HKLM InstallPath).</summary>
    public static string? FindSteamRoot()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        var path = ReadRegistry(Registry.CurrentUser, @"Software\Valve\Steam", "SteamPath")
                   ?? ReadRegistry(Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath")
                   ?? ReadRegistry(Registry.LocalMachine, @"SOFTWARE\Valve\Steam", "InstallPath");
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }
        // SteamPath steht mit Schraegstrichen in der Registry ("c:/program files (x86)/steam")
        path = Path.GetFullPath(path);
        return Directory.Exists(path) ? path : null;
    }

    [SupportedOSPlatform("windows")]
    private static string? ReadRegistry(RegistryKey root, string key, string value)
    {
        try
        {
            using var k = root.OpenSubKey(key);
            return k?.GetValue(value) as string;
        }
        catch (Exception e) when (e is SecurityException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>Alle Bibliotheksordner: der Steam-Ordner selbst plus die Eintraege aus libraryfolders.vdf.</summary>
    public static List<string> LibraryFolders(string steamRoot)
    {
        var libs = new List<string> { steamRoot };
        var vdfPath = Path.Combine(steamRoot, "steamapps", "libraryfolders.vdf");
        if (!File.Exists(vdfPath))
        {
            return libs;
        }
        VdfNode root;
        try
        {
            root = Vdf.Parse(File.ReadAllText(vdfPath));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return libs;
        }
        var folders = root["libraryfolders"];
        if (folders == null)
        {
            return libs;
        }
        foreach (var (key, node) in folders.Children)
        {
            // Neues Format: "0" { "path" "D:\\SteamLibrary" ... }, altes Format: "1" "D:\\SteamLibrary"
            var path = node.Value != null
                ? (int.TryParse(key, out _) ? node.Value : null)
                : node["path"]?.Value;
            if (string.IsNullOrWhiteSpace(path))
            {
                continue;
            }
            if (!libs.Any(l => SamePath(l, path)))
            {
                libs.Add(path);
            }
        }
        return libs;
    }

    /// <summary>Spielordner eines Steam-Spiels oder null. Prueft, dass die exe dort liegt.</summary>
    public static string? FindGame(IEnumerable<string> libraries, int appId, string exe)
    {
        foreach (var lib in libraries)
        {
            var steamapps = Path.Combine(lib, "steamapps");
            var acf = Path.Combine(steamapps, $"appmanifest_{appId}.acf");
            if (!File.Exists(acf))
            {
                continue;
            }
            string? installDir;
            try
            {
                installDir = Vdf.Parse(File.ReadAllText(acf))["AppState"]?["installdir"]?.Value;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            if (string.IsNullOrWhiteSpace(installDir))
            {
                continue;
            }
            var dir = Path.Combine(steamapps, "common", installDir);
            if (File.Exists(Path.Combine(dir, exe)))
            {
                return dir;
            }
        }
        return null;
    }

    private static bool SamePath(string a, string b) =>
        string.Equals(Normalize(a), Normalize(b), StringComparison.OrdinalIgnoreCase);

    private static string Normalize(string p) =>
        p.Replace('\\', '/').TrimEnd('/');
}
