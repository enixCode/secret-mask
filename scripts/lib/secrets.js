const fs = require('fs');
const path = require('path');

function readInput() {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.on('data', (chunk) => data += chunk);
    process.stdin.on('end', () => resolve(JSON.parse(data)));
  });
}

function normalizePath(p) {
  return p.replace(/\\\\/g, '/').replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, d) => '/' + d.toLowerCase());
}

function toWindowsPath(p) {
  return p.replace(/^\/([a-z])\//, (_, d) => d.toUpperCase() + ':/');
}

const DEFAULT_EXTRACTOR = /^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$/;

function parseFileEntry(entry) {
  if (Array.isArray(entry)) {
    return { patterns: entry.map((p) => new RegExp(p, 'i')), extractor: DEFAULT_EXTRACTOR };
  }
  const patterns = (entry.patterns || []).map((p) => new RegExp(p, 'i'));
  const extractor = entry.extractor ? new RegExp(entry.extractor) : DEFAULT_EXTRACTOR;
  return { patterns, extractor };
}

function loadMappings(cwd) {
  const configPath = path.join(cwd, '.secretmask', 'config.json');
  if (!fs.existsSync(configPath)) return null;

  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const files = Object.keys(config);
  const mappings = [];

  for (const fname of files) {
    const realFile = path.join(cwd, fname);
    if (!fs.existsSync(realFile)) continue;

    const { patterns, extractor } = parseFileEntry(config[fname]);
    const lines = fs.readFileSync(realFile, 'utf8').replace(/\r/g, '').split('\n');

    for (const line of lines) {
      if (/^\s*#/.test(line) || !line.trim()) continue;
      const match = line.match(extractor);
      if (!match) continue;

      const key = match[1];
      let value = match[2];
      // Strip surrounding quotes
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      if (!value) continue;

      const upperKey = key.toUpperCase();
      if (patterns.some((re) => re.test(upperKey))) {
        mappings.push({ value, placeholder: 'SECRET_VALUE_' + upperKey });
      }
    }
  }

  return { mappings, files };
}

function output(obj) {
  console.log(JSON.stringify(obj));
}

module.exports = { readInput, normalizePath, toWindowsPath, parseFileEntry, loadMappings, output };
