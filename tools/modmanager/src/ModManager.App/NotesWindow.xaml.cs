using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;
using REMultiplayer.ModManager.Core.Localization;
using REMultiplayer.ModManager.Core.Releases;

namespace REMultiplayer.ModManager;

/// <summary>Zeigt die Release-Texte aller Versionen einer Mod, neueste zuerst.</summary>
public partial class NotesWindow : Window
{
    public NotesWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => DarkTitleBar.Apply(this);
    }

    public static void ShowFor(string title, IReadOnlyList<ModRelease> releases)
    {
        var win = Create(title, releases);
        win.Owner = Application.Current.MainWindow;
        win.ShowDialog();
    }

    /// <summary>Fenster fuellen, ohne es zu zeigen (auch fuer Bildschirmfotos).</summary>
    public static NotesWindow Create(string title, IReadOnlyList<ModRelease> releases)
    {
        var win = new NotesWindow();
        win.Heading.Text = title;
        win.Viewer.Document = Build(releases);
        return win;
    }

    private static FlowDocument Build(IReadOnlyList<ModRelease> releases)
    {
        var muted = (Brush)Application.Current.FindResource("TextMutedBrush");
        var doc = new FlowDocument
        {
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 13,
            Foreground = (Brush)Application.Current.FindResource("TextBrush"),
            Background = Brushes.Transparent,
            PagePadding = new Thickness(0, 0, 12, 0),
        };
        if (releases.Count == 0)
        {
            doc.Blocks.Add(new Paragraph(new Run(L.T("notes.none"))) { Foreground = muted });
            return doc;
        }
        foreach (var r in releases)
        {
            var head = new Paragraph { Margin = new Thickness(0, doc.Blocks.Count == 0 ? 0 : 22, 0, 2) };
            head.Inlines.Add(new Run(L.T("notes.version", r.Version)) { FontSize = 18, FontWeight = FontWeights.SemiBold });
            if (r.Prerelease)
            {
                head.Inlines.Add(new Run("  " + L.T("notes.beta")) { Foreground = (Brush)Application.Current.FindResource("AccentBrush"), FontWeight = FontWeights.SemiBold });
            }
            doc.Blocks.Add(head);
            if (r.PublishedAt is { } date)
            {
                doc.Blocks.Add(new Paragraph(new Run(date.LocalDateTime.ToString(L.Instance.Current.DateFormat, L.Instance.Culture)))
                {
                    Foreground = muted,
                    Margin = new Thickness(0, 0, 0, 6),
                });
            }
            // Zweisprachige Notes: nur den Abschnitt der eingestellten Sprache zeigen
            var notes = PatchNotes.ForLanguage(r.Notes, L.Instance.Current.Code, L.Instance.Available);
            if (string.IsNullOrWhiteSpace(notes))
            {
                doc.Blocks.Add(new Paragraph(new Run(L.T("notes.empty"))) { Foreground = muted });
            }
            else
            {
                MarkdownFlow.Append(doc, notes);
            }
        }
        return doc;
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
