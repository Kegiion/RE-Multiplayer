using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;

namespace REMultiplayer.ModManager;

public static class Elevation
{
    public static bool IsElevated
    {
        get
        {
            using var id = WindowsIdentity.GetCurrent();
            return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
        }
    }

    /// <summary>Startet den Manager mit Administratorrechten neu. false, wenn der Spieler abgelehnt hat.</summary>
    public static bool RestartElevated(string arguments)
    {
        try
        {
            Process.Start(new ProcessStartInfo(AppInfo.ExePath)
            {
                UseShellExecute = true,
                Verb = "runas",
                Arguments = arguments,
            });
            return true;
        }
        catch (Win32Exception)
        {
            return false; // UAC-Abfrage abgelehnt
        }
    }

    /// <summary>Text fuer die Befehlszeile in Anfuehrungszeichen (Pfade mit Leerzeichen).</summary>
    public static string Quote(string s)
    {
        s = s.Replace("\"", "");
        // Ein Backslash direkt vor dem schliessenden " wuerde es maskieren
        return "\"" + (s.EndsWith('\\') ? s + "\\" : s) + "\"";
    }
}
