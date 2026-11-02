using System.Globalization;

namespace REMultiplayer.ModManager;

/// <summary>
/// Befehlszeile:
///   --install &lt;spiel&gt; --path &lt;ordner&gt; --package &lt;zip&gt; [--version x]   ohne Fenster (Tests in der CI)
///   --uninstall &lt;spiel&gt; --path &lt;ordner&gt;                                ohne Fenster
///   --resume install:&lt;spiel&gt; [--path &lt;ordner&gt;]                         nach Neustart als Administrator
///   --screenshot &lt;png&gt; [--demo] [--size 920x660]                       Bild des Fensters speichern
/// </summary>
public sealed class CommandLine
{
    public string? Install { get; private set; }
    public string? Uninstall { get; private set; }
    public string? Path { get; private set; }
    public string? Package { get; private set; }
    public string? Version { get; private set; }
    public string? Resume { get; private set; }
    public string? Screenshot { get; private set; }
    public bool Demo { get; private set; }
    public int Width { get; private set; } = 920;
    public int Height { get; private set; } = 660;

    public bool Headless => Install != null || Uninstall != null;

    public static CommandLine Parse(string[] args)
    {
        var c = new CommandLine();
        for (var i = 0; i < args.Length; i++)
        {
            string? Next() => i + 1 < args.Length ? args[++i] : null;
            switch (args[i].ToLowerInvariant())
            {
                case "--install": c.Install = Next(); break;
                case "--uninstall": c.Uninstall = Next(); break;
                case "--path": c.Path = Next(); break;
                case "--package": c.Package = Next(); break;
                case "--version": c.Version = Next(); break;
                case "--resume": c.Resume = Next(); break;
                case "--screenshot": c.Screenshot = Next(); break;
                case "--demo": c.Demo = true; break;
                case "--size":
                    var parts = (Next() ?? "").Split('x');
                    if (parts.Length == 2
                        && int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var w)
                        && int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var h))
                    {
                        c.Width = w;
                        c.Height = h;
                    }
                    break;
            }
        }
        return c;
    }
}
