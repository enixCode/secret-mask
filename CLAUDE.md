# secret-mask

Claude Code plugin that masks secret values from AI view using PreToolUse hooks.

## How it works

1. User defines protected files and key patterns in `.secretmask/config.json`
2. `init.ps1` scans those files and generates a value-to-placeholder mapping (`secrets.map`)
3. PreToolUse hook intercepts Read and Bash:
   - Read: redirects to a masked copy of the file
   - Bash: wraps command output through a sed filter
4. PostToolUse hook acts as backup - blocks output if secrets slip through

## Key principle

Real files are NEVER modified. Deployments, `npm run dev`, etc. always work.
Claude only sees `SECRET_KEYNAME` placeholders instead of real values.

## Setup in a project

1. Copy `example/config.example.json` to `<project>/.secretmask/config.json`
2. Edit config: add your files and key patterns
3. Run: `powershell -ExecutionPolicy Bypass -File scripts/init.ps1 -ProjectDir <project>`
4. Install the plugin in Claude Code

## Config format

Per file: a regex format and key patterns to filter which keys get masked.
Only keys matching `onlyKeys` patterns are masked. Others pass through in clear.
