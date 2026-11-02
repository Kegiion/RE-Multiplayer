using System.Windows.Input;
using REMods.ModManager.Core.Games;

namespace REMods.ModManager;

/// <summary>Eine Spielkarte im Fenster.</summary>
public sealed class GameViewModel : ObservableObject
{
    private readonly MainViewModel owner;

    public GameViewModel(MainViewModel owner, GameDefinition def)
    {
        this.owner = owner;
        Def = def;
        State = new GameState(def, null, false, null, null, null, false, null);
        PrimaryCommand = new RelayCommand(() => owner.InstallAsync(this), () => !owner.Busy && CanPrimary);
        UninstallCommand = new RelayCommand(() => owner.UninstallAsync(this), () => !owner.Busy && CanUninstall);
        NotesCommand = new RelayCommand(() => owner.ShowNotes(this), () => owner.HasNotes(Def));
        ReportCommand = new RelayCommand(() => owner.ReportBug(this), () => !owner.Busy);
        OpenFolderCommand = new RelayCommand(() => owner.OpenFolder(this), () => State.Dir != null);
        ChooseFolderCommand = new RelayCommand(() => owner.ChooseFolder(this), () => !owner.Busy);
    }

    public GameDefinition Def { get; }

    public GameState State { get; private set; }

    public ICommand PrimaryCommand { get; }
    public ICommand UninstallCommand { get; }
    public ICommand NotesCommand { get; }
    public ICommand ReportCommand { get; }
    public ICommand OpenFolderCommand { get; }
    public ICommand ChooseFolderCommand { get; }

    public void Apply(GameState state)
    {
        State = state;
        RaiseAll();
    }

    public string Name => Def.Name;

    public GameStatusKind Kind => State.Kind;

    public string FolderText => State.Dir ?? "Spielordner nicht gefunden. Über „Ordner wählen“ angeben, wo das Spiel liegt.";

    public string StatusText => Kind switch
    {
        GameStatusKind.NotFound => "Nicht gefunden",
        GameStatusKind.NotInstalled => "Nicht installiert",
        GameStatusKind.UpdateAvailable => "Update verfügbar",
        _ => "Installiert",
    };

    public string VersionText
    {
        get
        {
            var installed = !State.Installed ? "–"
                : State.InstalledVersion?.ToString() ?? "unbekannt (alter Installer)";
            var latest = State.Latest != null
                ? State.Latest.Version + (State.Latest.Prerelease ? " (Beta)" : "")
                : State.ReleaseError != null ? "nicht abrufbar"
                : "noch keine veröffentlicht";
            return $"Installiert: {installed}     Neueste: {latest}";
        }
    }

    public string PrimaryText => Kind switch
    {
        GameStatusKind.UpdateAvailable => "Aktualisieren",
        GameStatusKind.Installed => "Neu installieren",
        _ => "Installieren",
    };

    /// <summary>Roter Knopf, wenn es etwas zu tun gibt.</summary>
    public bool PrimaryAccent => Kind is GameStatusKind.NotInstalled or GameStatusKind.UpdateAvailable;

    public bool CanPrimary => State.Dir != null && State.Latest != null;

    public bool CanUninstall => State.Installed;

    public string HintText
    {
        get
        {
            var hints = new List<string>();
            if (State.Dir != null && !State.ExeSupported)
            {
                var ts = State.ExeTimestamp is { } t ? $"0x{t:X8}" : "unbekannt";
                hints.Add($"Deine {Def.Exe} hat eine andere Version (Zeitstempel {ts}) als die, für die die Mod gebaut ist. "
                          + "Das Menü funktioniert, der Koop bleibt aber eventuell aus.");
            }
            if (State.Dir != null && Def.Framework != null && !State.FrameworkPresent)
            {
                hints.Add($"{Def.Framework.Name} fehlt noch. Es wird beim Installieren automatisch mitinstalliert.");
            }
            return string.Join("\n", hints);
        }
    }

    public bool HasHint => HintText.Length > 0;
}
