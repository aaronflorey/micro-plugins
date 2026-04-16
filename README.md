# micro-plugins

Repository for Micro editor plugins.

This repository currently contains one plugin: `format`.

## Repository Layout

- `plugins/<plugin-name>/`: plugin source tree for each Micro plugin.
- `plugins/format/`: current formatter plugin.
- `repo.json`: repository metadata for Micro plugin installation.
- `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`: open
  source publication docs.

## Current Plugin

### `format`

Formats the current buffer with an installed formatter matched to the file
type.

Plugin files live under `plugins/format/`.

## Features

- Adds the `format` command.
- Formats on save by default with `format.onsave`.
- Prefers project-local formatter binaries when available.
- Falls back to formatter executables on `$PATH`.

## Formatter Mapping

- `oxfmt`: JavaScript, TypeScript, JSX, TSX, JSON, JSON5, YAML, TOML, HTML,
  CSS, SCSS, Less, Markdown, MDX, GraphQL, Vue, Handlebars.
- `ecs`: PHP.
- `gofmt`: Go.
- `ruff format`, then `black`: Python.
- `stylua`: Lua.
- `shfmt`: shell.
- `rustfmt`: Rust.

## Install

### Option 1: Clone Directly

Clone or copy the plugin directory itself into Micro's plugin directory:

```bash
git clone https://github.com/aaronflorey/micro-plugins.git /tmp/micro-plugins
cp -R /tmp/micro-plugins/plugins/format ~/.config/micro/plug/format
```

Restart Micro after installing the plugin directory.

### Option 2: Use `repo.json`

Once this repository is hosted somewhere with a raw file URL, add its
`repo.json` to your Micro config:

```json
{
  "pluginrepos": [
    "https://github.com/aaronflorey/micro-plugins/main/repo.json"
  ]
}
```

Then install the plugin:

```bash
micro -plugin install format
```

Or inside Micro:

```text
> plugin install format
```

## Usage

Format the current buffer:

```text
> format
```

Disable format-on-save for the current buffer:

```text
> setlocal format.onsave false
```

Disable format-on-save globally:

```text
> set format.onsave false
```

The current buffer must already be saved to disk.

## Local Formatter Resolution

The plugin checks for project-local tools first:

- `node_modules/.bin/oxfmt`
- `vendor/bin/ecs`
- `.venv/bin/ruff`
- `venv/bin/ruff`
- `.venv/bin/black`
- `venv/bin/black`

If none are found, it tries the matching global executable from `$PATH`.

## Adding More Plugins

This repository is now structured for additional plugins.

- `repo.json` already supports multiple plugin entries.
- Each plugin should live in its own `plugins/<plugin-name>/` directory.
- Each published plugin should be packaged from that plugin directory, not from
  the monorepo root.

## Publishing Notes

Before publishing this plugin, update `repo.json` so `Website` points at the
actual repository URL.
