#!/bin/bash
# secret-mask - SessionStart hook
# Provides Claude with rules and available SECRET_VALUE_ placeholders

INPUT=$(cat)

# Extract CWD
CWD_RAW=$(echo "$INPUT" | node -e "
  let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    const j=JSON.parse(d);
    console.log(j.cwd||'');
  });
")
CWD=$(echo "$CWD_RAW" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')

CONFIG="$CWD/.secretmask/config.json"
[ ! -f "$CONFIG" ] && exit 0

# Build list of placeholders per file
FILES=$(node -e "
  Object.keys(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')))
    .forEach(k=>console.log(k));
" "$CONFIG")

LINES=()
LINES+=("[secret-mask] Active - secrets are masked in protected files.")
LINES+=("")
LINES+=("Rules:")
LINES+=("- Use SECRET_VALUE_* placeholders everywhere (code, configs, commands, file writes)")
LINES+=("- Never ask the user for real secret values - placeholders auto-replace on write/execute")
LINES+=("- Use Read (not Grep) on protected files - Grep is blocked, Read shows masked content")
LINES+=("")
LINES+=("Protected files and placeholders:")

HAS_PLACEHOLDERS=false

for FNAME in $FILES; do
  REAL_FILE="$CWD/$FNAME"
  [ ! -f "$REAL_FILE" ] && continue

  PATTERNS=$(node -e "
    const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    (c[process.argv[2]]||[]).forEach(p=>console.log(p));
  " "$CONFIG" "$FNAME")

  FILE_LINES=()

  while IFS= read -r LINE; do
    [[ "$LINE" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${LINE// /}" ]] && continue

    if [[ "$LINE" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
      KEY="${BASH_REMATCH[1]}"
      VALUE="${BASH_REMATCH[2]}"
      VALUE="${VALUE%\"}" && VALUE="${VALUE#\"}"
      VALUE="${VALUE%\'}" && VALUE="${VALUE#\'}"
      [ -z "$VALUE" ] && continue

      UPPER_KEY=$(echo "$KEY" | tr '[:lower:]' '[:upper:]')

      while IFS= read -r PAT; do
        [ -z "$PAT" ] && continue
        if [[ "$UPPER_KEY" =~ $PAT ]]; then
          FILE_LINES+=("  - SECRET_VALUE_${UPPER_KEY}")
          HAS_PLACEHOLDERS=true
          break
        fi
      done <<< "$PATTERNS"
    fi
  done < "$REAL_FILE"

  if [ ${#FILE_LINES[@]} -gt 0 ]; then
    LINES+=("$FNAME:")
    LINES+=("${FILE_LINES[@]}")
  fi
done

[ "$HAS_PLACEHOLDERS" = false ] && exit 0

# Join lines with real newlines
CONTEXT=$(printf '%s\n' "${LINES[@]}")

node -e "console.log(JSON.stringify({
  hookSpecificOutput:{hookEventName:'SessionStart',additionalContext:process.argv[1]}
}))" "$CONTEXT"
