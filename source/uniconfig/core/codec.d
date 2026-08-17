module uniconfig.core.codec;

import std.json : JSONValue, parseJSON, JSONType, toJSON;
import std.string : strip, splitLines, startsWith, indexOf, stripLeft, toLower;
import std.array : appender, join, split;
import std.algorithm : canFind, startsWith, countUntil, map, filter;
import std.conv : to;
import std.exception : enforce;
import uniconfig.core.format;
import uniconfig.core.tree;

class CodecException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

JSONValue decodeToJson(string text, ConfigFormat fmt)
{
    if (text.length >= 1 && text[0] == '\uFEFF')
        text = text[1 .. $];
    if (text.length >= 3 && text[0] == 0xEF && text[1] == 0xBB && text[2] == 0xBF)
        text = text[3 .. $];
    final switch (fmt)
    {
    case ConfigFormat.json:
        return parseJSON(text);
    case ConfigFormat.json5:
        return parseJSON(stripJson5(text));
    case ConfigFormat.yaml:
        return decodeYamlLite(text);
    case ConfigFormat.toml:
        return decodeToml(text);
    case ConfigFormat.ini:
    case ConfigFormat.cfg:
        return decodeIni(text);
    case ConfigFormat.sdlang:
        return decodeSdlang(text);
    case ConfigFormat.hcl:
        return decodeHclLite(text);
    case ConfigFormat.unknown:
        throw new CodecException("unknown config format");
    }
}

string encodeFromJson(JSONValue root, ConfigFormat fmt)
{
    final switch (fmt)
    {
    case ConfigFormat.json:
    case ConfigFormat.json5:
        return toJSON(root, true);
    case ConfigFormat.yaml:
        return encodeYamlLite(root, 0);
    case ConfigFormat.toml:
        return encodeToml(root);
    case ConfigFormat.ini:
    case ConfigFormat.cfg:
        return encodeIni(root);
    case ConfigFormat.sdlang:
        return encodeSdlang(root);
    case ConfigFormat.hcl:
        return encodeHclLite(root);
    case ConfigFormat.unknown:
        throw new CodecException("unknown config format");
    }
}

ConfigNode decodeTree(string text, ConfigFormat fmt)
{
    return nodeFromJson(decodeToJson(text, fmt));
}

string encodeTree(ConfigNode root, ConfigFormat fmt)
{
    return encodeFromJson(root.toJson(), fmt);
}

/// Drop JSON5 comments and trailing commas so std.json can parse.
string stripJson5(string text)
{
    return stripJson5Lines(text);
}

private string stripJson5Lines(string text)
{
    auto app = appender!string;
    bool block;
    foreach (line; text.splitLines)
    {
        auto s = line;
        if (block)
        {
            auto end = s.indexOf("*/");
            if (end >= 0)
            {
                s = s[end + 2 .. $];
                block = false;
            }
            else
                continue;
        }
        auto trimmed = s.stripLeft;
        if (trimmed.startsWith("//"))
            continue;
        auto b = s.indexOf("/*");
        if (b >= 0)
        {
            auto e = s.indexOf("*/");
            if (e > b)
                s = s[0 .. b] ~ s[e + 2 .. $];
            else
            {
                s = s[0 .. b];
                block = true;
            }
        }
        // trailing comma before } or ]
        s = stripTrailingCommaOnLine(s);
        app.put(s);
        app.put('\n');
    }
    auto r = app.data;
    // second pass: trailing commas before closers
    import std.regex : ctRegex, replaceAll;
    static comma = ctRegex!(`,\s*([}\]])`);
    return replaceAll(r, comma, "$1");
}

private string stripTrailingCommaOnLine(string s)
{
    auto t = s.strip;
    if (t.endsWith(","))
        {}
    return s;
}

private bool endsWith(string s, string suf)
{
    return s.length >= suf.length && s[$ - suf.length .. $] == suf;
}

JSONValue decodeIni(string text)
{
    JSONValue[string] root;
    string section;
    foreach (raw; text.splitLines)
    {
        auto line = raw.strip;
        if (line.length == 0 || line.startsWith("#") || line.startsWith(";"))
            continue;
        if (line.startsWith("[") && line.length >= 2 && line[$ - 1] == ']')
        {
            section = line[1 .. $ - 1].strip;
            if (section !in root)
                root[section] = JSONValue((JSONValue[string]).init);
            continue;
        }
        auto eq = line.indexOf('=');
        if (eq < 0)
            eq = line.indexOf(':');
        if (eq < 0)
            continue;
        auto k = line[0 .. eq].strip;
        auto v = unquote(line[eq + 1 .. $].strip);
        auto val = scalarFromString(v);
        if (section.length)
        {
            auto obj = root[section].object;
            obj[k] = val;
            root[section] = JSONValue(obj);
        }
        else
            root[k] = val;
    }
    return JSONValue(root);
}

