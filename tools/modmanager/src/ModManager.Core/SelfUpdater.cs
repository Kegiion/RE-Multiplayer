namespace REMultiplayer.ModManager.Core;

/// <summary>
/// Tauscht die laufende exe gegen eine neue. Windows erlaubt, eine laufende exe umzubenennen,
/// aber nicht, sie zu loeschen. Deshalb: alt -> .old, neu -> alter Name, .old beim naechsten Start loeschen.
/// </summary>
public static class SelfUpdater
{
    public static string OldPath(string exePath) => exePath + ".old";

    public static void Swap(string exePath, string newFile)
    {
        var old = OldPath(exePath);
        if (File.Exists(old))
        {
            File.Delete(old);
        }
        File.Move(exePath, old);
        try
        {
            File.Move(newFile, exePath);
        }
        catch
        {
            File.Move(old, exePath); // Rueckgaengig machen, damit der Manager startbar bleibt
            throw;
        }
    }

    /// <summary>Raeumt die .old-Datei weg. Die alte Instanz kann noch kurz laufen, daher ein paar Versuche.</summary>
    public static async Task CleanupAsync(string exePath)
    {
        var old = OldPath(exePath);
        for (var i = 0; i < 10 && File.Exists(old); i++)
        {
            try
            {
                File.Delete(old);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                await Task.Delay(500);
            }
        }
    }
}
