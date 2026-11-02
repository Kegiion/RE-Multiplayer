using REMods.ModManager.Core.Install;
using REMods.ModManager.Core.Releases;

namespace REMods.ModManager.Core.Games;

public enum GameStatusKind
{
    NotFound,
    NotInstalled,
    Installed,
    UpdateAvailable,
}

/// <summary>Momentaufnahme eines Spiels: Ordner, installierte Version, neuestes Release.</summary>
public sealed record GameState(
    GameDefinition Game,
    string? Dir,
    bool Installed,
    InstallRecord? Record,
    ModRelease? Latest,
    uint? ExeTimestamp,
    bool FrameworkPresent,
    string? ReleaseError)
{
    /// <summary>null, wenn ohne Protokoll installiert (alter Installer oder per Hand).</summary>
    public ModVersion? InstalledVersion =>
        Record != null && ModVersion.TryParse(Record.Version, out var v) ? v : null;

    public GameStatusKind Kind =>
        Dir == null ? GameStatusKind.NotFound
        : !Installed ? GameStatusKind.NotInstalled
        : Latest != null && (InstalledVersion == null || Latest.Version > InstalledVersion) ? GameStatusKind.UpdateAvailable
        : GameStatusKind.Installed;

    public bool ExeSupported => Game.IsExeSupported(ExeTimestamp);

    /// <summary>Liest den Zustand eines Spielordners (ohne Netzwerk).</summary>
    public static GameState Read(GameDefinition game, string? dir, ModRelease? latest, string? releaseError)
    {
        if (dir == null)
        {
            return new GameState(game, null, false, null, latest, null, false, releaseError);
        }
        var installer = new ModInstaller(game, dir);
        return new GameState(game, dir, installer.IsInstalled, installer.ReadRecord(), latest,
            PeTimestamp.Read(Path.Combine(dir, game.Exe)), installer.FrameworkPresent, releaseError);
    }
}