string encodeIni(JSONValue root)
{
    auto app = appender!string;
    if (root.type != JSONTypeObjectCheck(root))
        return jsonScalar(root) ~ "\n";
    // hoisted keys first
    foreach (k, v; root.object)
    {
        if (v.type == JSONType.object)
            continue;
        app.put(k);
        app.put(" = ");
        app.put(jsonScalar(v));
        app.put('\n');
    }
    foreach (k, v; root.object)
    {
        if (v.type != JSONType.object)
            continue;
        app.put('[');
        app.put(k);
        app.put("]\n");
        foreach (ck, cv; v.object)
        {
            app.put(ck);
            app.put(" = ");
            app.put(jsonScalar(cv));
            app.put('\n');
        }
        app.put('\n');
    }
    return app.data;
}

private bool JSONTypeObjectCheck(JSONValue v)
{
    import std.json : JSONType;
    return v.type == JSONType.object;
}

JSONValue decodeToml(string text) => decodeIni(rewriteToml(text));

private string rewriteToml(string text)
{
    // Treat dotted keys as nested later; flatten [table.sub] names.
    return text;
}

string encodeToml(JSONValue root)
{
    return encodeIni(root);
}

JSONValue decodeHclLite(string text)
{
    JSONValue[string] obj;
    foreach (raw; text.splitLines)
    {
        auto line = raw.strip;
        if (line.length == 0 || line.startsWith("#") || line.startsWith("//"))
            continue;
        auto eq = line.indexOf('=');
        if (eq < 0)
            continue;
        auto k = line[0 .. eq].strip;
        auto rhs = line[eq + 1 .. $].strip;
        obj[k] = parseHclRhs(rhs);
    }
    return JSONValue(obj);
}

private JSONValue parseHclRhs(string rhs)
{
    import std.json : parseJSON;
    auto t = rhs.strip;
    if (t.startsWith("[") || t.startsWith("{"))
    {
        try
            return parseJSON(t);
        catch (Exception)
        {
        }
    }
    return scalarFromString(unquote(t));
}

string encodeHclLite(JSONValue root)
{
    import std.json : toJSON, JSONType;
    auto app = appender!string;
    if (root.type != JSONType.object)
        return jsonScalar(root) ~ "\n";
    foreach (k, v; root.object)
    {
        app.put(k);
        app.put(" = ");
        if (v.type == JSONType.string)
        {
            app.put('"');
            app.put(v.str);
            app.put('"');
        }
        else
            app.put(v.toJSON());
        app.put('\n');
    }
    return app.data;
}

JSONValue decodeSdlang(string text)
{
    import sdlang : parseSource, Tag;
    JSONValue[string] obj;
    auto root = parseSource(text);
    void walk(Tag tag, ref JSONValue[string] into)
    {
        foreach (child; tag.tags)
        {
            auto name = child.name;
            if (name.length == 0)
                continue;
            if (child.tags.length)
            {
                JSONValue[string] nested;
                if (child.values.length == 1)
                    nested["_value"] = sdlAtomic(child.values[0]);
                else if (child.values.length > 1)
                    nested["_value"] = sdlList(child);
                walk(child, nested);
                into[name] = JSONValue(nested);
            }
            else if (child.values.length == 1)
                into[name] = sdlAtomic(child.values[0]);
            else if (child.values.length > 1)
                into[name] = sdlList(child);
            else
                into[name] = JSONValue((JSONValue[string]).init);
        }
    }
    walk(root, obj);
    return JSONValue(obj);
}

private JSONValue sdlAtomic(V)(V v)
{
    try
        return JSONValue(v.get!string());
    catch (Exception)
    {
    }
    try
        return JSONValue(v.get!bool());
    catch (Exception)
    {
    }
    try
        return JSONValue(cast(long) v.get!int());
    catch (Exception)
    {
    }
    try
        return JSONValue(v.get!long());
    catch (Exception)
    {
    }
    try
        return JSONValue(v.get!double());
    catch (Exception)
    {
    }
    import std.conv : to;
    return JSONValue(to!string(v));
}

private JSONValue sdlList(T)(T tag)
{
    JSONValue[] arr;
    foreach (v; tag.values)
        arr ~= sdlAtomic(v);
    return JSONValue(arr);
}

string encodeSdlang(JSONValue root)
{
    import std.json : JSONType, toJSON;
    auto app = appender!string;
    if (root.type != JSONType.object)
        return sdlLiteral(root) ~ "\n";
    foreach (k, v; root.object)
    {
        app.put(k);
        app.put(' ');
        if (v.type == JSONType.object)
        {
            app.put("{\n");
            foreach (ck, cv; v.object)
            {
                app.put("    ");
                app.put(ck);
                app.put(' ');
                app.put(sdlLiteral(cv));
                app.put('\n');
            }
            app.put("}\n");
        }
        else
        {
            app.put(sdlLiteral(v));
            app.put('\n');
        }
    }
    return app.data;
}

private string sdlLiteral(JSONValue v)
{
    import std.json : JSONType, toJSON;
    final switch (v.type)
    {
    case JSONType.string:
        return `"` ~ v.str ~ `"`;
    case JSONType.null_:
        return `""`;
    case JSONType.true_:
        return "true";
    case JSONType.false_:
        return "false";
    case JSONType.integer:
        return to!string(v.integer);
    case JSONType.uinteger:
        return to!string(v.uinteger);
    case JSONType.float_:
        return to!string(v.floating);
    case JSONType.array:
    case JSONType.object:
        return `"` ~ v.toJSON() ~ `"`;
    }
}

