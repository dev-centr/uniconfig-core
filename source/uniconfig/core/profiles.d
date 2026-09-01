module uniconfig.core.profiles;

import std.algorithm : canFind;
import std.array : appender;
import std.file : dirEntries, SpanMode, exists, readText, isFile, isDir;
import std.path : buildPath, globMatch, baseName, dirName, absolutePath;
import std.string : startsWith, toLower;
import sdlang;
import uniconfig.core.format;
import uniconfig.core.schema;

struct ConfigProfile
{
    string id;
    string title;
    string[] globs;
    ConfigFormat format = ConfigFormat.unknown;
    string schemaPath; /// relative to the catalog file, or `bundled:<name>`
    string description;
    /// Registered catalog source (`catalog-index.sdl`) or `bundled`.
    string sourceId;
    string catalogPath;
    string repositoryUrl;
    bool repositoryClosedSource;
}

ConfigProfile[] loadProfileCatalog(string sdlText, string catalogDir = ".")
{
    ConfigProfile[] acc;
    auto doc = parseSource(sdlText, catalogDir);
    foreach (tag; doc.tags)
    {
        if (tag.name != "profile")
            continue;
        ConfigProfile p;
        if (tag.values.length)
            p.id = tag.values[0].get!string;
        foreach (child; tag.tags)
        {
            if (child.values.length == 0)
                continue;
            auto v = child.values[0].get!string;
            switch (child.name)
            {
            case "title":
                p.title = v;
                break;
            case "glob":
                p.globs ~= v;
                break;
            case "format":
                p.format = parseFormatName(v);
                break;
            case "schema":
                p.schemaPath = v;
                break;
            case "description":
                p.description = v;
                break;
            default:
                break;
            }
        }
        if (p.title.length == 0)
            p.title = p.id;
        acc ~= p;
    }
    return acc;
}

ConfigProfile[] loadProfileCatalogFile(string path)
{
    return loadProfileCatalog(readText(path), dirName(path));
}

ConfigProfile[] loadProfileDirectory(string dir)
{
    ConfigProfile[] acc;
    if (!exists(dir) || !isDir(dir))
        return acc;
    foreach (e; dirEntries(dir, SpanMode.shallow))
    {
        if (!e.isFile)
            continue;
        auto n = baseName(e.name).toLower;
        if (!(n.length > 4 && n[$ - 4 .. $] == ".sdl"))
            continue;
        acc ~= loadProfileCatalogFile(e.name);
    }
    return acc;
}

ConfigProfile* matchProfile(ConfigProfile[] profiles, string filePath)
{
    auto abs = absolutePath(filePath);
    auto bn = baseName(filePath);
    foreach (ref p; profiles)
    {
        foreach (g; p.globs)
        {
            if (globMatch(bn, g) || globMatch(abs, g) || globMatch(filePath, g)
                    || globMatch(abs.replaceSlash, g.replaceSlash))
                return &p;
        }
    }
    return null;
}

private string replaceSlash(string s)
{
    import std.array : replace;
    return s.replace("\\", "/");
}

DocumentSchema schemaForProfile(const ConfigProfile p, string catalogDir, string bundledDir)
{
    auto spec = p.schemaPath;
    if (spec.length == 0)
        return DocumentSchema.init;
    string path;
    if (spec.startsWith("bundled:"))
        path = buildPath(bundledDir, spec["bundled:".length .. $]);
    else
        path = buildPath(catalogDir, spec);
    if (!exists(path))
        return DocumentSchema.init;
    return loadSchemaFile(path);
}

unittest
{
    auto txt = q{
profile "gitconfig" {
    title "Git config"
    glob ".gitconfig"
    glob "**/config"
    format "ini"
    schema "bundled:gitconfig.schema.json"
    description "User and repo Git configuration"
}
};
    auto ps = loadProfileCatalog(txt);
    assert(ps.length == 1);
    assert(ps[0].id == "gitconfig");
    assert(matchProfile(ps, `/tmp/.gitconfig`) !is null);
}
