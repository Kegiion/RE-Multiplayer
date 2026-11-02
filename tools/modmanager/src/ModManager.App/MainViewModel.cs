using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;
using REMods.ModManager.Core;
using REMods.ModManager.Core.Games;
using REMods.ModManager.Core.Install;
using REMods.ModManager.Core.Releases;
using REMods.ModManager.Core.Reports;
using REMods.ModManager.Core.Steam;

namespace REMods.ModManager;

public sealed class MainViewModel : ObservableObject
{
    private readonly ManagerSettings settings;
    private readonly GitHubClient github = new(AppInfo.UserAgent);
    private GameCatalog catalog = GameCatalog.LoadEmbedded();
    private List<GhRelease>? releases;
    private string? releaseError;
    private ModRelease? managerUpdate;
    private readonly Dictionary<string, string> pathOverrides = new(StringComparer.OrdinalIgnoreCase);

    private bool busy;
    private double progress;
    private string status = "Bereit.";

    public MainViewModel(ManagerSettings settings)
    {
        this.settings = settings;
        RefreshCommand = new RelayCommand(RefreshAsync, () => !Busy);
        UpdateManagerCommand = new RelayCommand(UpdateManagerAsync, () => !Busy && managerUpdate != null);
        ShowManagerNotesCommand = new RelayCommand(ShowManagerNotes);
        foreach (var def in catalog.Games)
        {
            Games.Add(new GameViewModel(this, def));
        }
    }

    public ObservableCollection<GameViewModel> Games { get; } = [];

    public ICommand RefreshCommand { get; }
    public ICommand UpdateManagerCommand { get; }
    public ICommand ShowManagerNotesCommand { get; }

    public bool Busy
    {
        get => busy;
        private set
        {
            if (Set(ref busy, value))
            {
                CommandManager.InvalidateRequerySuggested();
            }
        }
    }

    public double Progress
    {
        get => progress;
        private set => Set(ref progress, value);
    }

    public string Status
    {
        get => status;
        private set => Set(ref status, value);
    }

    public string ManagerVersionText => $"Manager {AppInfo.Version} ({AppInfo.BuildId})";

    public bool ManagerUpdateVisible => managerUpdate != null;

    public string ManagerUpdateText => managerUpdate == null ? "" : $"Neue Manager-Version {managerUpdate.Version} verfügbar";

    public bool IncludePrereleases
    {
        get => settings.IncludePrereleases;
        set
        {
            if (settings.IncludePrereleases == value)
            {
                return;
            }
            settings.IncludePrereleases = value;
            settings.Save(AppInfo.SettingsFile);
            Raise();
            ApplyReleases();
        }
    }

    // ---- Start und Aktualisieren ----------------------------------------------

