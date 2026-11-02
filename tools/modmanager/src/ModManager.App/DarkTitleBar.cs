using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace REMultiplayer.ModManager;

/// <summary>Dunkle Titelleiste (Windows 10 ab 20H1 und Windows 11). Auf aelteren Systemen passiert nichts.</summary>
public static class DarkTitleBar
{
    private const int DwmwaUseImmersiveDarkMode = 20;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void Apply(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero)
        {
            return;
        }
        var on = 1;
        _ = DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref on, sizeof(int));
    }
}
