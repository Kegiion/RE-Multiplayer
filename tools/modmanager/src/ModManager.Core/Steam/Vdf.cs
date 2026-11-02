using System.Text;

namespace REMultiplayer.ModManager.Core.Steam;

/// <summary>Knoten einer Valve-KeyValues-Datei (libraryfolders.vdf, appmanifest_*.acf).</summary>
public sealed class VdfNode
{
    public string? Value { get; init; }

    public Dictionary<string, VdfNode> Children { get; } = new(StringComparer.OrdinalIgnoreCase);

    public VdfNode? this[string key] => Children.TryGetValue(key, out var node) ? node : null;
}

/// <summary>Minimaler Parser fuer das Text-Format von Steam ("key" "value" / "key" { ... }).</summary>
public static class Vdf
{
    public static VdfNode Parse(string text)
    {
        var root = new VdfNode();
        var stack = new Stack<VdfNode>();
        stack.Push(root);
        string? pendingKey = null;
        var i = 0;
        while (i < text.Length)
        {
            var c = text[i];
            if (char.IsWhiteSpace(c))
            {
                i++;
                continue;
            }
            if (c == '/' && i + 1 < text.Length && text[i + 1] == '/')
            {
                while (i < text.Length && text[i] != '\n')
                {
                    i++;
                }
                continue;
            }
            if (c == '{')
            {
                var node = new VdfNode();
                if (pendingKey != null)
                {
                    stack.Peek().Children[pendingKey] = node;
                    pendingKey = null;
                }
                stack.Push(node);
                i++;
                continue;
            }
            if (c == '}')
            {
                if (stack.Count > 1)
                {
                    stack.Pop();
                }
                pendingKey = null;
                i++;
                continue;
            }

            var token = c == '"' ? ReadQuoted(text, ref i) : ReadBare(text, ref i);
            if (pendingKey == null)
            {
                pendingKey = token;
            }
            else
            {
                stack.Peek().Children[pendingKey] = new VdfNode { Value = token };
                pendingKey = null;
            }
        }
        return root;
    }

    private static string ReadQuoted(string text, ref int i)
    {
        var sb = new StringBuilder();
        i++; // oeffnendes "
        while (i < text.Length && text[i] != '"')
        {
            if (text[i] == '\\' && i + 1 < text.Length)
            {
                var next = text[i + 1];
                sb.Append(next switch
                {
                    'n' => '\n',
                    't' => '\t',
                    _ => next,
                });
                i += 2;
                continue;
            }
            sb.Append(text[i]);
            i++;
        }
        i++; // schliessendes "
        return sb.ToString();
    }

    private static string ReadBare(string text, ref int i)
    {
        var start = i;
        while (i < text.Length && !char.IsWhiteSpace(text[i]) && text[i] is not ('{' or '}' or '"'))
        {
            i++;
        }
        return text[start..i];
    }
}
