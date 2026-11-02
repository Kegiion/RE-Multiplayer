namespace REMultiplayer.ModManager.Core.Install;

/// <summary>
/// Installationsprotokoll im Spielordner (z. B. remultiplayer/remultiplayer-install.json). Damit weiss der
/// Manager, welche Version installiert ist und welche Dateien er beim Deinstallieren entfernt.
/// </summary>
public sealed class InstallRecord
{
    public int Schema { get; set; } = 1;
    public string GameId { get; set; } = "";
    public string Version { get; set; } = "";
    public string Tag { get; set; } = "";
    public DateTimeOffset InstalledAt { get; set; }
    public string ManagerVersion { get; set; } = "";

    /// <summary>Alle Dateien der Mod, relativ zum Spielordner.</summary>
    public List<string> Files { get; set; } = [];

    /// <summary>true, wenn der Manager das Framework (REFramework) selbst installiert hat.</summary>
    public bool FrameworkInstalledByManager { get; set; }

    public List<string> FrameworkFiles { get; set; } = [];
}

public sealed class InstallException(string message, bool needsAdmin = false, Exception? inner = null)
    : Exception(message, inner)
{
    /// <summary>Keine Schreibrechte im Spielordner: als Administrator neu versuchen.</summary>
    public bool NeedsAdmin { get; } = needsAdmin;
}
