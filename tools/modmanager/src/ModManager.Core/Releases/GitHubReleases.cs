using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace REMultiplayer.ModManager.Core.Releases;

/// <summary>Release aus der GitHub-API (nur die Felder, die wir brauchen).</summary>
public sealed class GhRelease
{
    [JsonPropertyName("tag_name")] public string TagName { get; set; } = "";
    [JsonPropertyName("name")] public string? Name { get; set; }
    [JsonPropertyName("body")] public string? Body { get; set; }
    [JsonPropertyName("draft")] public bool Draft { get; set; }
    [JsonPropertyName("prerelease")] public bool Prerelease { get; set; }
    [JsonPropertyName("published_at")] public DateTimeOffset? PublishedAt { get; set; }
    [JsonPropertyName("html_url")] public string? HtmlUrl { get; set; }
    [JsonPropertyName("assets")] public List<GhAsset> Assets { get; set; } = [];
}

public sealed class GhAsset
{
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("browser_download_url")] public string DownloadUrl { get; set; } = "";
    [JsonPropertyName("size")] public long Size { get; set; }

    /// <summary>Pruefsumme von GitHub, z. B. "sha256:ab12...". Bei sehr alten Releases leer.</summary>
    [JsonPropertyName("digest")] public string? Digest { get; set; }
}

/// <summary>Release einer bestimmten Mod (Tag-Praefix schon abgeschnitten, Version geparst).</summary>
public sealed record ModRelease(
    string Tag,
    ModVersion Version,
    string Title,
    string Notes,
    bool Prerelease,
    DateTimeOffset? PublishedAt,
    string? HtmlUrl,
    IReadOnlyList<GhAsset> Assets)
{
    public GhAsset? FindAsset(string prefix, string suffix) =>
        Assets.FirstOrDefault(a => a.Name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
                                   && a.Name.EndsWith(suffix, StringComparison.OrdinalIgnoreCase));
}

public static class ReleaseSelector
{
    /// <summary>Alle Releases mit diesem Tag-Praefix, neueste zuerst. Entwuerfe nie, Vorabversionen optional.</summary>
    public static List<ModRelease> ForPrefix(IEnumerable<GhRelease> releases, string tagPrefix, bool includePrereleases)
    {
        var result = new List<ModRelease>();
        foreach (var r in releases)
        {
            if (r.Draft || (r.Prerelease && !includePrereleases)
                        || !r.TagName.StartsWith(tagPrefix, StringComparison.OrdinalIgnoreCase)
                        || !ModVersion.TryParse(r.TagName[tagPrefix.Length..], out var version))
            {
                continue;
            }
            result.Add(new ModRelease(r.TagName, version!, string.IsNullOrWhiteSpace(r.Name) ? r.TagName : r.Name,
                r.Body ?? "", r.Prerelease, r.PublishedAt, r.HtmlUrl, r.Assets));
        }
        return result.OrderByDescending(r => r.Version).ToList();
    }
}

/// <summary>Fehler beim Zugriff auf GitHub, mit einer Meldung fuer den Spieler.</summary>
public sealed class GitHubException(string message, Exception? inner = null) : Exception(message, inner);

/// <summary>Liest Releases ohne Anmeldung (oeffentliche Repos) und laedt Assets mit Pruefsumme.</summary>
public sealed class GitHubClient : IDisposable
{
    private readonly HttpClient http;

    public GitHubClient(string userAgent, HttpMessageHandler? handler = null)
    {
        http = handler == null ? new HttpClient() : new HttpClient(handler);
        // Kein Gesamt-Timeout (grosse Downloads), API-Aufrufe bekommen ApiTimeout
        http.Timeout = Timeout.InfiniteTimeSpan;
        http.DefaultRequestHeaders.UserAgent.ParseAdd(userAgent);
    }

    private static readonly TimeSpan ApiTimeout = TimeSpan.FromSeconds(30);

    public void Dispose() => http.Dispose();

    private static CancellationTokenSource WithTimeout(CancellationToken ct)
    {
        var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(ApiTimeout);
        return cts;
    }

    public async Task<List<GhRelease>> GetReleasesAsync(string repo, CancellationToken ct = default) =>
        await GetJsonAsync<List<GhRelease>>($"https://api.github.com/repos/{repo}/releases?per_page=100", ct) ?? [];

    public Task<GhRelease?> GetLatestReleaseAsync(string repo, CancellationToken ct = default) =>
        GetJsonAsync<GhRelease>($"https://api.github.com/repos/{repo}/releases/latest", ct);

