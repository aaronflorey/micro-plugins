# micro-plugins

A collection of [Micro editor](https://github.com/zyedidia/micro) plugins: `format`, `configdel`, and `jsonschema`. Each plugin is a standalone Lua file and help doc under `plugins/<name>/`.

## Commands

- **No test framework** — plugins are Lua scripts for Micro editor; no test runner exists. Validate by loading in Micro and exercising the feature manually.
- **No build step** — plugins are plain Lua; no compilation.
- **Release automation**: `release-please` manages plugin version bumps and GitHub releases from Conventional Commits. Each plugin has its own `version.txt` and `CHANGELOG.md` under `plugins/<name>/`.
- **Manual lint**: none configured. The Lua code is not linted.

## Plugin Architecture

Each plugin under `plugins/<name>/` follows this structure:

```
plugins/<name>/
  <name>.lua       # Main plugin code
  repo.json        # Plugin metadata for Micro's plugin manager
  version.txt      # Canonical version for release-please's simple strategy
  CHANGELOG.md     # Per-plugin changelog maintained by release-please
  help/
    <name>.md      # Micro help file (registered via config.AddRuntimeFile)
```

The top-level `repo.json` is kept for backward compatibility but only exposes the `format` plugin (Micro resolves `plugins[0]` only). The `channel.json` file is the proper install channel — it points to each plugin's per-plugin `repo.json`.

**repo.json format**: Array of plugin objects. Each `Version` entry **must** include a `Url` field pointing to a downloadable `.zip` archive for that plugin version. Micro's plugin manager downloads and unpacks that archive; a raw `.lua` URL is not installable.

### Micro Plugin API

Plugins use Micro's embedded Lua API with these imports:

```lua
local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local filepath = import("path/filepath")
local strings = import("strings")
local os = import("os")
```

### Required Functions

Every plugin must export:

- **`init()`** — Register options, commands, and help files. Called once at plugin load.
- **`onSave(bp)`** — Called on every buffer save. Must return `true`. Options from `bp.Buf.Settings`.

### Plugin Registration Pattern

```lua
function init()
    config.RegisterCommonOption("pluginname", "onsave", true)
    config.MakeCommand("command-name", handler_func, config.NoComplete)
    config.AddRuntimeFile("pluginname", config.RTHelp, "help/pluginname.md")
end
```

### Settings Access

Plugin settings are accessed from `bp.Buf.Settings["pluginname.key"]`. Defaults are registered via `config.RegisterCommonOption`. The `setting_enabled` helper (in jsonschema) safely resolves with a fallback default.

### Error Conventions

- User-facing errors: `micro.InfoBar():Error("pluginname: message")`
- Success messages: `micro.InfoBar():Message("pluginname: message")`
- Info logging: `micro.Log(message)`
- Plugin name prefix on all messages (lowercase, no trailing space)
- Errors bubble up through `tostring(err)` from `shell.ExecCommand`

### Tools & External Dependencies

Each plugin requires external CLI tools. Resolution follows two strategies:

1. **Local-first**: check project-local paths (`node_modules/.bin/`, `vendor/bin/`, `.venv/bin/`, `venv/bin/`)
2. **Fallback**: search `$PATH` via `os.Getenv("PATH")` and `os.Stat()`
3. **Upward search**: `find_upwards` traverses parent directories from the file's directory looking for local binaries

Relevant external tools per plugin:
- **format**: `oxfmt`, `ecs`, `gofmt`, `ruff`, `black`, `stylua`, `shfmt`, `rustfmt` (varies by file type)
- **configdel**: `yq` v4+
- **jsonschema**: Sourcemeta `jsonschema` CLI

### File Modification & Buffer Reload

Plugins that modify files externally (format, configdel) call `bp.Buf:ReOpen()` to reload the buffer from disk. The buffer must be saved first (`bp:Save()`). On-save handlers run the action silently and reopen after.

### Cursor & Location Handling

- Cursor `Y` is 0-indexed line, `X` is 0-indexed column
- When passing to external tools or displaying, add 1 (`cursor.Y + 1`, `cursor.X + 1`)
- `bp.Buf:Line(n)` uses 0-indexed lines

### Diagnostics (jsonschema only)

The jsonschema plugin uses `buffer.NewMessage` and `buffer.NewMessageAtLine` to surface validation errors as Micro buffer diagnostics. Messages use `diagnostic_owner = "jsonschema"` for scoped clearing via `buf:ClearMessages(diagnostic_owner)`.

### Buffer-to-Line reading

The jsonschema plugin implements an embedded JSON parser for building a pointer-to-location map. This maps JSON Pointer paths to line/col positions in the buffer to pin diagnostic locations accurately.

## Versioning

- VERSION constant at top of each `.lua` file: `VERSION = "0.2.1"`
- `repo.json` version lives at `data[0].Versions[0].Version`
- `plugins/<name>/version.txt` is the canonical version file for `release-please`
- `release-please` keeps `version.txt`, the plugin `VERSION` constant, and the plugin `repo.json` in sync
- The top-level `repo.json` is additionally updated by the `format` release because it is the backward-compatible single-plugin entrypoint
- Build fresh release archives with `bun scripts/package-plugin-releases.ts` when you need a local artifact preview; the script writes to `dist/plugin-releases/`
- The GitHub Actions `release-please` workflow uploads release zip assets in the same workflow run

## Buffer Reopen Pattern

`bp.Buf:ReOpen()` is used after external file modification. This is non-obvious — the buffer picks up the on-disk changes. Always save first via `bp:Save()`, then run the external command, then `ReOpen()`.

## Binding Keys (configdel)

The configdel plugin shows the defensive binding pattern used:

```lua
local bound = false
if config.BindKey ~= nil then
    local ok = pcall(config.BindKey, "Alt-d", "command:del-key", false)
    bound = ok
end
if not bound then
    config.TryBindKey("Alt-d", "command:del-key", false)
end
```

This handles API evolution across Micro versions — `BindKey` was added later, `TryBindKey` is the older fallback.

## Manual Verification

See `testdata/jsonschema/` for example files used to manually test schema validation. No automated tests exist — testing is done by loading plugins in Micro and running commands or saving files.

## Mise Tooling

Defined in `mise.toml`:
- `jsonschema` — latest
- `bun` — latest
