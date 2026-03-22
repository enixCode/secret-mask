# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Code plugin that masks secret values from AI view and restores them on write. Real files stay untouched - masking only happens in the hook layer.

## Architecture

The plugin uses node.js scripts triggered by Claude Code hooks (defined in `hooks/hooks.json`):

- **`scripts/mask.js`** - PreToolUse hook (matcher: `Read|Write|Edit|Bash|Grep`). Routes by tool name:
  - Read: copies protected file to `.secretmask/tmp/`, replaces real values with `SECRET_VALUE_<KEY>` placeholders, redirects Read to the masked copy
  - Write/Edit: detects `SECRET_VALUE_` in input, replaces placeholders back to real values in memory
  - Bash: replaces placeholders in commands with real values before execution, wraps output through inline sed to mask any leaked secrets
  - Grep: denies access to protected files (returns error telling Claude to use Read instead)
- **`scripts/context.js`** - SessionStart hook. Scans config and protected files, outputs available `SECRET_VALUE_*` placeholders so Claude knows what to use.
- **`scripts/lib/secrets.js`** - Shared module for config loading, secret mapping, and path normalization.

All secret values stay in memory - no secrets are ever written to disk. The only temp file is the masked copy for Read (contains only placeholders, no real values).

- **`skills/secret-mask/SKILL.md`** - Instructions injected into Claude's context about how to work with masked values.
- **`.claude-plugin/plugin.json`** - Plugin metadata (name, version, author).

## Config format

Target project's `.secretmask/config.json`:
```json
{
  ".env": [".*KEY.*", ".*SECRET.*", ".*TOKEN.*", ".*PASSWORD.*"],
  ".env.local": [".*TOKEN.*"]
}
```
Key = filename (relative to project root), Value = array of regex patterns matching env var names to mask.

## Dependencies

- node

## Testing changes

No automated tests. To test manually:
1. Create a test project with a `.secretmask/config.json` and a matching `.env` file
2. Install this plugin in Claude Code
3. Verify: Read shows placeholders, Write/Edit restores real values, Bash commands work with placeholders, Grep is denied on protected files
