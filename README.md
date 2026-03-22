<h1 align="center">secret-mask</h1>

<p align="center">
  <strong>Keep secrets out of Claude Code's context.</strong><br/>
  Real files stay untouched - masking only happens in the hook layer.
</p>

<p align="center">
  <a href="hooks/hooks.json"><img src="https://img.shields.io/badge/Claude_Code-Plugin-cc785c?logo=anthropic&logoColor=white" alt="Claude Code Plugin"/></a>
  <a href="https://nodejs.org"><img src="https://img.shields.io/badge/Node.js-Runtime-339933?logo=nodedotjs&logoColor=white" alt="Node.js"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"/></a>
</p>

## How it works

```mermaid
flowchart LR
    subgraph Hooks
        A[SessionStart] -->|context.js| B[List placeholders]
        C[PreToolUse] -->|mask.js| D{Tool?}
    end

    D -->|Read| E[Copy file, replace secrets with SECRET_VALUE_*]
    D -->|Write/Edit| F[Replace SECRET_VALUE_* back to real values]
    D -->|Bash| G[Unmask command, mask output]
    D -->|Grep| H[Deny on protected files]
```

Claude sees `SECRET_VALUE_API_KEY` instead of `sk-live-abc123`. When it writes or executes, placeholders are swapped back silently.

## Install

```bash
claude plugin add enixCode/secret-mask
```

## Setup

1. In your target project, create `.secretmask/config.json`:

**Simple (KEY=VALUE files like .env):**
```json
{
  ".env": [".*KEY.*", ".*SECRET.*", ".*TOKEN.*", ".*PASSWORD.*"]
}
```

**Advanced (custom file formats - JSON, YAML, INI...):**
```json
{
  "credentials.json": {
    "patterns": [".*key.*", ".*secret.*"],
    "extractor": "^\\s*\"([^\"]+)\"\\s*:\\s*\"([^\"]+)\"\\s*,?\\s*$"
  }
}
```

- Simple: array of regex patterns matching key names. Default extractor: `KEY=VALUE`
- Advanced: object with `patterns` (same) + `extractor` (regex with 2 capture groups: key, value)
- Both syntaxes can be mixed. See `config.example.json` for more examples.

2. Start Claude Code in that project - the plugin activates automatically.

## Dependencies

- node

## License

MIT
