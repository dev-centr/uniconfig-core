# uniconfig-core — agent notes

- Library only: config tree, codecs (JSON, JSON5-lite, YAML-lite, TOML, INI/cfg, SDLang, HCL-lite/tfvars), JSON Schema subset, profile catalog, file registry.
- No GUI. The desktop app is `dev-centr/uniconfig` (`uniconfig` binary).
- Public import: `import uniconfig.core;`
- Profiles shipped with the app, not this package. The engine loads SDLang catalogs from caller-supplied paths.
- Do not commit secrets. User registry lives under `%LOCALAPPDATA%\UniConfig\` (or `$XDG_CONFIG_HOME/uniconfig/`).
