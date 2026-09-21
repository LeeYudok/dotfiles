#!/bin/bash
# Claude Code statusLine script
# Reads JSON on stdin, prints one status line.

input=$(cat)

# --- palette (256-color, dim/muted for a quieter look) ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
SEP="${DIM} \xe2\x94\x82 ${RESET}"   # " │ "

FG_PATH=$'\033[38;5;110m'   # muted steel blue
FG_GIT_CLEAN=$'\033[38;5;108m'   # sage green
FG_GIT_DIRTY=$'\033[38;5;179m'   # muted amber
FG_MODEL=$'\033[38;5;73m'   # dusty teal
FG_OK=$'\033[38;5;108m'
FG_WARN=$'\033[38;5;179m'
FG_CRIT=$'\033[38;5;167m'   # muted red
FG_MUTE=$'\033[38;5;244m'   # gray

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
dir_name=$(basename "$cwd" 2>/dev/null)
[ -z "$dir_name" ] && dir_name="?"

model=$(echo "$input" | jq -r '.model.display_name // empty')

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
in_k=$(echo "$input" | jq -r '((.context_window.total_input_tokens // 0)/1000 | floor)')
win_k=$(echo "$input" | jq -r '((.context_window.context_window_size // 0)/1000 | floor)')

# --- path segment ---
path_part="${FG_PATH}${BOLD}${dir_name}${RESET}"

# --- git branch ---
git_part=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      git_part="${SEP}${FG_GIT_DIRTY}\xe2\x8e\x87 ${branch} \xe2\x97\x8f${RESET}"
    else
      git_part="${SEP}${FG_GIT_CLEAN}\xe2\x8e\x87 ${branch}${RESET}"
    fi
  fi
fi

# --- model segment ---
model_part=""
[ -n "$model" ] && model_part="${SEP}${FG_MODEL}${model}${RESET}"

# --- context usage: mini progress bar + colored percentage ---
ctx_part=""
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  [ "$used_int" -gt 100 ] && used_int=100

  if [ "$used_int" -ge 80 ]; then
    ctx_color="$FG_CRIT"
  elif [ "$used_int" -ge 60 ]; then
    ctx_color="$FG_WARN"
  else
    ctx_color="$FG_OK"
  fi

  bar_width=10
  filled=$(( used_int * bar_width / 100 ))
  empty=$(( bar_width - filled ))
  bar=""
  for ((i=0; i<filled; i++)); do bar="${bar}\xe2\x96\x88"; done
  for ((i=0; i<empty; i++)); do bar="${bar}\xe2\x96\x91"; done

  ctx_part="${SEP}${ctx_color}${bar} ${used_int}%${RESET} ${FG_MUTE}(${in_k}k/${win_k}k)${RESET}"
fi

# --- claude.ai rate limits (if present) ---
rate_part=""
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$five" ] || [ -n "$week" ]; then
  rl=""
  [ -n "$five" ] && rl="5h ${five%.*}%"
  if [ -n "$week" ]; then
    w="7d ${week%.*}%"
    [ -n "$rl" ] && rl="${rl}  ${w}" || rl="$w"
  fi
  rate_part="${SEP}${FG_MUTE}${rl}${RESET}"
fi

printf "%b%b%b%b%b\n" "$path_part" "$git_part" "$model_part" "$ctx_part" "$rate_part"
