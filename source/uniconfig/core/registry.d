module uniconfig.core.registry;

import std.array : appender;
import std.datetime : Clock, SysTime;
import std.file : exists, mkdirRecurse, write, readText;
import std.path : dirName, buildPath;
import std.string : replace;
import sdlang;

struct RegistryEntry
{
    string path;
    string profileId;
    string title;
    string lastOpened; /// ISO-ish timestamp
}

struct ConfigRegistry
{
    RegistryEntry[] files;

    const(RegistryEntry)* find(string path)
    {
        foreach (ref e; files)
            if (e.path == path)
                return &e;
        return null;
    }

    void touch(string path, string profileId, string title)
    {
        auto now = Clock.currTime.toISOExtString;
        foreach (ref e; files)
        {
            if (e.path == path)
            {
                e.profileId = profileId;
                e.title = title.length ? title : e.title;
                e.lastOpened = now;
                return;
            }
        }
        files ~= RegistryEntry(path, profileId, title, now);
    }
}

ConfigRegistry loadRegistry(string path)
{
    ConfigRegistry r;
    if (!exists(path))
        return r;
    auto doc = parseSource(readText(path), path);
    foreach (tag; doc.tags)
    {
        if (tag.name != "file")
            continue;
        RegistryEntry e;
        if (tag.values.length)
            e.path = tag.values[0].get!string;
        foreach (child; tag.tags)
        {
            if (child.values.length == 0)
                continue;
            auto v = child.values[0].get!string;
            switch (child.name)
            {
            case "profile":
                e.profileId = v;
                break;
            case "title":
                e.title = v;
                break;
            case "last-opened":
                e.lastOpened = v;
                break;
            default:
                break;
            }
        }
        if (e.path.length)
            r.files ~= e;
    }
    return r;
}

void saveRegistry(ConfigRegistry r, string path)
{
    mkdirRecurse(dirName(path));
    auto app = appender!string;
    app.put("// UniConfig Config Panel — opened files\n");
    foreach (e; r.files)
    {
        app.put("file \"");
        app.put(escapeSdl(e.path));
        app.put("\" {\n");
        if (e.profileId.length)
        {
            app.put("    profile \"");
            app.put(escapeSdl(e.profileId));
            app.put("\"\n");
        }
        if (e.title.length)
        {
            app.put("    title \"");
            app.put(escapeSdl(e.title));
            app.put("\"\n");
        }
        if (e.lastOpened.length)
        {
            app.put("    last-opened \"");
            app.put(escapeSdl(e.lastOpened));
            app.put("\"\n");
        }
        app.put("}\n");
    }
    write(path, app.data);
}

string defaultRegistryPath()
{
    import std.process : environment;
    import std.path : buildPath;
    version (Windows)
    {
        auto base = environment.get("LOCALAPPDATA");
        if (base.length == 0)
            base = environment.get("USERPROFILE", ".");
        return buildPath(base, "UniConfig", "registry.sdl");
    }
    else
    {
        auto xdg = environment.get("XDG_CONFIG_HOME");
        if (xdg.length == 0)
        {
            auto home = environment.get("HOME", ".");
            xdg = buildPath(home, ".config");
        }
        return buildPath(xdg, "uniconfig", "registry.sdl");
    }
}

string defaultConfigDir()
{
    import std.path : dirName;
    return dirName(defaultRegistryPath());
}

private string escapeSdl(string s)
{
    return s.replace(`\`, `\\`).replace(`"`, `\"`);
}

unittest
{
    ConfigRegistry r;
    r.touch(`/tmp/a.ini`, "gitconfig", "A");
    assert(r.find(`/tmp/a.ini`) !is null);
}
