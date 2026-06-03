# micro-plugins

[![License](https://img.shields.io/github/license/aaronflorey/micro-plugins?style=flat-square)](LICENSE)

A collection of [Micro editor](https://github.com/zyedidia/micro) plugins: `format` for code formatting, `configdel` for deleting YAML/JSON keys, and `jsonschema` for JSON Schema validation.

## Installation

Add the channel to your Micro settings (`~/.config/micro/settings.json`):

```json
{
  "pluginchannels": [
    "https://raw.githubusercontent.com/aaronflorey/micro-plugins/main/channel.json"
  ]
}
```

Then install plugins from within Micro:

```
> plugin install format
> plugin install configdel
> plugin install jsonschema
```

Or from the command line:

```sh
micro -plugin install format
micro -plugin install configdel
micro -plugin install jsonschema
```

## Plugins

### format

Formats the current buffer using a formatter matched to the file type. Prefers project-local binaries, falls back to `$PATH`.

**Formatters by file type:**

| Language                        | Formatter                 |
| ------------------------------- | ------------------------- |
| JavaScript, TypeScript, JSX, TSX, JSON, YAML, TOML, HTML, CSS, SCSS, Less, Markdown, MDX, GraphQL, Vue, Handlebars | `oxfmt` |
| PHP    | `ecs`                     |
| Go                              | `gofmt`                   |
| Python                          | `ruff format` then `black` |
| Lua                             | `stylua`                  |
| Shell                           | `shfmt`                   |
| Rust                            | `rustfmt`                 |

The buffer must be saved to disk first. Format-on-save is enabled by default; disable it:

```
> set format.onsave false
> setlocal format.onsave false
```

### configdel

Deletes the YAML or JSON key at the cursor position. Requires [`yq`](https://github.com/mikefarah/yq/) v4+.

**Supported filetypes:** `.yml`, `.yaml`, `.json`

Place the cursor on or near a key and press `Alt-d`, or run:

```
> del-key
```

### jsonschema

Validates `.json` files against their `$schema` using the Sourcemeta [`jsonschema`](https://github.com/sourcemeta/jsonschema) CLI. Failures appear as buffer diagnostics.

Install the CLI:

```sh
mise use jsonschema
```

Validation runs on save by default. Disable it:

```
> set jsonschema.onsave false
> setlocal jsonschema.onsave false
```

Disable remote `$schema` resolution:

```
> set jsonschema.http false
```

## Development

This repo uses `lefthook` for pre-commit automation and `mise` for tooling.

```sh
mise install
lefthook install
```

On commit, if staged files include changes to a plugin directory and the commit message uses Conventional Commits, the hook bumps that plugin's patch version.

## License

[MIT](LICENSE)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). By participating, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

See [SECURITY.md](SECURITY.md).
