module uniconfig.core.tree;

import std.algorithm : canFind, map;
import std.array : array, appender;
import std.conv : to;
import std.format : format;
import std.json : JSONValue, JSONType;

/// Leaf or container node in the unified config tree.
class ConfigNode
{
    string key; /// Last path segment. Empty on the document root.
    string path; /// Dotted path from the root (`user.name`).
    JSONValue value; /// Scalar or container as JSON. Objects also have `children`.
    ConfigNode[] children;
    string comment;
    bool fromFile; /// Present in the opened document.
    bool fromSchema; /// Declared by a schema or profile even if unset.
    bool included = true; /// User opted the field into the saved file.
    string description; /// Copied from schema when known.
    string title;
    string[] enumValues;
    string schemaType; /// `string`, `integer`, `number`, `boolean`, `object`, `array`.
    bool required;

    bool isObject() const
    {
        return children.length > 0 || value.type == JSONType.object;
    }

    ConfigNode child(string name)
    {
        foreach (c; children)
            if (c.key == name)
                return c;
        return null;
    }

    ConfigNode childAt(string dotted)
    {
        auto cur = this;
        foreach (seg; dotted.splitDots)
        {
            if (cur is null)
                return null;
            cur = cur.child(seg);
        }
        return cur;
    }

    void putChild(ConfigNode n)
    {
        foreach (i, c; children)
        {
            if (c.key == n.key)
            {
                children[i] = n;
                return;
            }
        }
        children ~= n;
    }

    ConfigNode[] walkLeaves()
    {
        ConfigNode[] acc;
        void rec(ConfigNode n)
        {
            if (n.children.length == 0 && n !is this)
            {
                acc ~= n;
                return;
            }
            if (n.children.length == 0 && n is this && n.fromFile)
                acc ~= n;
            foreach (c; n.children)
                rec(c);
        }
        rec(this);
        return acc;
    }

    JSONValue toJson() const
    {
        if (children.length == 0)
            return value;
        JSONValue[string] obj;
        foreach (c; children)
            obj[c.key] = c.toJson();
        return JSONValue(obj);
    }
}

string[] splitDots(string dotted)
{
    import std.array : split;
    if (dotted.length == 0)
        return [];
    return dotted.split(".");
}

string joinPath(string parent, string key)
{
    if (parent.length == 0)
        return key;
    if (key.length == 0)
        return parent;
    return parent ~ "." ~ key;
}

ConfigNode nodeFromJson(JSONValue v, string key = "", string path = "")
{
    auto n = new ConfigNode;
    n.key = key;
    n.path = path.length ? path : key;
    n.value = v;
    n.fromFile = true;
    n.included = true;
    if (v.type == JSONType.object)
    {
        foreach (k, child; v.object)
            n.putChild(nodeFromJson(child, k, joinPath(n.path, k)));
    }
    else if (v.type == JSONType.array)
    {
        n.schemaType = "array";
    }
    return n;
}

JSONValue scalarFromString(string s)
{
    import std.string : toLower, strip;
    auto t = s.strip;
    if (t == "true")
        return JSONValue(true);
    if (t == "false")
        return JSONValue(false);
    if (t == "null" || t.length == 0)
        return JSONValue(null);
    try
    {
        if (t.canFind('.') || t.canFind('e') || t.canFind('E'))
            return JSONValue(to!double(t));
        return JSONValue(to!long(t));
    }
    catch (Exception)
    {
        return JSONValue(s);
    }
}

string displayValue(const ConfigNode n)
{
    if (n is null)
        return "";
    if (n.children.length)
        return format("{%s keys}", n.children.length);
    final switch (n.value.type)
    {
    case JSONType.null_:
        return "";
    case JSONType.true_:
        return "true";
    case JSONType.false_:
        return "false";
    case JSONType.integer:
        return to!string(n.value.integer);
    case JSONType.uinteger:
        return to!string(n.value.uinteger);
    case JSONType.float_:
        return to!string(n.value.floating);
    case JSONType.string:
        return n.value.str;
    case JSONType.array:
        return n.value.toString();
    case JSONType.object:
        return n.value.toString();
    }
}

void setDisplayValue(ConfigNode n, string text)
{
    if (n.enumValues.length || n.schemaType == "string")
    {
        n.value = JSONValue(text);
        return;
    }
    if (n.schemaType == "boolean")
    {
        n.value = JSONValue(text.toLowerAscii == "true");
        return;
    }
    if (n.schemaType == "integer")
    {
        try
            n.value = JSONValue(to!long(text));
        catch (Exception)
            n.value = JSONValue(text);
        return;
    }
    if (n.schemaType == "number")
    {
        try
            n.value = JSONValue(to!double(text));
        catch (Exception)
            n.value = JSONValue(text);
        return;
    }
    n.value = scalarFromString(text);
}

private string toLowerAscii(string s)
{
    import std.string : toLower;
    return s.toLower;
}

unittest
{
    auto n = nodeFromJson(JSONValue(["a": JSONValue(1), "b": JSONValue("x")]));
    assert(n.child("a") !is null);
    assert(n.child("a").value.integer == 1);
    assert(n.childAt("b").value.str == "x");
}
