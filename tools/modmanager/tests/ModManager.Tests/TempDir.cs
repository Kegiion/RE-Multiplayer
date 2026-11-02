using System.IO.Compression;
using System.Text;

namespace REMods.ModManager.Tests;

/// <summary>Temporaerer Ordner, der nach dem Test geloescht wird.</summary>
public sealed class TempDir : IDisposable
{
    public TempDir()
    {
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "remods-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public string File(string relative) =>
        System.IO.Path.Combine(Path, relative.Replace('/', System.IO.Path.DirectorySeparatorChar));

    public string Write(string relative, string content)
    {
        var p = File(relative);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(p)!);
        System.IO.File.WriteAllText(p, content);
        return p;
    }

    public string WriteBytes(string relative, byte[] content)
    {
        var p = File(relative);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(p)!);
        System.IO.File.WriteAllBytes(p, content);
        return p;
    }

    public bool Exists(string relative) => System.IO.File.Exists(File(relative));

    public string Read(string relative) => System.IO.File.ReadAllText(File(relative));

    /// <summary>Baut ein ZIP mit den angegebenen Eintraegen (Name -> Inhalt).</summary>
    public string Zip(string name, IDictionary<string, byte[]> entries)
    {
        var p = File(name);
        using var zip = ZipFile.Open(p, ZipArchiveMode.Create);
        foreach (var (entryName, bytes) in entries)
        {
            var e = zip.CreateEntry(entryName);
            using var s = e.Open();
            s.Write(bytes);
        }
        return p;
    }

    public static byte[] Text(string s) => Encoding.UTF8.GetBytes(s);

    public void Dispose()
    {
        try
        {
            Directory.Delete(Path, recursive: true);
        }
        catch (IOException)
        {
        }
    }
}
