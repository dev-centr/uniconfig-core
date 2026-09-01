# uniconfig-core — agent notes

- Library only: config tree, codecs, JSON Schema subset, catalog index API, profile resolver, file registry.
- Vocabulary catalogs ship with **apps**; register via `registerCatalogSource`. User index: `catalog-index.sdl` beside `registry.sdl`.
- Bundled profiles (fallback pack) ship with ConfigUI, not this package.
- Do not commit secrets. User registry lives under `%LOCALAPPDATA%\UniConfig\` (or `$XDG_CONFIG_HOME/uniconfig/`).
