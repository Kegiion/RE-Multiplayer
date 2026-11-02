using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;
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
        var win = new NotesWindow { Owner = Application.Current.MainWindow };
        win.Heading.Text = title;
        win.Viewer.Document = Build(releases);
        win.ShowDialog();
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
            doc.Blocks.Add(new Paragraph(new Run("Noch keine Versionen veröffentlicht.")) { Foreground = muted });
            return doc;
        }
        foreach (var r in releases)
        {
            var head = new Paragraph { Margin = new Thickness(0, doc.Blocks.Count == 0 ? 0 : 22, 0, 2) };
            head.Inlines.Add(new Run("Version " + r.Version) { FontSize = 18, FontWeight = FontWeights.SemiBold });
            if (r.Prerelease)
            {
                head.Inlines.Add(new Run("  Beta") { Foreground = (Brush)Application.Current.FindResource("AccentBrush"), FontWeight = FontWeights.SemiBold });
            }
            doc.Blocks.Add(head);
            if (r.PublishedAt is { } date)
            {
                doc.Blocks.Add(new Paragraph(new Run(date.LocalDateTime.ToString("d. MMMM yyyy", new System.Globalization.CultureInfo("de-DE"))))
                {
                    Foreground = muted,
                    Margin = new Thickness(0, 0, 0, 6),
                });
            }
            if (string.IsNullOrWhiteSpace(r.Notes))
            {
                doc.Blocks.Add(new Paragraph(new Run("Keine Patch Notes.")) { Foreground = muted });
            }
            else
            {
                MarkdownFlow.Append(doc, r.Notes);
            }
        }
        return doc;
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
