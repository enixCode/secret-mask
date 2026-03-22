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
