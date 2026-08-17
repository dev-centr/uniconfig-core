module uniconfig.core.format;

import std.path : extension;
import std.string : toLower, strip, startsWith;

enum ConfigFormat
{
    unknown,
    json,
    json5,
    yaml,
    toml,
    ini,
    cfg,
    sdlang,
    hcl, /// tfvars / HCL-lite assignments
}

string formatName(ConfigFormat f)
{
    final switch (f)
    {
    case ConfigFormat.unknown:
        return "unknown";
    case ConfigFormat.json:
        return "json";
    case ConfigFormat.json5:
        return "json5";
    case ConfigFormat.yaml:
        return "yaml";
    case ConfigFormat.toml:
        return "toml";
    case ConfigFormat.ini:
        return "ini";
    case ConfigFormat.cfg:
        return "cfg";
    case ConfigFormat.sdlang:
        return "sdlang";
    case ConfigFormat.hcl:
        return "hcl";
    }
}

ConfigFormat parseFormatName(string name)
{
    auto n = name.toLower.strip;
    if (n == "json")
        return ConfigFormat.json;
    if (n == "json5")
        return ConfigFormat.json5;
    if (n == "yaml" || n == "yml")
        return ConfigFormat.yaml;
    if (n == "toml")
        return ConfigFormat.toml;
    if (n == "ini")
        return ConfigFormat.ini;
    if (n == "cfg" || n == "conf" || n == "config")
        return ConfigFormat.cfg;
    if (n == "sdlang" || n == "sdl")
        return ConfigFormat.sdlang;
    if (n == "hcl" || n == "hcl-lite" || n == "tfvars")
        return ConfigFormat.hcl;
    return ConfigFormat.unknown;
}

ConfigFormat detectFormat(string path, string text)
{
    auto ext = extension(path).toLower;
    if (ext == ".json")
        return ConfigFormat.json;
    if (ext == ".json5")
        return ConfigFormat.json5;
    if (ext == ".yaml" || ext == ".yml")
        return ConfigFormat.yaml;
    if (ext == ".toml")
        return ConfigFormat.toml;
    if (ext == ".ini")
        return ConfigFormat.ini;
    if (ext == ".cfg" || ext == ".conf")
        return ConfigFormat.cfg;
    if (ext == ".sdl")
        return ConfigFormat.sdlang;
    if (ext == ".tfvars" || ext == ".hcl")
        return ConfigFormat.hcl;

    auto t = text.strip;
    if (t.startsWith("{") || t.startsWith("["))
        return ConfigFormat.json;
    if (t.startsWith("---") || looksLikeYaml(t))
        return ConfigFormat.yaml;
    if (looksLikeSdl(t))
        return ConfigFormat.sdlang;
    if (t.canHaveIni())
        return ConfigFormat.ini;
    return ConfigFormat.unknown;
}

private bool looksLikeYaml(string t)
{
    import std.algorithm : canFind;
    return t.canFind(":\n") || t.canFind(": ");
}

private bool looksLikeSdl(string t)
{
    import std.algorithm : canFind;
    return t.canFind(`"`) && !t.canFind("{") && t.canFind("\n");
}

private bool canHaveIni(string t)
{
    import std.algorithm : canFind;
    return t.canFind("[") && t.canFind("]");
}

unittest
{
    assert(detectFormat("x.json", "{}") == ConfigFormat.json);
    assert(detectFormat("a.tfvars", "") == ConfigFormat.hcl);
    assert(parseFormatName("SDL") == ConfigFormat.sdlang);
}
