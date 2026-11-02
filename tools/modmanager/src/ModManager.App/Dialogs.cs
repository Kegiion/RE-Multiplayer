using System.Windows;

namespace REMods.ModManager;

/// <summary>Kurze Meldungen an den Spieler.</summary>
public static class Dialogs
{
    private const string Title = "REMods Mod-Manager";

    private static Window? Owner => Application.Current?.MainWindow is { IsVisible: true } w ? w : null;

    private static MessageBoxResult Show(string text, MessageBoxButton buttons, MessageBoxImage icon) =>
        Owner is { } owner
            ? MessageBox.Show(owner, text, Title, buttons, icon)
            : MessageBox.Show(text, Title, buttons, icon);

    public static void Info(string text) => Show(text, MessageBoxButton.OK, MessageBoxImage.Information);

    public static void Warn(string text) => Show(text, MessageBoxButton.OK, MessageBoxImage.Warning);

    public static void Error(string text) => Show(text, MessageBoxButton.OK, MessageBoxImage.Error);

    public static bool Confirm(string text) =>
        Show(text, MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes;
}
