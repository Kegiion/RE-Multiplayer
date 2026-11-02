namespace REMods.ModManager.Core.Install;

/// <summary>Liest den Zeitstempel aus dem PE-Header einer exe (daran erkennen wir die Spielversion).</summary>
public static class PeTimestamp
{
    public static uint? Read(string exe)
    {
        try
        {
            using var f = File.OpenRead(exe);
            using var r = new BinaryReader(f);
            if (r.ReadUInt16() != 0x5A4D) // "MZ"
            {
                return null;
            }
            f.Position = 0x3C;
            var peOffset = r.ReadInt32();
            if (peOffset <= 0 || peOffset > f.Length - 12)
            {
                return null;
            }
            f.Position = peOffset;
            if (r.ReadUInt32() != 0x00004550) // "PE\0\0"
            {
                return null;
            }
            f.Position = peOffset + 8; // Signatur + Machine + NumberOfSections
            return r.ReadUInt32();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
