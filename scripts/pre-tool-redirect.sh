#!/bin/bash
# PreToolUse hook - masks secrets in Read and Bash outputs
# Finds .secretmask/ in the project CWD provided by Claude Code

INPUT=$(cat)

# Extract CWD from hook input (Claude Code provides it)
CWD=$(echo "$INPUT" | grep -oE '"cwd"\s*:\s*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"')
CWD=$(echo "$CWD" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')

MAPFILE="$CWD/.secretmask/secrets.map"
MASKED_DIR="$CWD/.secretmask/masked"
CONFIG="$CWD/.secretmask/config.json"
FILTER="$CWD/.secretmask/filter.sed"

[ ! -f "$MAPFILE" ] || [ ! -s "$MAPFILE" ] && exit 0

TOOL=$(echo "$INPUT" | grep -oE '"tool_name"\s*:\s*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"')

# --- READ: redirect to masked copy ---
if [ "$TOOL" = "Read" ]; then
  FPATH=$(echo "$INPUT" | grep -oE '"file_path"\s*:\s*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"')
  [ -z "$FPATH" ] && exit 0

  UPATH=$(echo "$FPATH" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')
  FNAME=$(basename "$UPATH")

  grep -q "\"$FNAME\"" "$CONFIG" 2>/dev/null || exit 0

  mkdir -p "$MASKED_DIR"
  MASKED_FILE="$MASKED_DIR/$FNAME"
  cp "$UPATH" "$MASKED_FILE"

  while IFS=$'\t' read -r SECRET PLACEHOLDER; do
    [ -z "$SECRET" ] && continue
    CONTENT=$(cat "$MASKED_FILE")
    echo "${CONTENT//$SECRET/$PLACEHOLDER}" > "$MASKED_FILE"
  done < "$MAPFILE"

  # Build forward-slash path for JSON
  REDIRECT="$MASKED_DIR/$FNAME"
  # Convert /c/ back to C:/ for Claude Code
  REDIRECT=$(echo "$REDIRECT" | sed 's|^/c/|C:/|')

  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"updatedInput\":{\"file_path\":\"$REDIRECT\"}}}"
  exit 0
fi

# --- BASH: wrap command output through sed filter ---
if [ "$TOOL" = "Bash" ]; then
  # Build sed filter file
  > "$FILTER"
  while IFS=$'\t' read -r SECRET PLACEHOLDER; do
    [ -z "$SECRET" ] && continue
    echo "s|${SECRET}|${PLACEHOLDER}|g" >> "$FILTER"
  done < "$MAPFILE"

  [ ! -s "$FILTER" ] && exit 0

  # Extract original command
  CMD=$(echo "$INPUT" | sed 's/.*"command"\s*:\s*"//' | sed 's/".*//')
  [ -z "$CMD" ] && exit 0

  # Convert filter path for bash
  BASH_FILTER=$(echo "$FILTER" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')

  WRAPPED="${CMD} 2>&1 | sed -f ${BASH_FILTER}"

  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"%s"}}}' "$WRAPPED"
  exit 0
fi

exit 0
