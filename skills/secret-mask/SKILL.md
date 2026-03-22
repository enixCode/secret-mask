---
name: secret-mask
description: Instructions for working with masked secrets in protected files
---

# Secret Masking

This project uses secret-mask to protect sensitive values. When you read protected files, secret values appear as `SECRET_VALUE_<KEY>` placeholders (e.g., `SECRET_VALUE_API_KEY`).

## Rules

1. **Use placeholders everywhere** - in code, configs, commands, and file writes
2. **Never ask for real values** - placeholders are automatically replaced with real values when you write files or run commands
3. **Use Read, not Grep** - the Grep tool is blocked on protected files; use Read to see masked content
4. **Placeholders are bidirectional** - reading shows placeholders, writing/executing replaces them with real values

## Config setup

The config file is `.secretmask/config.json` in the target project root. Each key is a file path (relative to project root), each value defines which secrets to mask.

**Simple syntax** - for KEY=VALUE files (.env, .env.local, etc.):

```json
{
  ".env": [".*KEY.*", ".*SECRET.*", ".*TOKEN.*", ".*PASSWORD.*"]
}
```

Value is an array of regex patterns that match key names to mask. The default extractor parses `KEY=VALUE` lines.

**Advanced syntax** - for custom file formats (JSON, YAML, INI, .npmrc, etc.):

```json
{
  "credentials.json": {
    "patterns": [".*key.*", ".*secret.*"],
    "extractor": "^\\s*\"([^\"]+)\"\\s*:\\s*\"([^\"]+)\"\\s*,?\\s*$"
  }
}
```

- `patterns` - array of regex matching key names (same as simple)
- `extractor` - regex with exactly 2 capture groups: (1) key name, (2) value

Both syntaxes can be mixed in the same config.

## If masking is not working

- Verify `.secretmask/config.json` exists in the project root
- Check that file paths in config match actual file locations
- Check that regex patterns match the key names in your files
- For advanced syntax, verify the extractor regex has exactly 2 capture groups and matches the file format
