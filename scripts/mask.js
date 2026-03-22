const fs = require('fs');
const path = require('path');
const { readInput, normalizePath, toWindowsPath, loadMappings, output } = require('./lib/secrets');

async function main() {
  const input = await readInput();
  const rawCwd = input.cwd || '';
  const tool = input.tool_name || '';

  const result = loadMappings(rawCwd);
  if (!result || result.mappings.length === 0) return;

  const { mappings, files } = result;

  if (tool === 'Read') handleRead(input, rawCwd, mappings, files);
  else if (tool === 'Grep') handleGrep(input, cwd, files);
  else if (tool === 'Write') handleWrite(input, mappings);
  else if (tool === 'Edit') handleEdit(input, mappings);
  else if (tool === 'Bash') handleBash(input, mappings);
}

function handleRead(input, cwd, mappings, files) {
  const filePath = (input.tool_input && input.tool_input.file_path) || '';
  if (!filePath) return;

  const bname = path.basename(filePath);
  if (!files.includes(bname)) return;

  const tmpDir = path.join(cwd, '.secretmask', 'tmp');
  fs.mkdirSync(tmpDir, { recursive: true });

  let content = fs.readFileSync(filePath, 'utf8');
  for (const { value, placeholder } of mappings) {
    content = content.split(value).join(placeholder);
  }

  const maskedPath = path.join(tmpDir, bname);
  fs.writeFileSync(maskedPath, content);

  output({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: { file_path: maskedPath }
    }
  });
}

function handleGrep(input, cwd, files) {
  const gpath = (input.tool_input && input.tool_input.path) || '';
  if (!gpath) return;

  const bname = path.basename(gpath);
  if (!files.includes(bname)) return;

  output({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: 'secret-mask: this file contains secrets. Use Read tool instead - it will show masked values.'
    }
  });
}

function handleWrite(input, mappings) {
  const content = (input.tool_input && input.tool_input.content) || '';
  if (!content.includes('SECRET_VALUE_')) return;

  let unmasked = content;
  for (const { value, placeholder } of mappings) {
    unmasked = unmasked.split(placeholder).join(value);
  }

  output({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: { content: unmasked }
    }
  });
}

function handleEdit(input, mappings) {
  let oldStr = (input.tool_input && input.tool_input.old_string) || '';
  let newStr = (input.tool_input && input.tool_input.new_string) || '';
  if (!oldStr.includes('SECRET_VALUE_') && !newStr.includes('SECRET_VALUE_')) return;

  const origOld = oldStr;
  const origNew = newStr;
  for (const { value, placeholder } of mappings) {
    oldStr = oldStr.split(placeholder).join(value);
    newStr = newStr.split(placeholder).join(value);
  }

  const upd = {};
  if (oldStr !== origOld) upd.old_string = oldStr;
  if (newStr !== origNew) upd.new_string = newStr;
  if (Object.keys(upd).length > 0) {
    output({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        updatedInput: upd
      }
    });
  }
}

function handleBash(input, mappings) {
  let cmd = (input.tool_input && input.tool_input.command) || '';
  if (!cmd) return;

  // Replace placeholders with real values in command
  for (const { value, placeholder } of mappings) {
    cmd = cmd.split(placeholder).join(value);
  }

  // Build inline sed expressions to mask secrets in output
  const sedArgs = mappings.map(({ value, placeholder }) =>
    `-e 's|${value.replace(/[|&/\\]/g, '\\$&')}|${placeholder}|g'`
  ).join(' ');

  const wrapped = `${cmd} 2>&1 | sed ${sedArgs}`;
  output({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: { command: wrapped }
    }
  });
}

main();
