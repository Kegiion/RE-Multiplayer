using System.Windows.Input;
using REMultiplayer.ModManager.Core.Games;
using REMultiplayer.ModManager.Core.Localization;

namespace REMultiplayer.ModManager;

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

    /// <summary>Alle Texte neu lesen (nach einem Sprachwechsel).</summary>
    public void Relocalize() => RaiseAll();

    public string Name => Def.Name;

    public GameStatusKind Kind => State.Kind;

    public string FolderText => State.Dir ?? L.T("card.folderMissing");

    public string StatusText => Kind switch
    {
        GameStatusKind.NotFound => L.T("state.notFound"),
        GameStatusKind.NotInstalled => L.T("state.notInstalled"),
        GameStatusKind.UpdateAvailable => L.T("state.updateAvailable"),
        _ => L.T("state.installed"),
    };

    public string VersionText
    {
        get
        {
            var installed = !State.Installed ? "–"
                : State.InstalledVersion?.ToString() ?? L.T("version.unknown");
            var latest = State.Latest != null
                ? State.Latest.Prerelease ? L.T("version.beta", State.Latest.Version) : State.Latest.Version.ToString()
                : State.ReleaseError != null ? L.T("version.unavailable")
                : L.T("version.noneYet");
            return L.T("version.line", installed, latest);
        }
    }

    public string PrimaryText => Kind switch
    {
        GameStatusKind.UpdateAvailable => L.T("action.update"),
        GameStatusKind.Installed => L.T("action.reinstall"),
        _ => L.T("action.install"),
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
                var ts = State.ExeTimestamp is { } t ? $"0x{t:X8}" : L.T("version.unknown");
                hints.Add(L.T("hint.exeVersion", Def.Exe, ts));
            }
            if (State.Installed && State.Record == null)
            {
                hints.Add(L.T("hint.notManaged"));
            }
            if (State.Dir != null && Def.Framework != null && !State.FrameworkPresent)
            {
                hints.Add(L.T("hint.frameworkMissing", Def.Framework.Name));
            }
            return string.Join("\n", hints);
        }
    }

    public bool HasHint => HintText.Length > 0;
}
