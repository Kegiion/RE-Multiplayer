using System.Globalization;

namespace REMods.ModManager.Core;

/// <summary>Versionsnummer wie "0.4.0" oder "1.2.0-beta.1" (SemVer-aehnlich, bis zu 4 Teile).</summary>
public sealed class ModVersion : IComparable<ModVersion>, IEquatable<ModVersion>
{
    private readonly int[] parts;

    private ModVersion(int[] parts, string? prerelease)
    {
        this.parts = parts;
        Prerelease = prerelease;
    }

    /// <summary>Vorabkennung nach dem Bindestrich (z. B. "beta.1") oder null.</summary>
    public string? Prerelease { get; }

    public static ModVersion Parse(string text) =>
        TryParse(text, out var v) ? v! : throw new FormatException($"Ungueltige Version: {text}");

    public static bool TryParse(string? text, out ModVersion? version)
    {
        version = null;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }
        var s = text.Trim();
        if (s.StartsWith('v') || s.StartsWith('V'))
        {
            s = s[1..];
        }
        var plus = s.IndexOf('+');
        if (plus >= 0)
        {
            s = s[..plus];
        }
        string? pre = null;
        var dash = s.IndexOf('-');
        if (dash >= 0)
        {
            pre = s[(dash + 1)..];
            s = s[..dash];
            if (pre.Length == 0)
            {
                return false;
            }
        }
        var bits = s.Split('.');
        if (bits.Length is 0 or > 4)
        {
            return false;
        }
        var parts = new int[bits.Length];
        for (var i = 0; i < bits.Length; i++)
        {
            if (!int.TryParse(bits[i], NumberStyles.None, CultureInfo.InvariantCulture, out parts[i]))
            {
                return false;
            }
        }
        version = new ModVersion(parts, pre);
        return true;
    }

    public int CompareTo(ModVersion? other)
    {
        if (other is null)
        {
            return 1;
        }
        var n = Math.Max(parts.Length, other.parts.Length);
        for (var i = 0; i < n; i++)
        {
            var a = i < parts.Length ? parts[i] : 0;
            var b = i < other.parts.Length ? other.parts[i] : 0;
            if (a != b)
            {
                return a.CompareTo(b);
            }
        }
        // Eine Version ohne Vorabkennung ist neuer als eine mit
        if (Prerelease == null || other.Prerelease == null)
        {
            return (Prerelease == null ? 1 : 0) - (other.Prerelease == null ? 1 : 0);
        }
        return ComparePrerelease(Prerelease, other.Prerelease);
    }

    private static int ComparePrerelease(string a, string b)
    {
        var x = a.Split('.');
        var y = b.Split('.');
        for (var i = 0; i < Math.Min(x.Length, y.Length); i++)
        {
            var xNum = int.TryParse(x[i], NumberStyles.None, CultureInfo.InvariantCulture, out var xi);
            var yNum = int.TryParse(y[i], NumberStyles.None, CultureInfo.InvariantCulture, out var yi);
            var c = xNum && yNum ? xi.CompareTo(yi)
                : xNum ? -1
                : yNum ? 1
                : string.CompareOrdinal(x[i], y[i]);
            if (c != 0)
            {
                return c;
            }
        }
        return x.Length.CompareTo(y.Length);
    }

    public bool Equals(ModVersion? other) => other is not null && CompareTo(other) == 0;

    public override bool Equals(object? obj) => obj is ModVersion v && Equals(v);

    public override int GetHashCode()
    {
        // Abschliessende Nullen zaehlen nicht (1.0 == 1.0.0)
        var last = parts.Length - 1;
        while (last >= 0 && parts[last] == 0)
        {
            last--;
        }
        var h = new HashCode();
        for (var i = 0; i <= last; i++)
        {
            h.Add(parts[i]);
        }
        h.Add(Prerelease);
        return h.ToHashCode();
    }

    public override string ToString() =>
        string.Join('.', parts) + (Prerelease != null ? "-" + Prerelease : "");

    public static bool operator >(ModVersion a, ModVersion b) => a.CompareTo(b) > 0;

    public static bool operator <(ModVersion a, ModVersion b) => a.CompareTo(b) < 0;

    public static bool operator >=(ModVersion a, ModVersion b) => a.CompareTo(b) >= 0;

    public static bool operator <=(ModVersion a, ModVersion b) => a.CompareTo(b) <= 0;
}
