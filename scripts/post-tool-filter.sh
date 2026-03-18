#!/bin/bash
# PostToolUse hook - backup filter for secrets that slip through PreToolUse
# Blocks tool output if secrets are detected and provides masked version

INPUT=$(cat)

CWD=$(echo "$INPUT" | grep -oE '"cwd"\s*:\s*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"')
CWD=$(echo "$CWD" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')

MAPFILE="$CWD/.secretmask/secrets.map"

[ ! -f "$MAPFILE" ] || [ ! -s "$MAPFILE" ] && exit 0

# Stringify the full input to scan for secrets
FOUND=false
MASKED="$INPUT"

while IFS=$'\t' read -r SECRET PLACEHOLDER; do
  [ -z "$SECRET" ] && continue
  case "$MASKED" in
    *"$SECRET"*)
      FOUND=true
      MASKED="${MASKED//$SECRET/$PLACEHOLDER}"
      ;;
  esac
done < "$MAPFILE"

if [ "$FOUND" = true ]; then
  echo '{"decision":"block","reason":"Secret values detected and masked","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Output contained secret values - they were blocked."}}'
  exit 0
fi

exit 0
