module uniconfig.core.profile_resolver;

import std.file : exists;
import std.path : buildPath, dirName;
import uniconfig.core.catalog_index;
import uniconfig.core.profiles;

/// Lazy vocabulary resolution: bundled fallback + user-local registered catalogs.
struct ProfileResolver
{
    string bundledDir;
    private CatalogSourceEntry[] _sources;
    private ConfigProfile[] _bundled;
    private ConfigProfile[] _registered;
    private bool _indexLoaded;
    private bool _registeredLoaded;

    void loadBundled()
    {
        if (bundledDir.length == 0)
            return;
        auto cat = buildPath(bundledDir, "catalog.sdl");
        if (exists(cat))
            _bundled = loadProfileCatalogFile(cat);
        else
            _bundled = loadProfileDirectory(bundledDir);
        foreach (ref p; _bundled)
        {
            p.sourceId = "bundled";
            p.catalogPath = cat;
            p.repositoryUrl = "https://github.com/dev-centr/uniconfig";
            p.repositoryClosedSource = false;
        }
    }

    void refreshIndex(bool pruneStale = true, string indexPath = defaultCatalogIndexPath())
    {
        _sources = loadCatalogIndex(indexPath);
        if (pruneStale)
        {
            auto pruned = pruneStaleCatalogSources(_sources);
            if (pruned.length != _sources.length)
            {
                _sources = pruned;
                saveCatalogIndex(_sources, indexPath);
            }
        }
        _indexLoaded = true;
        _registeredLoaded = false;
    }

    private void ensureRegisteredProfiles(string indexPath = defaultCatalogIndexPath())
    {
        if (_registeredLoaded)
            return;
        if (!_indexLoaded)
            refreshIndex(true, indexPath);
        _registered = [];
        foreach (ref s; _sources)
        {
            if (!exists(s.catalogPath))
                continue;
            auto profiles = loadProfileCatalogFile(s.catalogPath);
            foreach (ref p; profiles)
            {
                p.sourceId = s.id;
                p.catalogPath = s.catalogPath;
                p.repositoryUrl = s.repositoryUrl;
                p.repositoryClosedSource = s.repositoryClosedSource;
            }
            _registered ~= profiles;
        }
        _registeredLoaded = true;
    }

    ConfigProfile[] allProfiles(string indexPath = defaultCatalogIndexPath())
    {
        ensureRegisteredProfiles(indexPath);
        return _bundled ~ _registered;
    }

    ConfigProfile* match(string filePath, string indexPath = defaultCatalogIndexPath())
    {
        ensureRegisteredProfiles(indexPath);
        if (auto p = matchProfile(_bundled, filePath))
            return p;
        return matchProfile(_registered, filePath);
    }

    CatalogSourceEntry* sourceForProfile(const ConfigProfile p)
    {
        if (p.sourceId == "bundled" || p.sourceId.length == 0)
            return null;
        return findCatalogSource(_sources, p.sourceId);
    }

    string catalogDirFor(const ConfigProfile p)
    {
        if (p.catalogPath.length)
            return dirName(p.catalogPath);
        return bundledDir;
    }
}

ProfileResolver makeProfileResolver(string bundledDir, bool refreshIndexNow = true)
{
    ProfileResolver r;
    r.bundledDir = bundledDir;
    r.loadBundled();
    if (refreshIndexNow)
        r.refreshIndex(true);
    return r;
}
