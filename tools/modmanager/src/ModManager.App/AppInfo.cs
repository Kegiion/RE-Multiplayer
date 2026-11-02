using System.Reflection;

namespace REMods.ModManager;

/// <summary>Feste Angaben zum Manager und seine Ablageorte.</summary>
public static class AppInfo
{
    public const string Repo = "Kegiion/REMods";
    public const string ManagerTagPrefix = "manager-v";
    public const string ManagerAssetName = "REMods-Manager.exe";

    /// <summary>Neuere Spiele-Liste aus dem Repo (faellt auf die eingebaute zurueck).</summary>
    public const string RemoteCatalogUrl = "https://raw.githubusercontent.com/" + Repo + "/main/tools/modmanager/games.json";

    private static readonly string Informational =
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
        ?? "0.0.0";

    /// <summary>Version ohne Build-Anhang, z. B. "1.0.0".</summary>
    public static string Version => Informational.Split('+')[0];

    /// <summary>Kurzer Git-Commit, aus dem gebaut wurde, oder "lokal".</summary>
    public static string BuildId
    {
        get
        {
            var plus = Informational.IndexOf('+');
            if (plus < 0)
            {
                return "lokal";
            }
            var hash = Informational[(plus + 1)..];
            return hash.Length > 7 ? hash[..7] : hash;
        }
    }

    public static string UserAgent => $"REMods-Manager/{Version}";

    public static string DataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "REMods");

    public static string SettingsFile => Path.Combine(DataDir, "settings.json");

    public static string LogFile => Path.Combine(DataDir, "manager.log");

    public static string DownloadDir => Path.Combine(Path.GetTempPath(), "REMods");

    public static string ExePath => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "REMods-Manager.exe");
}
