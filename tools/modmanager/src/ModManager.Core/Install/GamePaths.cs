using REMultiplayer.ModManager.Core.Localization;

namespace REMultiplayer.ModManager.Core.Install;

/// <summary>
/// Relative Pfade im Spielordner. Intern immer mit "/" getrennt. Alles, was aus dem
/// Spielordner herausfuehren koennte (absolute Pfade, "..", Laufwerke), wird abgelehnt.
/// </summary>
public static class GamePaths
{
    public static bool TryNormalize(string relative, out string normalized)
    {
        normalized = "";
        var r = relative.Replace('\\', '/').Trim();
        while (r.StartsWith("./", StringComparison.Ordinal))
        {
            r = r[2..];
        }
        if (r.Length == 0 || r.StartsWith('/') || r.Contains(':'))
        {
            return false;
        }
        var parts = r.Split('/');
        if (parts.Any(p => p.Length == 0 || p == "." || p == ".."))
        {
            return false;
        }
        normalized = r;
        return true;
    }

    public static string Normalize(string relative) =>
        TryNormalize(relative, out var n) ? n : throw new InstallException(L.T("error.invalidPackagePath", relative));

    /// <summary>Voller Pfad im Spielordner. Wirft, wenn der Pfad aus dem Ordner herausfuehrt.</summary>
    public static string Resolve(string root, string relative)
    {
        var n = Normalize(relative);
        var rootFull = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        var full = Path.GetFullPath(Path.Combine(rootFull, n.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(rootFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            throw new InstallException(L.T("error.invalidPackagePath", relative));
        }
        return full;
    }

    /// <summary>Liegt der Pfad in (oder ist gleich) prefix? Beide relativ, Gross/Klein egal.</summary>
    public static bool IsUnder(string relative, string prefix)
    {
        var r = relative.Replace('\\', '/').Trim('/');
        var p = prefix.Replace('\\', '/').Trim('/');
        return r.Equals(p, StringComparison.OrdinalIgnoreCase)
               || r.StartsWith(p + "/", StringComparison.OrdinalIgnoreCase);
    }
}