    /// <summary>Text einer Datei (z. B. games.json aus dem Repo) oder null bei jedem Fehler.</summary>
    public async Task<string?> TryGetTextAsync(string url, CancellationToken ct = default)
    {
        try
        {
            using var cts = WithTimeout(ct);
            using var resp = await http.GetAsync(url, cts.Token);
            return resp.IsSuccessStatusCode ? await resp.Content.ReadAsStringAsync(cts.Token) : null;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return null;
        }
    }

    private async Task<T?> GetJsonAsync<T>(string url, CancellationToken outer)
    {
        using var cts = WithTimeout(outer);
        var ct = cts.Token;
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Accept.ParseAdd("application/vnd.github+json");
        req.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
        HttpResponseMessage resp;
        try
        {
            resp = await http.SendAsync(req, ct);
        }
        catch (HttpRequestException e)
        {
            throw new GitHubException("GitHub ist nicht erreichbar. Besteht eine Internetverbindung?", e);
        }
        catch (TaskCanceledException e) when (!outer.IsCancellationRequested)
        {
            throw new GitHubException("GitHub antwortet nicht (Zeitüberschreitung).", e);
        }
        using (resp)
        {
            if (resp.StatusCode == HttpStatusCode.NotFound)
            {
                throw new GitHubException("Keine Releases gefunden (Repo nicht gefunden oder nicht öffentlich).");
            }
            if (resp.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests)
            {
                throw new GitHubException("GitHub hat zu viele Anfragen gezählt. Bitte in einer Stunde erneut versuchen.");
            }
            if (!resp.IsSuccessStatusCode)
            {
                throw new GitHubException($"GitHub meldet einen Fehler ({(int)resp.StatusCode}).");
            }
            try
            {
                await using var stream = await resp.Content.ReadAsStreamAsync(ct);
                return await JsonSerializer.DeserializeAsync<T>(stream, cancellationToken: ct);
            }
            catch (JsonException e)
            {
                throw new GitHubException("Unerwartete Antwort von GitHub.", e);
            }
        }
    }

    /// <summary>
    /// Laedt ein Asset nach destFile. Nur HTTPS von github.com. Groesse und SHA-256 (falls GitHub
    /// eine Pruefsumme liefert) werden geprueft, erst dann liegt die Datei unter destFile.
    /// </summary>
    public async Task DownloadAsync(GhAsset asset, string destFile, IProgress<double>? progress = null,
        CancellationToken ct = default)
    {
        if (!Uri.TryCreate(asset.DownloadUrl, UriKind.Absolute, out var uri)
            || uri.Scheme != Uri.UriSchemeHttps
            || !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase))
        {
            throw new GitHubException($"Unerwartete Download-Adresse: {asset.DownloadUrl}");
        }

        var part = destFile + ".part";
        try
        {
            using var resp = await http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!resp.IsSuccessStatusCode)
            {
                throw new GitHubException($"Download von {asset.Name} fehlgeschlagen ({(int)resp.StatusCode}).");
            }
            var total = resp.Content.Headers.ContentLength ?? asset.Size;
            using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            long written = 0;
            await using (var src = await resp.Content.ReadAsStreamAsync(ct))
            await using (var dst = File.Create(part))
            {
                var buffer = new byte[81920];
                int read;
                while ((read = await src.ReadAsync(buffer, ct)) > 0)
                {
                    await dst.WriteAsync(buffer.AsMemory(0, read), ct);
                    sha.AppendData(buffer, 0, read);
                    written += read;
                    if (total > 0)
                    {
                        progress?.Report(Math.Min(1.0, (double)written / total));
                    }
                }
            }

            if (asset.Size > 0 && written != asset.Size)
            {
                throw new GitHubException($"{asset.Name} ist unvollständig angekommen. Bitte erneut versuchen.");
            }
            if (!string.IsNullOrEmpty(asset.Digest)
                && asset.Digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
            {
                var expected = asset.Digest["sha256:".Length..];
                var actual = Convert.ToHexString(sha.GetHashAndReset());
                if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
                {
                    throw new GitHubException($"Die Prüfsumme von {asset.Name} stimmt nicht. Download verworfen.");
                }
            }
            File.Move(part, destFile, overwrite: true);
        }
        catch (HttpRequestException e)
        {
            throw new GitHubException($"Download von {asset.Name} abgebrochen. Besteht eine Internetverbindung?", e);
        }
        catch (TaskCanceledException e) when (!ct.IsCancellationRequested)
        {
            throw new GitHubException($"Download von {asset.Name} abgebrochen (Zeitüberschreitung).", e);
        }
        finally
        {
            if (File.Exists(part))
            {
                File.Delete(part);
            }
        }
    }
}
