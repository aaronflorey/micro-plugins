# micro-plugins

Repository for Micro editor plugins.

This repository currently contains three plugins: `format`, `configdel`, and
`jsonschema`.

## Repository Layout

- `plugins/<plugin-name>/`: plugin source tree for each Micro plugin.
- `plugins/format/`: formatter plugin.
- `plugins/configdel/`: config key deletion plugin.
- `plugins/jsonschema/`: JSON Schema validation plugin.
- `repo.json`: repository metadata for Micro plugin installation.
- `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`: open
  source publication docs.

## Current Plugins

### `format`

Formats the current buffer with an installed formatter matched to the file
type.

Plugin files live under `plugins/format/`.

#### Features

- Adds the `format` command.
- Formats on save by default with `format.onsave`.
- Prefers project-local formatter binaries when available.
- Falls back to formatter executables on `$PATH`.

#### Formatter Mapping

- `oxfmt`: JavaScript, TypeScript, JSX, TSX, JSON, JSON5, YAML, TOML, HTML,
  CSS, SCSS, Less, Markdown, MDX, GraphQL, Vue, Handlebars.
- `ecs`: PHP.
- `gofmt`: Go.
- `ruff format`, then `black`: Python.
- `stylua`: Lua.
- `shfmt`: shell.
- `rustfmt`: Rust.

#### Usage

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

#### Local Formatter Resolution

The plugin checks for project-local tools first:

- `node_modules/.bin/oxfmt`
- `vendor/bin/ecs`
- `.venv/bin/ruff`
- `venv/bin/ruff`
- `.venv/bin/black`
- `venv/bin/black`

If none are found, it tries the matching global executable from `$PATH`.

### `configdel`

Deletes the YAML or JSON key at the current cursor position using `yq`.

Plugin files live under `plugins/configdel/`.

#### Features

- Adds the `del-key` command and `Alt-d` keybinding.
- Deletes the YAML or JSON key nearest to the cursor.
- YAML key detection uses `yq` line/column metadata for precision.
- JSON key detection falls back to line-scanning heuristics.
- Errors clearly when `yq` is not installed or the file type is unsupported.

#### Requirements

- `yq` (v4+) must be installed and available in your `$PATH`.
  Install from: https://github.com/mikefarah/yq/

#### Supported Filetypes

- YAML: `.yml`, `.yaml`
- JSON: `.json`

#### Usage

Place your cursor on or near the key you want to delete, then run:

```text
> del-key
```

Or use the default keybinding:

```text
Alt-d
```

#### Limitations (v0.1.0)

- Object keys only (array element deletion is not targeted).
- JSON key detection is best-effort (yq does not provide line metadata for JSON).

### `jsonschema`

Validates saved JSON files against the root `$schema` using Sourcemeta's
`jsonschema` CLI.

Plugin files live under `plugins/jsonschema/`.

#### Features

- Adds the `validate-schema` command.
- Validates `.json` files on save by default with `jsonschema.onsave`.
- Surfaces schema failures as Micro buffer diagnostics.
- Enables remote schema resolution by default with `jsonschema.http`.

#### Requirements

- Install the `jsonschema` CLI and make sure it is available in your `$PATH`.
- Supported install options include `mise use jsonschema`, Homebrew, npm,
  PyPI, or Sourcemeta release binaries.

#### Usage

Validate the current buffer:

```text
> validate-schema
```

Disable validation-on-save for the current buffer:

```text
> setlocal jsonschema.onsave false
```

Disable validation-on-save globally:

```text
> set jsonschema.onsave false
```

Disable remote HTTP schema resolution:

```text
> set jsonschema.http false
```

#### Notes

- Only `.json` files are supported in v0.1.0.
- Validation runs against the saved file on disk.
- Relative `$schema` paths resolve from the file's directory.

#### Manual Verification

Example files live under `testdata/jsonschema/`.

1. Install the Sourcemeta CLI, for example with `mise use jsonschema`.
2. Open `testdata/jsonschema/invalid-user.json` in Micro with the `jsonschema`
   plugin enabled.
3. Save the file.
4. Confirm that Micro surfaces schema diagnostics for:
   - `age` being below the minimum
   - `extra` being rejected by `additionalProperties`
5. Run `> validate-schema` to trigger the same validation manually.

### Installing a Plugin

Clone or copy the plugin directory into Micro's plugin directory:

```bash
git clone https://github.com/aaronflorey/micro-plugins.git /tmp/micro-plugins
cp -R /tmp/micro-plugins/plugins/format ~/.config/micro/plug/format
cp -R /tmp/micro-plugins/plugins/configdel ~/.config/micro/plug/configdel
cp -R /tmp/micro-plugins/plugins/jsonschema ~/.config/micro/plug/jsonschema
```

Restart Micro after installing.

#### Using `repo.json`

Add the raw file URL to your Micro config:

```json
{
  "pluginrepos": [
    "https://github.com/aaronflorey/micro-plugins/main/repo.json"
  ]
}
```

Then install a plugin:

```bash
micro -plugin install format
micro -plugin install configdel
micro -plugin install jsonschema
```

Or inside Micro:

```text
> plugin install format
> plugin install configdel
> plugin install jsonschema
```

## Adding More Plugins

- `repo.json` already supports multiple plugin entries.
- Each plugin should live in its own `plugins/<plugin-name>/` directory.
- Each published plugin should be packaged from that plugin directory, not from
  the monorepo root.

## Publishing Notes

Before publishing this plugin, update `repo.json` so each entry's `Website` points at the
actual repository URL.

## Development Hooks

This repository uses `lefthook` for commit-time automation.

```bash
mise install
lefthook install
```

On `commit-msg`, if staged files include `plugins/<name>/...` and the commit message uses
Conventional Commits, the hook bumps that plugin's version in both:

- `plugins/<name>/*.lua` (`VERSION = "x.y.z"`)
- `repo.json` (`Versions[0].Version`)

Bump rules:

- `feat:` -> minor
- `fix:` and all other conventional types -> patch
- `!` or `BREAKING CHANGE:` -> major
