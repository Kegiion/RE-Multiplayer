using System.IO.Compression;
using System.Text;
using System.Text.Json;
using REMods.ModManager.Core.Games;

namespace REMods.ModManager.Core.Install;

/// <summary>
/// Installiert, aktualisiert und entfernt eine Mod in einem Spielordner.
/// Portiert aus games/re0hd/installer/installer.cpp:
///   - fremde Loader-DLL (dinput8.dll) wird gesichert und beim Deinstallieren wiederhergestellt
///   - Einstellungen (KeepPaths, z. B. remods/data) bleiben erhalten
///   - fehlende Schreibrechte melden sich als InstallException mit NeedsAdmin
/// </summary>
public sealed class ModInstaller(GameDefinition game, string gameDir)
{
    public GameDefinition Game { get; } = game;

    public string GameDir { get; } = gameDir;

    private string Full(string relative) => GamePaths.Resolve(GameDir, relative);

    public string RecordFile => Full(Game.RecordPath);

    public bool IsInstalled => File.Exists(Full(Game.InstalledMarker)) || File.Exists(RecordFile);

    /// <summary>true, wenn kein Framework noetig ist oder alle seine Dateien vorhanden sind.</summary>
    public bool FrameworkPresent => Game.Framework == null || Game.Framework.Files.All(f => File.Exists(Full(f)));

