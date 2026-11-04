using System.Globalization;
using System.Windows;
using System.Windows.Threading;
using REMultiplayer.ModManager.Core;
using REMultiplayer.ModManager.Core.Localization;

namespace REMultiplayer.ModManager;

public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Directory.CreateDirectory(AppInfo.DataDir);
        if (!File.Exists(AppInfo.SettingsFile) && File.Exists(AppInfo.LegacySettingsFile))
        {
            File.Copy(AppInfo.LegacySettingsFile, AppInfo.SettingsFile);
        }
        ManagerLog.FilePath = AppInfo.LogFile;
        DispatcherUnhandledException += OnUnhandled;

        var args = CommandLine.Parse(e.Args);
        if (args.Headless)
        {
            Shutdown(Headless.Run(args));
            return;
        }

        // Sprachen: eingebaute plus eigene Dateien in %LOCALAPPDATA%\RE-Multiplayer\lang
        L.Instance = Localizer.Load(Path.Combine(AppInfo.DataDir, "lang"));
        var settings = ManagerSettings.Load(AppInfo.SettingsFile);
        var vm = new MainViewModel(settings);
        vm.ApplyLanguage(args.Lang != null && L.Instance.Has(args.Lang)
            ? args.Lang.ToLowerInvariant()
            : L.Instance.Resolve(settings.Language, CultureInfo.CurrentUICulture));
        var window = new MainWindow { DataContext = vm };

        if (args.Screenshot != null)
        {
            var code = 0;
            try
            {
                if (args.Demo)
                {
                    vm.LoadDemo();
                }
                else
                {
                    await vm.InitializeAsync(null, null);
                }
                if (args.Notes)
                {
                    Screenshot.Save(NotesWindow.Create("RE:Multiplayer Mod-Manager", vm.DemoReleases), args.Screenshot,
                        args.Width, args.Height);
                }
                else
                {
                    Screenshot.Save(window, args.Screenshot, args.Width, args.Height);
                }
            }
            catch (Exception ex)
            {
                ManagerLog.Error("Bildschirmfoto fehlgeschlagen", ex);
                code = 1;
            }
            Shutdown(code);
            return;
        }

        MainWindow = window;
        window.Show();
        await vm.InitializeAsync(args.Resume, args.Path);
    }

    private static void OnUnhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        ManagerLog.Error("Unerwarteter Fehler", e.Exception);
        MessageBox.Show(L.T("dialog.unexpected", e.Exception.Message, AppInfo.LogFile),
            "RE:Multiplayer Mod-Manager", MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }
}
