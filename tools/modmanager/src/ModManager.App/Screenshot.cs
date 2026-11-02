using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace REMods.ModManager;

/// <summary>Speichert den Fensterinhalt als PNG, ohne das Fenster anzuzeigen (Sichtpruefung in der CI).</summary>
public static class Screenshot
{
    public static void Save(MainWindow window, string file, int width, int height)
    {
        var root = (FrameworkElement)window.Content;
        var size = new Size(width, height);
        for (var pass = 0; pass < 2; pass++)
        {
            root.Measure(size);
            root.Arrange(new Rect(size));
            root.UpdateLayout();
            // Bindungen und Vorlagen fertig rendern lassen
            window.Dispatcher.Invoke(() => { }, DispatcherPriority.Loaded);
        }
        var bmp = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(root);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bmp));
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(file))!);
        using var stream = File.Create(file);
        encoder.Save(stream);
    }
}
