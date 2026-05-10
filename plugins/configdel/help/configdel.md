# Config Delete Key plugin

Adds a `del-key` command that deletes the YAML or JSON key at the current cursor position.

## Requirements

- `yq` (v4+) must be installed and available in your `$PATH`
  - Install from: https://github.com/mikefarah/yq/

## Supported filetypes

- YAML: `.yml`, `.yaml`
- JSON: `.json`

## Usage

Place your cursor on or near the key you want to delete, then run:

```text
> del-key
```

Or use the default keybinding:

```text
Alt-d
```

The plugin will:
1. Detect the key at your cursor position using `yq` metadata
2. Delete that key from the file
3. Reload the buffer with the updated content

## Examples

**YAML** - Delete the `port` key:
```yaml
server:
  port: 8080    # <- cursor here
  host: localhost
```
After running `del-key` (or pressing Alt-d):
```yaml
server:
  host: localhost
```

**JSON** - Delete the `debug` key:
```json
{
  "debug": true,    # <- cursor here
  "verbose": false
}
```
After running `del-key` (or pressing Alt-d):
```json
{
  "verbose": false
}
```

## Limitations (v0.1.0)

- **Object keys only**: Array element deletion is not supported in this version. If your cursor is on a key inside an array item, the key will be deleted but the array item itself will remain.
- **Cursor proximity**: The plugin finds the nearest key to your cursor. If no key is detected on the same line, it checks lines within ±1 line distance.
- **File must be saved**: The buffer must be saved to disk before the command can run.
- **yq required**: This plugin depends entirely on `yq` for parsing and deletion.

## Error messages

- `yq is required but not installed`: Install yq from https://github.com/mikefarah/yq/
- `Unsupported filetype`: Only `.yml`, `.yaml`, and `.json` files are supported
- `Save the buffer before deleting a key`: The file must be saved to disk first
- `No key found at cursor position`: The plugin couldn't detect a key near your cursor
- `Failed to parse file`: yq encountered a syntax error in your file
- `Delete failed`: The deletion operation failed (see log for details)

## Notes

- For JSON files, `yq` does not provide line/column metadata, so key detection uses a best-effort approach based on file structure.
- The plugin preserves your file's formatting as much as possible, but `yq` may reformat the output according to its standard style.
