# JSON Schema plugin

Validates saved JSON files against the root `$schema` using the external
`jsonschema` CLI from Sourcemeta.

Auto-validation on save is enabled by default for `.json` files.

Features:

- Adds the `validate-schema` command.
- Validates the current file when a root `$schema` key is present.
- Surfaces validation failures as Micro buffer diagnostics.
- Enables remote schema resolution by default with `jsonschema.http`.

Requirements:

- Install the `jsonschema` CLI and make sure it is available on your `$PATH`.
- Supported install options include `mise use jsonschema`, Homebrew, npm,
  PyPI, or Sourcemeta release binaries.

Usage:

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

Notes:

- Only `.json` files are supported in this version.
- Validation runs against the saved file on disk.
- Relative `$schema` paths resolve from the file's directory.
