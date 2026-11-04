using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;
using REMultiplayer.ModManager.Core;
using REMultiplayer.ModManager.Core.Games;
using REMultiplayer.ModManager.Core.Install;
using REMultiplayer.ModManager.Core.Localization;
using REMultiplayer.ModManager.Core.Releases;
using REMultiplayer.ModManager.Core.Reports;
using REMultiplayer.ModManager.Core.Steam;

namespace REMultiplayer.ModManager;

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
    private Func<string> status = () => L.T("status.ready");

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

    /// <summary>Statuszeile. Als Funktion gespeichert, damit sie beim Sprachwechsel neu uebersetzt wird.</summary>
    public string Status => status();

    private void SetStatus(Func<string> text)
    {
        status = text;
        Raise(nameof(Status));
    }

    // ---- Sprache ------------------------------------------------------------------

    /// <summary>"Automatisch" (Windows-Sprache) und alle Sprachdateien.</summary>
    public IReadOnlyList<LanguageOption> Languages { get; } =
        [new LanguageOption(""), .. L.Instance.Available.Select(p => new LanguageOption(p.Code))];

    /// <summary>Gewaehlte Sprache, "" = Windows-Sprache. Wird gespeichert und sofort angewendet.</summary>
    public string LanguageChoice
    {
        get => settings.Language ?? "";
        set
        {
            var v = string.IsNullOrEmpty(value) ? null : value;
            if (settings.Language == v)
            {
                return;
            }
            settings.Language = v;
            settings.Save(AppInfo.SettingsFile);
            ApplyLanguage(L.Instance.Resolve(v, System.Globalization.CultureInfo.CurrentUICulture));
            Raise();
        }
    }

    /// <summary>Sprache umschalten und alle berechneten Texte neu lesen.</summary>
    public void ApplyLanguage(string code)
    {
        Tr.Use(code);
        ManagerLog.Info($"Sprache: {code}");
        foreach (var o in Languages)
        {
            o.Refresh();
        }
        foreach (var g in Games)
        {
            g.Relocalize();
        }
        Raise(nameof(Status));
        Raise(nameof(ManagerUpdateText));
    }

    public string ManagerVersionText => $"Manager {AppInfo.Version} ({AppInfo.BuildId})";

    public bool ManagerUpdateVisible => managerUpdate != null;

    public string ManagerUpdateText => managerUpdate == null ? "" : L.T("update.available", managerUpdate.Version);

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
        SetStatus(() => L.T("status.checking"));
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
                releaseError = e is GitHubException ? e.Message : L.T("error.githubUnreachable");
                ManagerLog.Error("Releases nicht abrufbar", e);
            }
            ApplyReleases();
            var checkedAt = DateTime.Now;
            var error = releaseError;
            SetStatus(() => error ?? L.T("status.checkedAt", checkedAt));
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
            Dialogs.Warn(L.T("dialog.closeGameFirst", g.Name));
            return;
        }
        var asset = release.FindAsset(g.Def.AssetPrefix, ".zip");
        if (asset == null)
        {
            Dialogs.Error(L.T("dialog.assetMissing", release.Tag, g.Def.AssetPrefix));
            return;
        }
        if (!g.State.ExeSupported)
        {
            var ts = g.State.ExeTimestamp is { } t ? $"0x{t:X8}" : L.T("version.unknown");
            if (!Dialogs.Confirm(L.T("hint.exeVersion", g.Def.Exe, ts) + "\n\n" + L.T("dialog.installAnyway")))
            {
                return;
            }
        }
        var fw = g.Def.Framework;
        var needFramework = fw != null && !g.State.FrameworkPresent;
        if (needFramework && !Dialogs.Confirm(L.T("dialog.frameworkConfirm", g.Name, fw!.Name, fw.Repo)))
        {
            return;
        }

        var ok = await RunBusy(g, "install", async report =>
        {
            Directory.CreateDirectory(AppInfo.DownloadDir);
            var package = Path.Combine(AppInfo.DownloadDir, asset.Name);
            SetStatus(() => L.T("status.downloading", g.Name, asset.Name));
            await github.DownloadAsync(asset, package, report);

            string? frameworkZip = null;
            if (needFramework)
            {
                SetStatus(() => L.T("status.downloading", g.Name, fw!.Name));
                var fwRelease = await github.GetLatestReleaseAsync(fw.Repo)
                                ?? throw new GitHubException(L.T("error.frameworkNoRelease", fw.Name));
                var fwName = fw.PickAsset(fwRelease.Assets.Select(a => a.Name))
                             ?? throw new GitHubException(L.T("error.frameworkAssetMissing", fw.Name, fw.Asset));
                var fwAsset = fwRelease.Assets.First(a => a.Name == fwName);
                frameworkZip = Path.Combine(AppInfo.DownloadDir, $"{fw.Name}-{fwAsset.Name}");
                await github.DownloadAsync(fwAsset, frameworkZip, report);
                ManagerLog.Info($"{fw.Name} {fwRelease.TagName} geladen");
            }

            SetStatus(() => L.T("status.installing", g.Name));
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
            SetStatus(() => L.T("status.installed", g.Name, release.Version));
            var hint = g.Def.HintFor(L.Instance.Current.Code);
            Dialogs.Info(L.T("dialog.installed", g.Name, release.Version)
                         + (string.IsNullOrEmpty(hint) ? "" : "\n\n" + hint));
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
            Dialogs.Warn(L.T("dialog.closeGameFirst", g.Name));
            return;
        }
        if (confirm && !Dialogs.Confirm(L.T("dialog.uninstallConfirm", g.Name)))
        {
            return;
        }
        var ok = await RunBusy(g, "uninstall", async _ =>
        {
            SetStatus(() => L.T("status.uninstalling", g.Name));
            await Task.Run(() => new ModInstaller(g.Def, dir).Uninstall());
            ManagerLog.Info($"{g.Def.Id} deinstalliert aus {dir}");
        });
        RefreshGame(g);
        if (ok)
        {
            SetStatus(() => L.T("status.uninstalled", g.Name));
            Dialogs.Info(L.T("dialog.uninstalled", g.Name));
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
            SetStatus(() => L.T("status.adminNeeded"));
            if (Elevation.IsElevated)
            {
                Dialogs.Error(L.T("dialog.noWriteEvenAdmin"));
            }
            else if (Dialogs.Confirm(L.T("dialog.restartAdmin")))
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
            SetStatus(() => L.T("status.failed", e.Message));
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
        var asset = update?.FindAsset("RE-Multiplayer", ".exe");
        if (update == null || asset == null || Busy)
        {
            if (update != null && asset == null)
            {
                Dialogs.Error(L.T("dialog.managerAssetMissing", update.Tag, AppInfo.ManagerAssetName));
            }
            return;
        }
        var exe = AppInfo.ExePath;
        var newFile = exe + ".new";
        Busy = true;
        Progress = 0;
        try
        {
            SetStatus(() => L.T("status.downloadingManager", update.Version));
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
            Dialogs.Error(L.T("dialog.selfUpdateNoRights"));
        }
        catch (Exception e) when (e is GitHubException or HttpRequestException or IOException or TaskCanceledException)
        {
            ManagerLog.Error("Selbst-Update fehlgeschlagen", e);
            TryDelete(newFile);
            Dialogs.Error(L.T("dialog.selfUpdateFailed", e.Message));
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
        NotesWindow.ShowFor("RE:Multiplayer Mod-Manager", list);
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
        var dialog = new OpenFolderDialog { Title = L.T("dialog.chooseFolderTitle", g.Name, g.Def.Exe) };
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
            Dialogs.Error(L.T("dialog.exeNotInFolder", g.Def.Exe));
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
            .AppendLine(L.T("report.game", g.Name, g.Def.Id))
            .AppendLine(L.T("report.modInstalled",
                s.Installed ? s.InstalledVersion?.ToString() ?? L.T("version.unknown") : L.T("report.no")))
            .AppendLine(L.T("report.latest", s.Latest?.Version.ToString() ?? "–"))
            .AppendLine(L.T("report.exeTimestamp", s.ExeTimestamp is { } t ? $"0x{t:X8}" : "–")
                        + (s.ExeSupported ? "" : L.T("report.unsupported")))
            .AppendLine(g.Def.Framework != null
                ? L.T("report.framework", g.Def.Framework.Name, L.T(s.FrameworkPresent ? "report.yes" : "report.no"))
                : "")
            .AppendLine(L.T("report.folder", s.Dir ?? L.T("report.notFound")))
            .AppendLine(L.T("report.manager", AppInfo.Version, AppInfo.BuildId))
            .AppendLine(L.T("report.language", L.Instance.Current.Code))
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
        var zipPath = Path.Combine(desktop, $"{L.T("report.zipPrefix")}-{g.Def.Id}-{DateTime.Now:yyyyMMdd-HHmm}.zip");
        try
        {
            BugReport.CreateZip(zipPath, info, files, profile);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            ManagerLog.Error("Fehlerbericht nicht erstellt", e);
            Dialogs.Error(L.T("report.saveFailed", e.Message));
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
                tail = L.T("report.logUnreadable", e.Message);
            }
        }
        var body = $"**{L.T("report.whatHappened")}**\n\n\n\n**{L.T("report.expected")}**\n\n\n\n**{L.T("report.steps")}**\n\n1. \n\n"
                   + "---\n" + BugReport.Sanitize(info, profile).Replace("\n", "  \n") + "\n\n"
                   + (tail.Length > 0
                       ? $"<details><summary>{L.T("report.logTail")}</summary>\n\n```\n{tail}\n```\n</details>\n\n"
                       : "")
                   + L.T("report.dragZip", Path.GetFileName(zipPath));
        var url = BugReport.BuildIssueUrl(AppInfo.Repo, $"[{g.Def.Id}] ", body);

        Dialogs.Info(L.T("report.dialog", Path.GetFileName(zipPath)));
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        Process.Start(new ProcessStartInfo("explorer.exe", "/select," + Elevation.Quote(zipPath)) { UseShellExecute = true });
    }

    // ---- Demo fuer Bildschirmfotos -------------------------------------------------

    /// <summary>Zweisprachige Beispiel-Patch-Notes fuer --screenshot --notes.</summary>
    public const string DemoNotes =
        "### Deutsch\n\n- **Oberfläche auf Deutsch und Englisch.** Die Sprache richtet sich nach Windows.\n- Patch Notes in deiner Sprache.\n\n"
        + "### English\n\n- **Interface in German and English.** The language follows Windows.\n- Patch notes in your language.";

    public IReadOnlyList<ModRelease> DemoReleases { get; } =
    [
        new("manager-v1.2.0", ModVersion.Parse("1.2.0"), "manager-v1.2.0", DemoNotes, false, new DateTimeOffset(2026, 11, 4, 12, 0, 0, TimeSpan.Zero), null, []),
        new("manager-v1.1.1", ModVersion.Parse("1.1.1"), "manager-v1.1.1",
            "- **RE2: REFramework lässt sich wieder installieren.** Alte Patch Notes ohne Sprachabschnitte bleiben unverändert.",
            false, new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero), null, []),
    ];

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
        SetStatus(() => L.T("status.checkedAt", DateTime.Today.AddHours(12)));
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
