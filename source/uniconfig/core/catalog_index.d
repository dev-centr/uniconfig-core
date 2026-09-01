module uniconfig.core.catalog_index;

import std.array : appender;
import std.datetime : Clock;
import std.file : exists, mkdirRecurse, readText, write;
import std.path : buildPath, dirName;
import std.string : strip, toLower;
import sdlang;
import uniconfig.core.registry : defaultConfigDir;

/// One registered vocabulary catalog on the user's machine (`catalog-index.sdl`).
struct CatalogSourceEntry
{
    string id;
    string catalogPath;
    string registeredBy;
    string registeredAt;
    string repositoryUrl;
    bool repositoryClosedSource;
}

/// Arguments for `registerCatalogSource`.
struct CatalogRegistration
{
    string registeredBy = "";
    string repositoryUrl = "";
    bool repositoryClosedSource = false;
}

string defaultCatalogIndexPath()
{
    return buildPath(defaultConfigDir(), "catalog-index.sdl");
}

CatalogSourceEntry[] loadCatalogIndex(string path)
{
    CatalogSourceEntry[] acc;
    if (!exists(path))
        return acc;
    auto doc = parseSource(readText(path), path);
    foreach (tag; doc.tags)
    {
        if (tag.name != "source")
            continue;
        CatalogSourceEntry e;
        if (tag.values.length)
            e.id = tag.values[0].get!string;
        foreach (child; tag.tags)
        {
            if (child.values.length == 0)
                continue;
            auto v = child.values[0].get!string;
            switch (child.name)
            {
            case "catalog":
                e.catalogPath = v;
                break;
            case "registered-by":
                e.registeredBy = v;
                break;
            case "registered-at":
                e.registeredAt = v;
                break;
            case "repository":
                e.repositoryUrl = v;
                break;
            case "repository-closed-source":
                e.repositoryClosedSource = v.toLower == "true" || v == "1";
                break;
            default:
                break;
            }
        }
        if (e.id.length && e.catalogPath.length)
            acc ~= e;
    }
    return acc;
}

void saveCatalogIndex(CatalogSourceEntry[] entries, string path)
{
    mkdirRecurse(dirName(path));
    auto app = appender!string;
    app.put("// UniConfig — registered vocabulary catalogs (user-local)\n");
    foreach (e; entries)
    {
        app.put("source \"");
        app.put(escapeSdl(e.id));
        app.put("\" {\n");
        app.put("    catalog \"");
        app.put(escapeSdl(e.catalogPath));
        app.put("\"\n");
        if (e.registeredBy.length)
        {
            app.put("    registered-by \"");
            app.put(escapeSdl(e.registeredBy));
            app.put("\"\n");
        }
        if (e.registeredAt.length)
        {
            app.put("    registered-at \"");
            app.put(escapeSdl(e.registeredAt));
            app.put("\"\n");
        }
        if (e.repositoryClosedSource)
            app.put("    repository-closed-source true\n");
        else if (e.repositoryUrl.length)
        {
            app.put("    repository \"");
            app.put(escapeSdl(e.repositoryUrl));
            app.put("\"\n");
        }
        app.put("}\n");
    }
    write(path, app.data);
}

/// Drop index entries whose catalog file no longer exists.
CatalogSourceEntry[] pruneStaleCatalogSources(CatalogSourceEntry[] entries)
{
    CatalogSourceEntry[] kept;
    foreach (e; entries)
    {
        if (exists(e.catalogPath))
            kept ~= e;
    }
    return kept;
}

void validateCatalogRegistration(CatalogRegistration reg)
{
    import std.exception : enforce;
    enforce(reg.repositoryClosedSource || reg.repositoryUrl.strip.length > 0,
        "CatalogRegistration requires repository URL or repositoryClosedSource=true");
}

/// Idempotent: updates path and metadata when `id` already exists.
void registerCatalogSource(string id, string catalogPath, CatalogRegistration reg,
        string indexPath = defaultCatalogIndexPath())
{
    validateCatalogRegistration(reg);
    import std.exception : enforce;
    import std.path : absolutePath;
    enforce(id.length > 0, "registerCatalogSource: id required");
    enforce(catalogPath.length > 0, "registerCatalogSource: catalogPath required");
    auto absCatalog = absolutePath(catalogPath);
    enforce(exists(absCatalog), "registerCatalogSource: catalog not found: " ~ absCatalog);

    auto entries = loadCatalogIndex(indexPath);
    auto now = Clock.currTime.toISOExtString;
    bool found;
    foreach (ref e; entries)
    {
        if (e.id != id)
            continue;
        e.catalogPath = absCatalog;
        e.registeredBy = reg.registeredBy;
        e.registeredAt = now;
        e.repositoryUrl = reg.repositoryClosedSource ? "" : reg.repositoryUrl;
        e.repositoryClosedSource = reg.repositoryClosedSource;
        found = true;
        break;
    }
    if (!found)
    {
        entries ~= CatalogSourceEntry(id, absCatalog, reg.registeredBy, now,
            reg.repositoryClosedSource ? "" : reg.repositoryUrl, reg.repositoryClosedSource);
    }
    saveCatalogIndex(entries, indexPath);
}

bool unregisterCatalogSource(string id, string indexPath = defaultCatalogIndexPath())
{
    auto entries = loadCatalogIndex(indexPath);
    CatalogSourceEntry[] kept;
    bool removed;
    foreach (e; entries)
    {
        if (e.id == id)
            removed = true;
        else
            kept ~= e;
    }
    if (!removed)
        return false;
    saveCatalogIndex(kept, indexPath);
    return true;
}

CatalogSourceEntry* findCatalogSource(CatalogSourceEntry[] entries, string id)
{
    foreach (ref e; entries)
        if (e.id == id)
            return &e;
    return null;
}

private string escapeSdl(string s)
{
    import std.string : replace;
    return s.replace(`\`, `\\`).replace(`"`, `\"`);
}

unittest
{
    import std.file : remove, tempDir, write;
    auto dir = tempDir;
    auto catalog = buildPath(dir, "test-catalog.sdl");
    auto index = buildPath(dir, "test-index.sdl");
    scope (exit)
    {
        if (exists(catalog))
            remove(catalog);
        if (exists(index))
            remove(index);
    }
    write(catalog, `profile "x" { glob "*.x" format "json" }`);
    registerCatalogSource("com.test.app", catalog,
        CatalogRegistration("Test/1", "https://example.com/repo"), index);
    auto loaded = loadCatalogIndex(index);
    assert(loaded.length == 1);
    assert(loaded[0].id == "com.test.app");
    assert(loaded[0].repositoryUrl == "https://example.com/repo");
    unregisterCatalogSource("com.test.app", index);
    assert(loadCatalogIndex(index).length == 0);
}
