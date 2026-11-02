using REMods.ModManager.Core;
using REMods.ModManager.Core.Games;
using REMods.ModManager.Core.Install;

namespace REMods.ModManager;

/// <summary>Installieren/Deinstallieren ohne Fenster (fuer die CI). Exit-Codes: 0 ok, 1 Fehler, 2 Admin noetig, 3 Aufruf falsch.</summary>
public static class Headless
{
    public static int Run(CommandLine c)
    {
        var id = c.Install ?? c.Uninstall;
        var game = GameCatalog.LoadEmbedded().Games.FirstOrDefault(g => g.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
        if (game == null || c.Path == null || !File.Exists(Path.Combine(c.Path, game.Exe)))
        {
            ManagerLog.Error($"Aufruf falsch: Spiel '{id}', Ordner '{c.Path}'");
            return 3;
        }
        try
        {
            var installer = new ModInstaller(game, c.Path);
            if (c.Install != null)
            {
                if (c.Package == null || !File.Exists(c.Package))
                {
                    ManagerLog.Error($"Paket fehlt: '{c.Package}'");
                    return 3;
                }
                var version = c.Version ?? "0.0.0";
                installer.Install(c.Package, null, version, game.TagPrefix + version, AppInfo.Version);
                ManagerLog.Info($"{game.Id} {version} installiert nach {c.Path} (ohne Fenster)");
            }
            else
            {
                installer.Uninstall();
                ManagerLog.Info($"{game.Id} deinstalliert aus {c.Path} (ohne Fenster)");
            }
            return 0;
        }
        catch (InstallException e)
        {
            ManagerLog.Error("Ohne Fenster fehlgeschlagen", e);
            return e.NeedsAdmin ? 2 : 1;
        }
    }
}
