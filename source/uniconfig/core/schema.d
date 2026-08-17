module uniconfig.core.schema;

import std.json : JSONValue, JSONType, parseJSON;
import std.file : exists, readText;
import std.path : dirName, buildPath, baseName;
import std.string : strip, indexOf, startsWith, splitLines;
import uniconfig.core.tree;

struct FieldSchema
{
    string name;
    string path;
    string type = "string";
    string title;
    string description;
    string[] enumValues;
    JSONValue defaultValue;
    bool required;
    bool additionalProperties = true;
    FieldSchema[] properties;
}

struct DocumentSchema
{
    string id;
    string title;
    string source; /// path or URL the schema was loaded from
    FieldSchema root;
}

DocumentSchema schemaFromJsonText(string text, string source = "")
{
    auto j = parseJSON(text);
    DocumentSchema ds;
    ds.source = source;
    if ("$id" in j)
        ds.id = j["$id"].str;
    if ("title" in j)
        ds.title = j["title"].str;
    ds.root = fieldFromJson(j, "", "");
    if (ds.title.length == 0)
        ds.title = ds.root.title;
    return ds;
}

FieldSchema fieldFromJson(JSONValue j, string name, string path)
{
    FieldSchema f;
    f.name = name;
    f.path = path;
    if (j.type != JSONType.object)
        return f;
    if ("type" in j && j["type"].type == JSONType.string)
        f.type = j["type"].str;
    else if ("properties" in j)
        f.type = "object";
    if ("title" in j && j["title"].type == JSONType.string)
        f.title = j["title"].str;
    if ("description" in j && j["description"].type == JSONType.string)
        f.description = j["description"].str;
    if ("enum" in j && j["enum"].type == JSONType.array)
    {
        foreach (e; j["enum"].array)
        {
            if (e.type == JSONType.string)
                f.enumValues ~= e.str;
            else
                f.enumValues ~= e.toString();
        }
    }
    if ("default" in j)
        f.defaultValue = j["default"];
    if ("additionalProperties" in j && j["additionalProperties"].type == JSONType.false_)
        f.additionalProperties = false;
    string[] required;
    if ("required" in j && j["required"].type == JSONType.array)
    {
        foreach (r; j["required"].array)
            if (r.type == JSONType.string)
                required ~= r.str;
    }
    if ("properties" in j && j["properties"].type == JSONType.object)
    {
        f.type = "object";
        foreach (k, child; j["properties"].object)
        {
            auto nest = fieldFromJson(child, k, joinPath(path, k));
            foreach (rq; required)
                if (rq == k)
                    nest.required = true;
            f.properties ~= nest;
        }
    }
    return f;
}

/// Infer a schema from an existing instance so the UI still has types.
DocumentSchema inferSchema(ConfigNode root, string title = "Inferred")
{
    DocumentSchema ds;
    ds.id = "inferred";
    ds.title = title;
    ds.source = "infer";
    ds.root = inferField(root, "", "");
    ds.root.type = "object";
    return ds;
}

FieldSchema inferField(ConfigNode n, string name, string path)
{
    FieldSchema f;
    f.name = name;
    f.path = path;
    f.title = name;
    if (n.children.length)
    {
        f.type = "object";
        foreach (c; n.children)
            f.properties ~= inferField(c, c.key, c.path);
        return f;
    }
    import std.json : JSONType;
    final switch (n.value.type)
    {
    case JSONType.true_:
    case JSONType.false_:
        f.type = "boolean";
        break;
    case JSONType.integer:
    case JSONType.uinteger:
        f.type = "integer";
        break;
    case JSONType.float_:
        f.type = "number";
        break;
    case JSONType.array:
        f.type = "array";
        break;
    case JSONType.object:
        f.type = "object";
        break;
    case JSONType.string:
    case JSONType.null_:
        f.type = "string";
        break;
    }
    f.defaultValue = n.value;
    return f;
}

/// Locate `$schema` / YAML modeline / TOML `#:schema` / sidecar `<file>.schema.json`.
string discoverSchemaPointer(string filePath, string text)
{
    import std.file : exists;
    auto sidecar = filePath ~ ".schema.json";
    if (exists(sidecar))
        return sidecar;
    auto dirSidecar = buildPath(dirName(filePath), "schema.json");
    if (exists(dirSidecar))
        return dirSidecar;

    foreach (line; text.splitLines)
    {
        auto t = line.strip;
        if (t.startsWith(`"$schema"`) || t.startsWith(`"$schema":`))
        {
            auto q = t.indexOf("http");
            if (q < 0)
                q = t.indexOf("./");
            if (q >= 0)
            {
                auto rest = t[q .. $];
                auto end = rest.indexOf('"');
                if (end > 0)
                    return rest[0 .. end];
            }
        }
        auto y = "yaml-language-server: $schema=";
        auto idx = t.indexOf(y);
        if (idx >= 0)
            return t[idx + y.length .. $].strip;
        if (t.startsWith("#:schema "))
            return t["#:schema ".length .. $].strip;
        if (t.startsWith("# @schema "))
            return t["# @schema ".length .. $].strip;
    }
    return "";
}

DocumentSchema loadSchemaFile(string path)
{
    return schemaFromJsonText(readText(path), path);
}

unittest
{
    auto ds = schemaFromJsonText(`{
      "title": "Demo",
      "type": "object",
      "properties": {
        "name": { "type": "string", "description": "Display name" },
        "port": { "type": "integer", "default": 8080 }
      },
      "required": ["name"]
    }`);
    assert(ds.title == "Demo");
    assert(ds.root.properties.length == 2);
    assert(ds.root.properties[0].name == "name" || ds.root.properties[1].name == "name");
}