JSONValue decodeYamlLite(string text)
{
    // Indent-based mapping; lists with "- " at the leaf.
    struct Item
    {
        int indent;
        string key;
        string rhs;
        bool list;
    }
    Item[] items;
    foreach (raw; text.splitLines)
    {
        auto line = raw;
        if (line.strip.length == 0 || line.stripLeft.startsWith("#"))
            continue;
        if (line.strip == "---" || line.strip == "...")
            continue;
        int ind;
        while (ind < line.length && (line[ind] == ' ' || line[ind] == '\t'))
            ind++;
        auto rest = line[ind .. $];
        bool list;
        if (rest.startsWith("- "))
        {
            list = true;
            rest = rest[2 .. $];
        }
        auto colon = rest.indexOf(':');
        string k, rhs;
        if (colon >= 0 && !list)
        {
            k = rest[0 .. colon].strip;
            rhs = rest[colon + 1 .. $].strip;
        }
        else if (list)
        {
            k = "";
            rhs = rest.strip;
            auto c2 = rest.indexOf(':');
            if (c2 >= 0)
            {
                k = rest[0 .. c2].strip;
                rhs = rest[c2 + 1 .. $].strip;
            }
        }
        else
        {
            k = rest.strip;
            rhs = "";
        }
        items ~= Item(ind, k, rhs, list);
    }

    JSONValue parseFrom(ref size_t i, int parentIndent)
    {
        JSONValue[string] obj;
        JSONValue[] arr;
        bool asArr;
        while (i < items.length)
        {
            auto it = items[i];
            if (it.indent < parentIndent)
                break;
            if (it.indent > parentIndent && i > 0)
            {
                // child of previous — handled by recursion
                break;
            }
            i++;
            JSONValue val;
            if (i < items.length && items[i].indent > it.indent)
                val = parseFrom(i, items[i].indent);
            else if (it.rhs.length)
                val = scalarFromString(unquote(it.rhs));
            else
                val = JSONValue((JSONValue[string]).init);

            if (it.list && it.key.length == 0)
            {
                asArr = true;
                arr ~= val;
            }
            else if (it.key.length)
                obj[it.key] = val;
        }
        if (asArr && obj.length == 0)
            return JSONValue(arr);
        return JSONValue(obj);
    }

    size_t i;
    int base = items.length ? items[0].indent : 0;
    return parseFrom(i, base);
}

string encodeYamlLite(JSONValue v, int indent)
{
    import std.json : JSONType, toJSON;
    import std.range : repeat;
    auto pad = to!string(' '.repeat(indent));
    auto app = appender!string;
    if (v.type != JSONType.object)
    {
        app.put(jsonScalar(v));
        app.put('\n');
        return app.data;
    }
    foreach (k, child; v.object)
    {
        app.put(pad);
        app.put(k);
        app.put(':');
        if (child.type == JSONType.object)
        {
            app.put('\n');
            app.put(encodeYamlLite(child, indent + 2));
        }
        else if (child.type == JSONType.array)
        {
            app.put('\n');
            foreach (el; child.array)
            {
                app.put(pad);
                app.put("  - ");
                if (el.type == JSONType.object)
                {
                    app.put('\n');
                    app.put(encodeYamlLite(el, indent + 4));
                }
                else
                {
                    app.put(jsonScalar(el));
                    app.put('\n');
                }
            }
        }
        else
        {
            app.put(' ');
            app.put(jsonScalar(child));
            app.put('\n');
        }
    }
    return app.data;
}

private string jsonScalar(JSONValue v)
{
    import std.json : JSONType, toJSON;
    final switch (v.type)
    {
    case JSONType.string:
        return v.str;
    case JSONType.null_:
        return "";
    case JSONType.true_:
        return "true";
    case JSONType.false_:
        return "false";
    case JSONType.integer:
        return to!string(v.integer);
    case JSONType.uinteger:
        return to!string(v.uinteger);
    case JSONType.float_:
        return to!string(v.floating);
    case JSONType.array:
    case JSONType.object:
        return v.toJSON();
    }
}

private string unquote(string s)
{
    auto t = s.strip;
    if (t.length >= 2 && ((t[0] == '"' && t[$ - 1] == '"') || (t[0] == '\'' && t[$ - 1] == '\'')))
        return t[1 .. $ - 1];
    return t;
}

unittest
{
    auto j = decodeToJson(`{"a":1,"b":true}`, ConfigFormat.json);
    assert(j["a"].integer == 1);
    auto ini = decodeToJson("[user]\nname = ada\n", ConfigFormat.ini);
    assert(ini["user"]["name"].str == "ada");
    auto hcl = decodeToJson(`region = "us-east-1"` ~ "\n", ConfigFormat.hcl);
    assert(hcl["region"].str == "us-east-1");
    auto y = decodeToJson("foo: bar\nnest:\n  x: 1\n", ConfigFormat.yaml);
    assert(y["foo"].str == "bar");
}
