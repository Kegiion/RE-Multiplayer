using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;

namespace REMods.ModManager;

/// <summary>
/// Sehr einfache Markdown-Anzeige fuer Patch Notes: Ueberschriften (#), Aufzaehlungen (- oder *),
/// Absaetze, **fett** und `code`. Mehr brauchen Release-Texte nicht.
/// </summary>
public static partial class MarkdownFlow
{
    [GeneratedRegex(@"(\*\*[^*]+\*\*|`[^`]+`)")]
    private static partial Regex InlineToken();

    public static void Append(FlowDocument doc, string markdown)
    {
        List? list = null;
        foreach (var raw in markdown.Replace("\r", "").Split('\n'))
        {
            var line = raw.TrimEnd();
            var trimmed = line.TrimStart();
            if (trimmed.Length == 0)
            {
                list = null;
                continue;
            }
            if (trimmed.StartsWith('#'))
            {
                var level = trimmed.TakeWhile(c => c == '#').Count();
                var p = new Paragraph(Inlines(trimmed[level..].Trim()))
                {
                    FontSize = level <= 2 ? 16 : 14,
                    FontWeight = FontWeights.SemiBold,
                    Margin = new Thickness(0, 10, 0, 4),
                };
                doc.Blocks.Add(p);
                list = null;
                continue;
            }
            if (trimmed.StartsWith("- ", StringComparison.Ordinal) || trimmed.StartsWith("* ", StringComparison.Ordinal))
            {
                if (list == null)
                {
                    list = new List { MarkerStyle = TextMarkerStyle.Disc, Margin = new Thickness(0, 2, 0, 6), Padding = new Thickness(20, 0, 0, 0) };
                    doc.Blocks.Add(list);
                }
                list.ListItems.Add(new ListItem(new Paragraph(Inlines(trimmed[2..])) { Margin = new Thickness(0, 1, 0, 1) }));
                continue;
            }
            list = null;
            doc.Blocks.Add(new Paragraph(Inlines(line)) { Margin = new Thickness(0, 2, 0, 6) });
        }
    }

    private static Span Inlines(string text)
    {
        var span = new Span();
        foreach (var part in InlineToken().Split(text))
        {
            if (part.Length == 0)
            {
                continue;
            }
            if (part.Length > 4 && part.StartsWith("**", StringComparison.Ordinal) && part.EndsWith("**", StringComparison.Ordinal))
            {
                span.Inlines.Add(new Bold(new Run(part[2..^2])));
            }
            else if (part.Length > 2 && part.StartsWith('`') && part.EndsWith('`'))
            {
                span.Inlines.Add(new Run(part[1..^1]) { FontFamily = new FontFamily("Consolas") });
            }
            else
            {
                span.Inlines.Add(new Run(part));
            }
        }
        return span;
    }
}
