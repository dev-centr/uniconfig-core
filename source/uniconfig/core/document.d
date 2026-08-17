module uniconfig.core.document;

import std.file : readText, write, exists;
import std.json : JSONValue;
import std.path : baseName, dirName, absolutePath, buildPath;
import uniconfig.core.tree;
import uniconfig.core.format;
import uniconfig.core.codec;
import uniconfig.core.schema;
import uniconfig.core.merge;
import uniconfig.core.profiles;
import uniconfig.core.registry;

struct OpenedDocument
{
    string path;
    ConfigFormat format;
    ConfigProfile profile;
    DocumentSchema schema;
    ConfigNode instance; /// as on disk
    ConfigNode merged; /// schema overlay
    string raw;
    bool dirty;
}

struct OpenContext
{
    ConfigProfile[] profiles;
    string bundledSchemaDir;
    string profileCatalogDir;
}

OpenedDocument openDocument(string path, OpenContext ctx)
{
    OpenedDocument d;
    d.path = absolutePath(path);
    d.raw = exists(path) ? readText(path) : "";
    auto matched = matchProfile(ctx.profiles, d.path);
    if (matched !is null)
        d.profile = *matched;

    d.format = d.profile.format != ConfigFormat.unknown
        ? d.profile.format : detectFormat(d.path, d.raw);

    if (d.format == ConfigFormat.unknown)
        d.format = ConfigFormat.json;

    if (d.raw.length)
        d.instance = decodeTree(d.raw, d.format);
    else
        d.instance = new ConfigNode;

    if (d.profile.id.length)
        d.schema = schemaForProfile(d.profile, ctx.profileCatalogDir, ctx.bundledSchemaDir);

    if (d.schema.root.properties.length == 0)
    {
        auto ptr = discoverSchemaPointer(d.path, d.raw);
        if (ptr.length && exists(ptr))
            d.schema = loadSchemaFile(ptr);
        else if (ptr.length && exists(buildPath(dirName(d.path), ptr)))
            d.schema = loadSchemaFile(buildPath(dirName(d.path), ptr));
    }

    if (d.schema.root.properties.length == 0)
        d.schema = inferSchema(d.instance, baseName(d.path));

    d.merged = mergeSchema(d.instance, d.schema);
    return d;
}

void saveDocument(OpenedDocument d)
{
    auto json = d.merged.toJson();
    // Drop fields the user left out of the file.
    json = pruneUnincluded(d.merged);
    auto text = encodeFromJson(json, d.format);
    write(d.path, text);
}

JSONValue pruneUnincluded(ConfigNode n)
{
    import std.json : JSONValue, JSONType;
    if (n.children.length == 0)
        return n.included ? n.value : JSONValue(null);

    JSONValue[string] obj;
    foreach (c; n.children)
    {
        if (!c.included && !c.fromFile)
            continue;
        if (!c.included && c.fromSchema && !c.fromFile)
            continue;
        if (c.children.length)
        {
            auto nested = pruneUnincluded(c);
            if (nested.type == JSONType.object && nested.object.length == 0 && !c.fromFile)
                continue;
            obj[c.key] = nested;
        }
        else if (c.included)
            obj[c.key] = c.value;
    }
    return JSONValue(obj);
}

void registerOpened(ref ConfigRegistry reg, const OpenedDocument d)
{
    auto title = d.profile.title.length ? d.profile.title : baseName(d.path);
    if (d.schema.title.length)
        title = d.schema.title;
    reg.touch(d.path, d.profile.id, title);
}
