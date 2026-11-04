using System.ComponentModel;
using System.Windows.Data;
using System.Windows.Markup;
using REMultiplayer.ModManager.Core.Localization;

namespace REMultiplayer.ModManager;

/// <summary>
/// Texte fuer die Oberflaeche. XAML bindet ueber die Markup-Erweiterung l:T an den Indexer,
/// beim Sprachwechsel aktualisieren sich alle Texte ohne Neustart.
/// </summary>
public sealed class Tr : INotifyPropertyChanged
{
    public static Tr Instance { get; } = new();

    public string this[string key] => L.T(key);

    public event PropertyChangedEventHandler? PropertyChanged;

    public static void Use(string code)
    {
        L.Instance.Use(code);
        Instance.PropertyChanged?.Invoke(Instance, new PropertyChangedEventArgs("Item[]"));
    }
}

/// <summary>Markup-Erweiterung fuer XAML, z. B. Content="{l:T card.uninstall}".</summary>
[MarkupExtensionReturnType(typeof(object))]
public sealed class TExtension : MarkupExtension
{
    public TExtension()
    {
    }

    public TExtension(string key) => Key = key;

    [ConstructorArgument("key")]
    public string Key { get; set; } = "";

    public override object ProvideValue(IServiceProvider serviceProvider) =>
        new Binding($"[{Key}]") { Source = Tr.Instance, Mode = BindingMode.OneWay }.ProvideValue(serviceProvider);
}

/// <summary>Eintrag in der Sprachauswahl. Code "" = Windows-Sprache.</summary>
public sealed class LanguageOption(string code) : ObservableObject
{
    public string Code { get; } = code;

    public string Display => Code.Length == 0
        ? L.T("header.languageAuto", L.Instance.Available.FirstOrDefault(p => p.Code == SystemCode)?.Name ?? SystemCode)
        : L.Instance.Available.First(p => p.Code == Code).Name;

    /// <summary>Sprache, die "Automatisch" gerade bedeutet.</summary>
    public static string SystemCode => L.Instance.Resolve(null, System.Globalization.CultureInfo.CurrentUICulture);

    public void Refresh() => Raise(nameof(Display));
}