    public InstallRecord? ReadRecord()
    {
        try
        {
            return File.Exists(RecordFile)
                ? JsonSerializer.Deserialize<InstallRecord>(File.ReadAllText(RecordFile), Json.Options)
                : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }

    /// <summary>Prueft, ob wir im Spielordner schreiben duerfen.</summary>
    public void EnsureWritable()
    {
        var probe = Path.Combine(GameDir, $".remods-schreibtest-{Guid.NewGuid():N}");
        try
        {
            File.WriteAllText(probe, "");
            File.Delete(probe);
        }
        catch (UnauthorizedAccessException e)
        {
            throw NeedsAdmin(e);
        }
        catch (IOException e)
        {
            throw new InstallException("Im Spielordner kann nicht geschrieben werden: " + e.Message, false, e);
        }
    }

    /// <summary>
    /// Installiert oder aktualisiert die Mod aus einem ZIP (Inhalt = Spielordner).
    /// frameworkZip: optional das ZIP des Frameworks (z. B. REFramework), das mitinstalliert wird.
    /// </summary>
    public InstallRecord Install(string packageZip, string? frameworkZip, string version, string tag, string managerVersion)
    {
        EnsureWritable();
        return Run(() =>
        {
            using var zip = ZipFile.OpenRead(packageZip);
            var entries = new List<(ZipArchiveEntry Entry, string Rel)>();
            foreach (var entry in zip.Entries)
            {
                if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\'))
                {
                    continue; // Ordner-Eintrag
                }
                entries.Add((entry, GamePaths.Normalize(entry.FullName)));
            }
            if (entries.Count == 0)
            {
                throw new InstallException("Das Paket ist leer.");
            }
            // Alle Ziele vorab pruefen, damit ein kaputtes Paket gar nichts schreibt
            foreach (var (_, rel) in entries)
            {
                Full(rel);
            }

            var old = ReadRecord();
            var newFiles = entries.Select(e => e.Rel).ToList();

            BackupForeignLoader(newFiles);
            foreach (var (entry, rel) in entries)
            {
                var target = Full(rel);
                if (Game.IsKept(rel) && File.Exists(target))
                {
                    continue; // Einstellungen des Spielers nicht ueberschreiben
                }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                entry.ExtractToFile(target, overwrite: true);
            }

            // Dateien, die es in der neuen Version nicht mehr gibt
            if (old != null)
            {
                var stale = old.Files
                    .Where(f => GamePaths.TryNormalize(f, out _))
                    .Except(newFiles, StringComparer.OrdinalIgnoreCase)
                    .Where(f => !Game.IsKept(f))
                    .ToList();
                DeleteFiles(stale);
                PruneDirectories(stale);
            }

            var frameworkByManager = old?.FrameworkInstalledByManager ?? false;
            var frameworkFiles = old?.FrameworkFiles ?? [];
            if (frameworkZip != null && Game.Framework != null)
            {
                frameworkFiles = ExtractFramework(frameworkZip);
                frameworkByManager = true;
            }

            var record = new InstallRecord
            {
                GameId = Game.Id,
                Version = version,
                Tag = tag,
                InstalledAt = DateTimeOffset.Now,
                ManagerVersion = managerVersion,
                Files = newFiles,
                FrameworkInstalledByManager = frameworkByManager,
                FrameworkFiles = frameworkFiles,
            };
            Directory.CreateDirectory(Path.GetDirectoryName(RecordFile)!);
            File.WriteAllText(RecordFile, JsonSerializer.Serialize(record, Json.Options));
            return record;
        });
    }

    /// <summary>Entfernt die Mod. Einstellungen bleiben, eine gesicherte fremde Loader-DLL kommt zurueck.</summary>
    public void Uninstall()
    {
        EnsureWritable();
        Run(() =>
        {
            var record = ReadRecord();
            var files = (record?.Files ?? LegacyFiles())
                .Where(f => GamePaths.TryNormalize(f, out _) && !Game.IsKept(f))
                .ToList();
            if (record is { FrameworkInstalledByManager: true })
            {
                files.AddRange(record.FrameworkFiles.Where(f => GamePaths.TryNormalize(f, out _)));
            }
            DeleteFiles(files);
            RestoreLoaderBackup();
            if (File.Exists(RecordFile))
            {
                File.Delete(RecordFile);
            }
            PruneDirectories(files.Append(Game.RecordPath));
            foreach (var dir in Game.LegacyDirs)
            {
                PruneDirectory(Full(dir));
            }
            return 0;
        });
    }

    /// <summary>Unsere Loader-DLL enthaelt den Pfad zur Runtime als UTF-16-Text.</summary>
    public bool IsOurLoader(string path)
    {
        if (Game.Loader == null || !File.Exists(path))
        {
            return false;
        }
        var needle = Encoding.Unicode.GetBytes(Game.Loader.OwnMarker);
        var bytes = File.ReadAllBytes(path);
        return bytes.AsSpan().IndexOf(needle) >= 0;
    }

    private List<string> LegacyFiles()
    {
        var files = new List<string>(Game.LegacyFiles);
        foreach (var dir in Game.LegacyDirs)
        {
            var full = Full(dir);
            if (!Directory.Exists(full))
            {
                continue;
            }
            foreach (var f in Directory.EnumerateFiles(full, "*", SearchOption.AllDirectories))
            {
                files.Add(Path.GetRelativePath(GameDir, f).Replace('\\', '/'));
            }
        }
        if (Game.Loader != null)
        {
            files.Add(Game.Loader.File); // wird nur geloescht, wenn es unserer ist
        }
        return files;
    }

    private void BackupForeignLoader(IEnumerable<string> packageFiles)
    {
        var loader = Game.Loader;
        if (loader == null || !packageFiles.Contains(loader.File, StringComparer.OrdinalIgnoreCase))
        {
            return;
        }
        var path = Full(loader.File);
        if (File.Exists(path) && !IsOurLoader(path))
        {
            File.Copy(path, path + loader.BackupSuffix, overwrite: true);
        }
    }

    private void RestoreLoaderBackup()
    {
        var loader = Game.Loader;
        if (loader == null)
        {
            return;
        }
        var path = Full(loader.File);
        var backup = path + loader.BackupSuffix;
        if (File.Exists(backup) && !File.Exists(path))
        {
            File.Move(backup, path);
        }
    }

    private void DeleteFiles(IEnumerable<string> files)
    {
        foreach (var rel in files)
        {
            var path = Full(rel);
            if (!File.Exists(path))
            {
                continue;
            }
            // Eine fremde Loader-DLL (z. B. inzwischen eine andere Mod) nie loeschen
            if (Game.Loader != null && GamePaths.IsUnder(rel, Game.Loader.File) && !IsOurLoader(path))
            {
                continue;
            }
            File.Delete(path);
        }
    }

    private List<string> ExtractFramework(string frameworkZip)
    {
        var fw = Game.Framework!;
        using var zip = ZipFile.OpenRead(frameworkZip);
        var written = new List<string>();
        foreach (var file in fw.Files)
        {
            var rel = GamePaths.Normalize(file);
            var name = Path.GetFileName(rel);
            // Zuerst exakter Pfad, sonst gleicher Dateiname irgendwo im ZIP
            var entry = zip.Entries.FirstOrDefault(e =>
                            GamePaths.TryNormalize(e.FullName, out var n) && n.Equals(rel, StringComparison.OrdinalIgnoreCase))
                        ?? zip.Entries.FirstOrDefault(e => e.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                        ?? throw new InstallException($"Im {fw.Name}-Paket fehlt {file}.");
            var target = Full(rel);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            entry.ExtractToFile(target, overwrite: true);
            written.Add(rel);
        }
        return written;
    }

    /// <summary>Leere Ordner entfernen, von den Dateien aus nach oben bis zum Spielordner.</summary>
    private void PruneDirectories(IEnumerable<string> files)
    {
        foreach (var rel in files)
        {
            var dir = Path.GetDirectoryName(Full(rel));
            if (dir != null)
            {
                PruneDirectory(dir);
            }
        }
    }

    private void PruneDirectory(string dir)
    {
        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(GameDir));
        var current = Path.TrimEndingDirectorySeparator(Path.GetFullPath(dir));
        while (current.Length > root.Length
               && current.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            if (!Directory.Exists(current) || Directory.EnumerateFileSystemEntries(current).Any())
            {
                return;
            }
            Directory.Delete(current);
            current = Path.GetDirectoryName(current)!;
        }
    }

    private static InstallException NeedsAdmin(Exception e) =>
        new("Für den Spielordner werden Administratorrechte benötigt.", true, e);

    private static T Run<T>(Func<T> action)
    {
        try
        {
            return action();
        }
        catch (UnauthorizedAccessException e)
        {
            throw NeedsAdmin(e);
        }
        catch (IOException e) when (IsSharingViolation(e))
        {
            throw new InstallException(
                "Eine Datei wird gerade benutzt. Läuft das Spiel noch? Bitte beenden und erneut versuchen.", false, e);
        }
        catch (InvalidDataException e)
        {
            throw new InstallException("Das Paket ist beschädigt: " + e.Message, false, e);
        }
        catch (IOException e)
        {
            throw new InstallException("Fehler beim Schreiben: " + e.Message, false, e);
        }
    }

    // ERROR_SHARING_VIOLATION (32) und ERROR_LOCK_VIOLATION (33)
    private static bool IsSharingViolation(IOException e) => (e.HResult & 0xFFFF) is 32 or 33;
}
