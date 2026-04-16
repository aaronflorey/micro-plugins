# Format plugin

Adds a `format` command that formats the current buffer with a formatter that
matches the file type.

Auto-format on save is enabled by default for supported filetypes.

Supported mappings:

- `oxfmt`: JavaScript, TypeScript, JSX, TSX, JSON, YAML, TOML, HTML, CSS,
  SCSS, Less, Markdown, GraphQL, Vue, and related extensions.
- `ecs`: PHP.
- `gofmt`: Go.
- `ruff format`, then `black` fallback: Python.
- `stylua`: Lua.
- `shfmt`: shell scripts.
- `rustfmt`: Rust.

The plugin prefers project-local binaries when it finds them:

- `node_modules/.bin/oxfmt`
- `vendor/bin/ecs`
- `.venv/bin/ruff`, `venv/bin/ruff`
- `.venv/bin/black`, `venv/bin/black`

If there is no project-local formatter, it falls back to a matching executable
found on your global `$PATH`.

Usage:

```text
> format
```

Default keybinding:

```text
Alt-f
```

Disable auto-format for the current buffer:

```text
> setlocal format.onsave false
```

Disable auto-format globally:

```text
> set format.onsave false
```

The current buffer must already be saved to disk.
