#!/bin/bash
# secret-mask - PreToolUse hook for ALL tools
# Masks secrets on read/output, unmasks placeholders on write/execute

INPUT=$(cat)

# Extract CWD and tool name (one node call)
PARSED=$(echo "$INPUT" | node -e "
  let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    const j=JSON.parse(d);
    console.log(j.cwd||'');
    console.log(j.tool_name||'');
  });
")
CWD_RAW=$(echo "$PARSED" | head -1)
TOOL=$(echo "$PARSED" | tail -1)

CWD=$(echo "$CWD_RAW" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')

CONFIG="$CWD/.secretmask/config.json"
[ ! -f "$CONFIG" ] && exit 0

# --- Build replacements in memory ---
declare -a SECRETS=()
declare -a PLACEHOLDERS=()

FILES=$(node -e "
  Object.keys(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')))
    .forEach(k=>console.log(k));
" "$CONFIG")

for FNAME in $FILES; do
  REAL_FILE="$CWD/$FNAME"
  [ ! -f "$REAL_FILE" ] && continue

  PATTERNS=$(node -e "
    const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    (c[process.argv[2]]||[]).forEach(p=>console.log(p));
  " "$CONFIG" "$FNAME")

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
          SECRETS+=("$VALUE")
          PLACEHOLDERS+=("SECRET_VALUE_${UPPER_KEY}")
          break
        fi
      done <<< "$PATTERNS"
    fi
  done < "$REAL_FILE"
done

COUNT=${#SECRETS[@]}
[ $COUNT -eq 0 ] && exit 0

# --- Prepare tmp dir and reverse map for Write/Edit ---
TMPDIR="$CWD/.secretmask/tmp"
mkdir -p "$TMPDIR"

MAPFILE="$TMPDIR/reverse.tsv"
> "$MAPFILE"
for ((i=0; i<COUNT; i++)); do
  printf '%s\t%s\n' "${PLACEHOLDERS[$i]}" "${SECRETS[$i]}" >> "$MAPFILE"
done

# --- READ: create masked copy, redirect ---
if [ "$TOOL" = "Read" ]; then
  FPATH=$(echo "$INPUT" | node -e "
    let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
      const j=JSON.parse(d);
      console.log((j.tool_input&&j.tool_input.file_path)||'');
    });
  ")
  [ -z "$FPATH" ] && exit 0
  UPATH=$(echo "$FPATH" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')
  BNAME=$(basename "$UPATH")

  echo "$FILES" | grep -qF "$BNAME" || exit 0

  MASKED="$TMPDIR/$BNAME"
  cp "$UPATH" "$MASKED"

  for ((i=0; i<COUNT; i++)); do
    CONTENT=$(cat "$MASKED")
    echo "${CONTENT//${SECRETS[$i]}/${PLACEHOLDERS[$i]}}" > "$MASKED"
  done

  REDIRECT=$(echo "$TMPDIR/$BNAME" | sed 's|^/c/|C:/|')
  node -e "console.log(JSON.stringify({
    hookSpecificOutput:{hookEventName:'PreToolUse',updatedInput:{file_path:process.argv[1]}}
  }))" "$REDIRECT"
  exit 0
fi

# --- GREP: deny on protected files ---
if [ "$TOOL" = "Grep" ]; then
  GPATH=$(echo "$INPUT" | node -e "
    let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
      const j=JSON.parse(d);
      console.log((j.tool_input&&j.tool_input.path)||'');
    });
  ")
  [ -z "$GPATH" ] && exit 0
  UPATH=$(echo "$GPATH" | sed 's|\\\\|/|g' | sed 's|\\|/|g' | sed 's|^C:|/c|')
  BNAME=$(basename "$UPATH")

  echo "$FILES" | grep -qF "$BNAME" || exit 0

  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"secret-mask: this file contains secrets. Use Read tool instead - it will show masked values."}}'
  exit 0
fi

# --- WRITE: unmask placeholders in content ---
if [ "$TOOL" = "Write" ]; then
  echo "$INPUT" | grep -q "SECRET_VALUE_" || exit 0

  RESULT=$(echo "$INPUT" | node -e "
    const fs=require('fs');
    let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
      try{
        const input=JSON.parse(d);
        let content=input.tool_input.content;
        fs.readFileSync(process.argv[1],'utf8').trim().split('\n').forEach(l=>{
          const i=l.indexOf('\t');
          if(i>0)content=content.split(l.slice(0,i)).join(l.slice(i+1));
        });
        console.log(JSON.stringify({hookSpecificOutput:{hookEventName:'PreToolUse',updatedInput:{content}}}));
      }catch(e){}
    });
  " "$MAPFILE" 2>/dev/null)

  [ -n "$RESULT" ] && echo "$RESULT"
  exit 0
fi

# --- EDIT: unmask placeholders in old_string and new_string ---
if [ "$TOOL" = "Edit" ]; then
  echo "$INPUT" | grep -q "SECRET_VALUE_" || exit 0

  RESULT=$(echo "$INPUT" | node -e "
    const fs=require('fs');
    let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
      try{
        const input=JSON.parse(d);
        let oldStr=input.tool_input.old_string;
        let newStr=input.tool_input.new_string;
        const lines=fs.readFileSync(process.argv[1],'utf8').trim().split('\n');
        lines.forEach(l=>{
          const i=l.indexOf('\t');
          if(i>0){
            const p=l.slice(0,i),s=l.slice(i+1);
            oldStr=oldStr.split(p).join(s);
            newStr=newStr.split(p).join(s);
          }
        });
        const upd={};
        if(oldStr!==input.tool_input.old_string)upd.old_string=oldStr;
        if(newStr!==input.tool_input.new_string)upd.new_string=newStr;
        if(Object.keys(upd).length>0)
          console.log(JSON.stringify({hookSpecificOutput:{hookEventName:'PreToolUse',updatedInput:upd}}));
      }catch(e){}
    });
  " "$MAPFILE" 2>/dev/null)

  [ -n "$RESULT" ] && echo "$RESULT"
  exit 0
fi

# --- BASH: unmask placeholders in command + mask output ---
if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | node -e "
    let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
      const j=JSON.parse(d);
      console.log((j.tool_input&&j.tool_input.command)||'');
    });
  ")
  [ -z "$CMD" ] && exit 0

  # Replace placeholders in command with real values
  for ((i=0; i<COUNT; i++)); do
    CMD="${CMD//${PLACEHOLDERS[$i]}/${SECRETS[$i]}}"
  done

  # Build sed filter for output masking
  FILTERFILE="$TMPDIR/filter.sed"
  > "$FILTERFILE"
  for ((i=0; i<COUNT; i++)); do
    echo "s|${SECRETS[$i]}|${PLACEHOLDERS[$i]}|g" >> "$FILTERFILE"
  done

  BFILTER=$(echo "$FILTERFILE" | sed 's|^C:|/c|')
  WRAPPED="${CMD} 2>&1 | sed -f ${BFILTER}"
  node -e "console.log(JSON.stringify({
    hookSpecificOutput:{hookEventName:'PreToolUse',updatedInput:{command:process.argv[1]}}
  }))" "$WRAPPED"
  exit 0
fi

exit 0