    /// <summary>resume: "install:re0hd" o. ae. nach einem Neustart als Administrator.</summary>
    public async Task InitializeAsync(string? resume, string? resumePath)
    {
        _ = SelfUpdater.CleanupAsync(AppInfo.ExePath);
        ManagerLog.Info($"Start, Manager {AppInfo.Version} ({AppInfo.BuildId}), Administrator: {Elevation.IsElevated}");

        // Neuere Spiele-Liste aus dem Repo, wenn gueltig und vom selben Schema
        var remote = await github.TryGetTextAsync(AppInfo.RemoteCatalogUrl);
        if (remote != null)
        {
            try
            {
                var c = GameCatalog.Parse(remote);
                catalog = c;
                Games.Clear();
                foreach (var def in catalog.Games)
                {
                    Games.Add(new GameViewModel(this, def));
                }
            }
            catch (InvalidDataException e)
            {
                ManagerLog.Error("Spiele-Liste aus dem Repo ignoriert", e);
            }
        }

        string? resumeAction = null;
        GameViewModel? resumeGame = null;
        if (resume?.Split(':') is [var action, var id])
        {
            resumeAction = action;
            resumeGame = Games.FirstOrDefault(g => g.Def.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
            if (resumeGame != null && resumePath != null)
            {
                pathOverrides[resumeGame.Def.Id] = resumePath;
            }
        }

        await RefreshAsync();

        if (resumeGame != null)
        {
            if (resumeAction == "install")
            {
                await InstallAsync(resumeGame);
            }
            else if (resumeAction == "uninstall")
            {
                await UninstallAsync(resumeGame, confirm: false);
            }
        }
    }

    public async Task RefreshAsync()
    {
        if (Busy)
        {
            return;
        }
        Busy = true;
        Status = "Suche Spiele und Updates …";
        try
        {
            try
            {
                releases = await github.GetReleasesAsync(AppInfo.Repo);
                releaseError = null;
            }
            catch (Exception e) when (e is GitHubException or HttpRequestException or TaskCanceledException)
            {
                releases = null;
                releaseError = e is GitHubException ? e.Message : "GitHub ist nicht erreichbar.";
                ManagerLog.Error("Releases nicht abrufbar", e);
            }
            ApplyReleases();
            Status = releaseError ?? $"Zuletzt geprüft um {DateTime.Now:HH:mm} Uhr.";
        }
        finally
        {
            Busy = false;
        }
    }

    /// <summary>Spielordner suchen und Zustand aller Karten neu berechnen (ohne Netzwerk).</summary>
    private void ApplyReleases()
    {
        var steam = SteamLocator.FindSteamRoot();
        var libraries = steam != null ? SteamLocator.LibraryFolders(steam) : new List<string>();
        foreach (var g in Games)
        {
            var dir = FindDir(g.Def, libraries);
            var latest = releases == null ? null : ReleaseSelector.ForPrefix(releases, g.Def.TagPrefix, IncludePrereleases).FirstOrDefault();
            g.Apply(GameState.Read(g.Def, dir, latest, releaseError));
        }
        var current = ModVersion.TryParse(AppInfo.Version, out var v) ? v : null;
        managerUpdate = releases == null ? null
            : ReleaseSelector.ForPrefix(releases, AppInfo.ManagerTagPrefix, IncludePrereleases)
                .FirstOrDefault(r => current == null || r.Version > current);
        Raise(nameof(ManagerUpdateVisible));
        Raise(nameof(ManagerUpdateText));
        CommandManager.InvalidateRequerySuggested();
    }

    private string? FindDir(GameDefinition def, List<string> libraries)
    {
        foreach (var candidate in new[]
                 {
                     pathOverrides.GetValueOrDefault(def.Id),
                     settings.GamePaths.GetValueOrDefault(def.Id),
                 })
        {
            if (candidate != null && File.Exists(Path.Combine(candidate, def.Exe)))
            {
                return candidate;
            }
        }
        return SteamLocator.FindGame(libraries, def.SteamAppId, def.Exe);
    }

    private void RefreshGame(GameViewModel g)
    {
        var latest = releases == null ? null : ReleaseSelector.ForPrefix(releases, g.Def.TagPrefix, IncludePrereleases).FirstOrDefault();
        g.Apply(GameState.Read(g.Def, g.State.Dir, latest, releaseError));
    }

    // ---- Aktionen ---------------------------------------------------------------

    public async Task InstallAsync(GameViewModel g)
    {
        var dir = g.State.Dir;
        var release = g.State.Latest;
        if (dir == null || release == null || Busy)
        {
            return;
        }
        if (IsRunning(g.Def))
        {
            Dialogs.Warn($"Bitte zuerst {g.Name} beenden.");
            return;
        }
        var asset = release.FindAsset(g.Def.AssetPrefix, ".zip");
        if (asset == null)
        {
            Dialogs.Error($"Im Release {release.Tag} fehlt die Datei {g.Def.AssetPrefix}….zip.");
            return;
        }
        if (!g.State.ExeSupported)
        {
            var ts = g.State.ExeTimestamp is { } t ? $"0x{t:X8}" : "unbekannt";
            if (!Dialogs.Confirm($"Deine {g.Def.Exe} hat eine andere Version (Zeitstempel {ts}) als die, für die die Mod gebaut ist.\n"
                                 + "Das Menü funktioniert, der Koop bleibt aber eventuell aus.\n\nTrotzdem installieren?"))
            {
                return;
            }
        }
        var fw = g.Def.Framework;
        var needFramework = fw != null && !g.State.FrameworkPresent;
        if (needFramework && !Dialogs.Confirm($"{g.Name} braucht {fw!.Name}. Der Manager lädt die aktuelle Version von "
                                              + $"github.com/{fw.Repo} und installiert sie mit.\n\nEinverstanden?"))
        {
            return;
        }

        var ok = await RunBusy(g, "install", async report =>
        {
            Directory.CreateDirectory(AppInfo.DownloadDir);
            var package = Path.Combine(AppInfo.DownloadDir, asset.Name);
            Status = $"{g.Name}: lade {asset.Name} …";
            await github.DownloadAsync(asset, package, report);

            string? frameworkZip = null;
            if (needFramework)
            {
                Status = $"{g.Name}: lade {fw!.Name} …";
                var fwRelease = await github.GetLatestReleaseAsync(fw.Repo)
                                ?? throw new GitHubException($"{fw.Name}: kein Release gefunden.");
                var fwAsset = fwRelease.Assets.FirstOrDefault(a => a.Name.Equals(fw.Asset, StringComparison.OrdinalIgnoreCase))
                              ?? throw new GitHubException($"{fw.Name}: {fw.Asset} fehlt im neuesten Release.");
                frameworkZip = Path.Combine(AppInfo.DownloadDir, $"{fw.Name}-{fwAsset.Name}");
                await github.DownloadAsync(fwAsset, frameworkZip, report);
                ManagerLog.Info($"{fw.Name} {fwRelease.TagName} geladen");
            }

            Status = $"{g.Name}: installiere …";
            await Task.Run(() => new ModInstaller(g.Def, dir).Install(package, frameworkZip, release.Version.ToString(),
                release.Tag, AppInfo.Version));
            TryDelete(package);
            if (frameworkZip != null)
            {
                TryDelete(frameworkZip);
            }
            ManagerLog.Info($"{g.Def.Id} {release.Version} installiert nach {dir}");
        });
        RefreshGame(g);
        if (ok)
        {
            Status = $"{g.Name}: Version {release.Version} installiert.";
            Dialogs.Info($"Fertig! {g.Name}: Koop-Mod {release.Version} ist installiert."
                         + (string.IsNullOrEmpty(g.Def.Hint) ? "" : "\n\n" + g.Def.Hint));
        }
    }

    public Task UninstallAsync(GameViewModel g) => UninstallAsync(g, confirm: true);

    private async Task UninstallAsync(GameViewModel g, bool confirm)
    {
        var dir = g.State.Dir;
        if (dir == null || Busy)
        {
            return;
        }
        if (IsRunning(g.Def))
        {
            Dialogs.Warn($"Bitte zuerst {g.Name} beenden.");
            return;
        }
        if (confirm && !Dialogs.Confirm($"Koop-Mod aus {g.Name} entfernen?\n\nDeine Einstellungen bleiben erhalten."))
        {
            return;
        }
        var ok = await RunBusy(g, "uninstall", async _ =>
        {
            Status = $"{g.Name}: entferne Mod …";
            await Task.Run(() => new ModInstaller(g.Def, dir).Uninstall());
            ManagerLog.Info($"{g.Def.Id} deinstalliert aus {dir}");
        });
        RefreshGame(g);
        if (ok)
        {
            Status = $"{g.Name}: Mod entfernt.";
            Dialogs.Info($"Die Koop-Mod wurde aus {g.Name} entfernt. Deine Einstellungen sind noch da.");
        }
    }

    /// <summary>Fuehrt eine Aktion mit Fortschrittsbalken aus und zeigt Fehler verstaendlich an.</summary>
    private async Task<bool> RunBusy(GameViewModel g, string action, Func<IProgress<double>, Task> work)
    {
        Busy = true;
        Progress = 0;
        var report = new Progress<double>(p => Progress = p * 100);
        try
        {
            await work(report);
            return true;
        }
        catch (InstallException e) when (e.NeedsAdmin)
        {
            ManagerLog.Error($"{g.Def.Id}: Schreibrechte fehlen", e);
            Status = "Administratorrechte nötig.";
            if (Elevation.IsElevated)
            {
                Dialogs.Error("Im Spielordner kann nicht geschrieben werden, auch nicht als Administrator.\n\n"
                              + "Läuft das Spiel noch? Ist eine Datei schreibgeschützt?");
            }
            else if (Dialogs.Confirm("Für den Spielordner braucht der Manager Administratorrechte.\n\n"
                                     + "Als Administrator neu starten und weitermachen?"))
            {
                var args = $"--resume {action}:{g.Def.Id} --path {Elevation.Quote(g.State.Dir!)}";
                if (Elevation.RestartElevated(args))
                {
                    Application.Current.Shutdown();
                }
            }
            return false;
        }
        catch (Exception e) when (e is InstallException or GitHubException or HttpRequestException or IOException
                                      or InvalidDataException or UnauthorizedAccessException or TaskCanceledException)
        {
            ManagerLog.Error($"{g.Def.Id}: {action} fehlgeschlagen", e);
            Status = "Fehlgeschlagen: " + e.Message;
            Dialogs.Error(e.Message);
            return false;
        }
        finally
        {
            Busy = false;
            Progress = 0;
        }
    }

    // ---- Manager selbst aktualisieren -------------------------------------------

    private async Task UpdateManagerAsync()
    {
        var update = managerUpdate;
        var asset = update?.FindAsset("REMods-Manager", ".exe");
        if (update == null || asset == null || Busy)
        {
            if (update != null && asset == null)
            {
                Dialogs.Error($"Im Release {update.Tag} fehlt {AppInfo.ManagerAssetName}.");
            }
            return;
        }
        var exe = AppInfo.ExePath;
        var newFile = exe + ".new";
        Busy = true;
        Progress = 0;
        try
        {
            Status = $"Lade Manager {update.Version} …";
            await github.DownloadAsync(asset, newFile, new Progress<double>(p => Progress = p * 100));
            SelfUpdater.Swap(exe, newFile);
            ManagerLog.Info($"Manager aktualisiert auf {update.Version}");
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true });
            Application.Current.Shutdown();
        }
        catch (UnauthorizedAccessException e)
        {
            ManagerLog.Error("Selbst-Update: keine Schreibrechte", e);
            TryDelete(newFile);
            Dialogs.Error("Der Manager darf sich in seinem Ordner nicht ersetzen.\n\n"
                          + "Bitte REMods-Manager.exe z. B. auf den Desktop oder in Downloads verschieben und neu starten.");
        }
        catch (Exception e) when (e is GitHubException or HttpRequestException or IOException or TaskCanceledException)
        {
            ManagerLog.Error("Selbst-Update fehlgeschlagen", e);
            TryDelete(newFile);
            Dialogs.Error("Update fehlgeschlagen: " + e.Message);
        }
        finally
        {
            Busy = false;
            Progress = 0;
        }
    }

    private void ShowManagerNotes()
    {
        if (releases == null)
        {
            return;
        }
        var list = ReleaseSelector.ForPrefix(releases, AppInfo.ManagerTagPrefix, IncludePrereleases);
        NotesWindow.ShowFor("REMods Mod-Manager", list);
    }

    // ---- Kleinere Aktionen --------------------------------------------------------

    public bool HasNotes(GameDefinition def) =>
        releases != null && ReleaseSelector.ForPrefix(releases, def.TagPrefix, IncludePrereleases).Count > 0;

    public void ShowNotes(GameViewModel g)
    {
        if (releases != null)
        {
            NotesWindow.ShowFor(g.Name, ReleaseSelector.ForPrefix(releases, g.Def.TagPrefix, IncludePrereleases));
        }
    }

    public void OpenFolder(GameViewModel g)
    {
        if (g.State.Dir != null)
        {
            Process.Start(new ProcessStartInfo("explorer.exe", Elevation.Quote(g.State.Dir)) { UseShellExecute = true });
        }
    }

    public void ChooseFolder(GameViewModel g)
    {
        var dialog = new OpenFolderDialog { Title = $"Ordner von {g.Name} wählen (dort liegt {g.Def.Exe})" };
        if (g.State.Dir != null)
        {
            dialog.InitialDirectory = g.State.Dir;
        }
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        var folder = dialog.FolderName;
        if (!File.Exists(Path.Combine(folder, g.Def.Exe)))
        {
            Dialogs.Error($"In diesem Ordner liegt keine {g.Def.Exe}.");
            return;
        }
        settings.GamePaths[g.Def.Id] = folder;
        settings.Save(AppInfo.SettingsFile);
        pathOverrides.Remove(g.Def.Id);
        var latest = releases == null ? null : ReleaseSelector.ForPrefix(releases, g.Def.TagPrefix, IncludePrereleases).FirstOrDefault();
        g.Apply(GameState.Read(g.Def, folder, latest, releaseError));
    }

    /// <summary>Logs als ZIP auf den Desktop legen und ein vorausgefuelltes GitHub-Issue oeffnen.</summary>
    public void ReportBug(GameViewModel g)
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var s = g.State;
        var info = new StringBuilder()
            .AppendLine($"Spiel: {g.Name} ({g.Def.Id})")
            .AppendLine($"Mod installiert: {(s.Installed ? s.InstalledVersion?.ToString() ?? "unbekannt" : "nein")}")
            .AppendLine($"Neueste Mod-Version: {s.Latest?.Version.ToString() ?? "–"}")
            .AppendLine($"Spiel-exe Zeitstempel: {(s.ExeTimestamp is { } t ? $"0x{t:X8}" : "–")}"
                        + (s.ExeSupported ? "" : " (nicht die unterstützte Version)"))
            .AppendLine(g.Def.Framework != null ? $"{g.Def.Framework.Name} vorhanden: {(s.FrameworkPresent ? "ja" : "nein")}" : "")
            .AppendLine($"Spielordner: {s.Dir ?? "nicht gefunden"}")
            .AppendLine($"Manager: {AppInfo.Version} ({AppInfo.BuildId})")
            .AppendLine($"Windows: {RuntimeInformation.OSDescription}")
            .ToString().Replace("\r\n", "\n").Replace("\n\n", "\n").TrimEnd();

        var files = new List<string>();
        if (s.Dir != null)
        {
            files.AddRange(g.Def.Logs.Select(l => GamePaths.Resolve(s.Dir, l)).Where(File.Exists));
            var record = new ModInstaller(g.Def, s.Dir).RecordFile;
            if (File.Exists(record))
            {
                files.Add(record);
            }
        }
        if (File.Exists(AppInfo.LogFile))
        {
            files.Add(AppInfo.LogFile);
        }

        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        var zipPath = Path.Combine(desktop, $"REMods-Fehlerbericht-{g.Def.Id}-{DateTime.Now:yyyyMMdd-HHmm}.zip");
        try
        {
            BugReport.CreateZip(zipPath, info, files, profile);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            ManagerLog.Error("Fehlerbericht nicht erstellt", e);
            Dialogs.Error("Der Fehlerbericht konnte nicht gespeichert werden: " + e.Message);
            return;
        }

        var tail = "";
        var mainLog = s.Dir == null ? null : g.Def.Logs.Select(l => GamePaths.Resolve(s.Dir, l)).FirstOrDefault(File.Exists);
        if (mainLog != null)
        {
            try
            {
                tail = BugReport.Sanitize(BugReport.Tail(BugReport.ReadShared(mainLog), 40), profile);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                tail = "(Log nicht lesbar: " + e.Message + ")";
            }
        }
        var body = "**Was ist passiert?**\n\n\n\n**Was hast du erwartet?**\n\n\n\n**Wie kann man es nachstellen?**\n\n1. \n\n"
                   + "---\n" + BugReport.Sanitize(info, profile).Replace("\n", "  \n") + "\n\n"
                   + (tail.Length > 0 ? $"<details><summary>Log (letzte Zeilen)</summary>\n\n```\n{tail}\n```\n</details>\n\n" : "")
                   + $"Bitte die Datei `{Path.GetFileName(zipPath)}` vom Desktop hier hineinziehen.";
        var url = BugReport.BuildIssueUrl(AppInfo.Repo, $"[{g.Def.Id}] ", body);

        Dialogs.Info("Der Fehlerbericht liegt auf deinem Desktop:\n" + Path.GetFileName(zipPath) + "\n\n"
                     + "Gleich öffnet sich GitHub mit einem vorausgefüllten Fehlerbericht. Bitte kurz beschreiben, "
                     + "was passiert ist, und die ZIP-Datei hineinziehen. Dafür brauchst du ein GitHub-Konto.\n\n"
                     + "Bitte vor dem Absenden kurz durchlesen: Benutzername und IP-Adressen sind schon entfernt.");
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        Process.Start(new ProcessStartInfo("explorer.exe", "/select," + Elevation.Quote(zipPath)) { UseShellExecute = true });
    }

    // ---- Demo fuer Bildschirmfotos -------------------------------------------------

    /// <summary>Beispielzustand ohne Netzwerk und ohne echte Spielordner (--screenshot --demo).</summary>
    public void LoadDemo()
    {
        static ModRelease Rel(string tag, string version, bool pre = false) =>
            new(tag, ModVersion.Parse(version), tag, "", pre, DateTimeOffset.Now, null, []);

        foreach (var g in Games)
        {
            g.Apply(g.Def.Id switch
            {
                "re0hd" => new GameState(g.Def, @"C:\Program Files (x86)\Steam\steamapps\common\Resident Evil 0", true,
                    new InstallRecord { Version = "0.3.0" }, Rel("re0hd-v0.4.0", "0.4.0"), 0x6799D40F, true, null),
                "re2r" => new GameState(g.Def, @"D:\SteamLibrary\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2", false, null,
                    Rel("re2r-v0.3.1", "0.3.1"), null, false, null),
                _ => new GameState(g.Def, null, false, null, null, null, false, null),
            });
        }
        managerUpdate = Rel("manager-v1.1.0", "1.1.0");
        Raise(nameof(ManagerUpdateVisible));
        Raise(nameof(ManagerUpdateText));
        Status = "Zuletzt geprüft um 12:00 Uhr.";
    }

    // ---- Hilfen ---------------------------------------------------------------------

    private static bool IsRunning(GameDefinition def)
    {
        if (string.IsNullOrEmpty(def.ProcessName))
        {
            return false;
        }
        var procs = Process.GetProcessesByName(def.ProcessName);
        foreach (var p in procs)
        {
            p.Dispose();
        }
        return procs.Length > 0;
    }

    private static void TryDelete(string file)
    {
        try
        {
            File.Delete(file);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            ManagerLog.Error($"Konnte {file} nicht löschen", e);
        }
    }
}
