using System.Windows;
using System.Windows.Threading;
using REMultiplayer.ModManager.Core;

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

        var vm = new MainViewModel(ManagerSettings.Load(AppInfo.SettingsFile));
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
                Screenshot.Save(window, args.Screenshot, args.Width, args.Height);
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
        MessageBox.Show("Unerwarteter Fehler:\n\n" + e.Exception.Message + "\n\nDetails stehen in " + AppInfo.LogFile,
            "RE:Multiplayer Mod-Manager", MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }
}
