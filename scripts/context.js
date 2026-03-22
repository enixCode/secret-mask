const { readInput, normalizePath, loadMappings, output } = require('./lib/secrets');

async function main() {
  const input = await readInput();
  const cwd = normalizePath(input.cwd || '');

  const result = loadMappings(cwd);

  if (!result) {
    output({
      hookSpecificOutput: {
        hookEventName: 'SessionStart',
        additionalContext: '[secret-mask] No config found. Create .secretmask/config.json to protect secrets. Example:\n{\n  ".env": [".*KEY.*", ".*SECRET.*", ".*TOKEN.*", ".*PASSWORD.*"]\n}'
      }
    });
    return;
  }

  if (result.mappings.length === 0) return;

  // Group placeholders by file
  const byFile = {};
  for (const { placeholder } of result.mappings) {
    // We can't easily track which file each mapping came from in loadMappings,
    // so re-scan to group by file
  }

  // Re-scan to build grouped output (same logic as loadMappings but grouped)
  const fs = require('fs');
  const path = require('path');
  const configPath = path.join(cwd, '.secretmask', 'config.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const files = Object.keys(config);

  const lines = [
    '[secret-mask] Active - secrets are masked in protected files.',
    '',
    'Rules:',
    '- Use SECRET_VALUE_* placeholders everywhere (code, configs, commands, file writes)',
    '- Never ask the user for real secret values - placeholders auto-replace on write/execute',
    '- Use Read (not Grep) on protected files - Grep is blocked, Read shows masked content',
    '',
    'Protected files and placeholders:'
  ];

  for (const fname of files) {
    const realFile = path.join(cwd, fname);
    if (!fs.existsSync(realFile)) continue;

    const patterns = (config[fname] || []).map((p) => new RegExp(p));
    const fileLines = fs.readFileSync(realFile, 'utf8').replace(/\r/g, '').split('\n');
    const placeholders = [];

    for (const line of fileLines) {
      if (/^\s*#/.test(line) || !line.trim()) continue;
      const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.+)$/);
      if (!match) continue;

      const key = match[1];
      let value = match[2];
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      if (!value) continue;

      const upperKey = key.toUpperCase();
      if (patterns.some((re) => re.test(upperKey))) {
        placeholders.push('  - SECRET_VALUE_' + upperKey);
      }
    }

    if (placeholders.length > 0) {
      lines.push(fname + ':');
      lines.push(...placeholders);
    }
  }

  output({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: lines.join('\n')
    }
  });
}

main();
