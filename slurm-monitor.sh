#!/usr/bin/env bash
set -uo pipefail

USER_NAME="${USER_NAME:-${USER:-unknown}}"
LOG_DIR="${LOG_DIR:-}"
FALLBACK_OUT_LOG="${FALLBACK_OUT_LOG:-}"
FALLBACK_ERR_LOG="${FALLBACK_ERR_LOG:-}"
LOG_REFRESH="${LOG_REFRESH:-5}"
SLURM_REFRESH="${SLURM_REFRESH:-30}"
MODE="${MODE:-both}"                 # both | out | err | details | picker
QUEUE_VISIBLE_ROWS="${QUEUE_VISIBLE_ROWS:-4}"

# CLI:
#   ./slurm-monitor.sh [log_dir] [fallback_out] [fallback_err]
#
# Examples:
#   ./slurm-monitor.sh /work/ruhan625/logs
#   ./slurm-monitor.sh /work/ruhan625/logs /tmp/default.out /tmp/default.err
#   LOG_DIR=/work/ruhan625/logs ./slurm-monitor.sh

if (( $# >= 1 )); then
  if [[ -d "$1" ]]; then
    LOG_DIR="$1"
    shift
  fi
fi
if (( $# >= 1 )); then
  FALLBACK_OUT_LOG="$1"
  shift
fi
if (( $# >= 1 )); then
  FALLBACK_ERR_LOG="$1"
  shift
fi

PAUSED=0
ROWS=40
COLS=120
JOB_COUNT=0
SELECTED_INDEX=0
SELECTED_JOBID=""
QUEUE_ERROR=""
LAST_LOG_REFRESH="never"
LAST_SLURM_REFRESH="never"
LAST_SLURM_EPOCH=0
LAST_SELECTED_FOR_DETAILS=""
CURRENT_OUT_LOG=""
CURRENT_ERR_LOG=""
CURRENT_IN_LOG=""
CURRENT_WORKDIR=""
PRE_PICKER_MODE="both"

PICKER_INDEX=0
declare -a PICKER_FILES
declare -a DETAILS_LINES

declare -a JOB_IDS JOB_STATES JOB_TIMES JOB_NODES JOB_REASONS JOB_NAMES

declare -A STDOUT_MAP STDERR_MAP STDIN_MAP WORKDIR_MAP
declare -A USER_STDOUT_MAP USER_STDERR_MAP

timestamp_now() {
  date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf 'unknown'
}

epoch_now() {
  date +%s 2>/dev/null || printf '0'
}

setup_colors() {
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    BOLD="$(tput bold 2>/dev/null || true)"
    DIM="$(tput dim 2>/dev/null || true)"
    REV="$(tput rev 2>/dev/null || true)"
    RESET="$(tput sgr0 2>/dev/null || true)"
    RED="$(tput setaf 1 2>/dev/null || true)"
    GREEN="$(tput setaf 2 2>/dev/null || true)"
    YELLOW="$(tput setaf 3 2>/dev/null || true)"
    BLUE="$(tput setaf 4 2>/dev/null || true)"
    MAGENTA="$(tput setaf 5 2>/dev/null || true)"
    CYAN="$(tput setaf 6 2>/dev/null || true)"
  else
    BOLD=""; DIM=""; REV=""; RESET=""
    RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""
  fi
}

cleanup() {
  tput cnorm 2>/dev/null || true
  tput rmcup 2>/dev/null || true
  stty echo 2>/dev/null || true
}

init_ui() {
  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true
  stty -echo 2>/dev/null || true
}

trap cleanup EXIT INT TERM

term_size() {
  ROWS=$(tput lines 2>/dev/null || echo 40)
  COLS=$(tput cols 2>/dev/null || echo 120)
  (( ROWS < 20 )) && ROWS=20
  (( COLS < 80 )) && COLS=80
}

hr() {
  local width=$(( COLS > 1 ? COLS - 1 : 1 ))
  printf '%*s' "$width" '' | tr ' ' '-'
  tput el 2>/dev/null || true
  printf '\n'
}

blank_lines() {
  local n="$1" i
  for ((i = 0; i < n; i++)); do
    tput el 2>/dev/null || true
    printf '\n'
  done
}

fit() {
  local width="$1"
  shift
  local text="$*"

  (( width <= 0 )) && return 0

  if (( ${#text} > width )); then
    if (( width > 3 )); then
      printf "%s" "${text:0:$((width - 3))}..."
    else
      printf "%s" "${text:0:$width}"
    fi
  else
    printf "%-*s" "$width" "$text"
  fi
}

strip_ansi() {
  sed -E $'s/\x1B\\[[0-9;?]*[ -/]*[@-~]//g; s/\x1B[@-_]//g'
}

sanitize_line() {
  local line="$1"

  line="${line//$'\r'/}"
  line="$(printf '%s' "$line" | strip_ansi)"
  line="$(printf '%s' "$line" | tr -d '\000-\010\013\014\016-\037\177')"

  printf '%s' "$line"
}

print_row() {
  local text width
  width=$(( COLS > 1 ? COLS - 1 : 1 ))

  printf -v text "$@"
  text="$(sanitize_line "$text")"

  printf '%s' "${text:0:$width}"
  tput el 2>/dev/null || true
  printf '\n'
}

print_last_row() {
  local text width
  width=$(( COLS > 1 ? COLS - 1 : 1 ))

  printf -v text "$@"
  text="$(sanitize_line "$text")"

  printf '%s' "${text:0:$width}"
  tput el 2>/dev/null || true
}

print_row_ansi() {
  local text
  printf -v text "$@"
  printf '%s' "$text"
  tput el 2>/dev/null || true
  printf '\n'
}

print_prefix_row_ansi() {
  local prefix_ansi="$1"
  local prefix_plain="$2"
  shift 2

  local suffix width remaining
  width=$(( COLS > 1 ? COLS - 1 : 1 ))

  printf -v suffix "$@"
  suffix="$(sanitize_line "$suffix")"

  remaining=$(( width - ${#prefix_plain} ))
  (( remaining < 0 )) && remaining=0

  printf '%s%s%s' "$prefix_ansi" "$prefix_plain" "$RESET"
  printf '%s' "${suffix:0:$remaining}"
  tput el 2>/dev/null || true
  printf '\n'
}

print_buffer() {
  local -n arr_ref="$1"
  local max_lines="$2"
  local i line width

  width=$(( COLS > 1 ? COLS - 1 : 1 ))

  for ((i = 0; i < max_lines; i++)); do
    if (( i < ${#arr_ref[@]} )); then
      line="${arr_ref[i]}"
      line="${line//$'\t'/    }"
      line="$(sanitize_line "$line")"
      printf '%s' "${line:0:$width}"
      tput el 2>/dev/null || true
      printf '\n'
    else
      tput el 2>/dev/null || true
      printf '\n'
    fi
  done
}

min_value() {
  if (( $1 < $2 )); then
    echo "$1"
  else
    echo "$2"
  fi
}

extract_key_value() {
  local key="$1"
  awk -v k="$key" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ ("^" k "=")) {
          sub("^" k "=", "", $i)
          print $i
          exit
        }
      }
    }
  '
}

make_absolute_path() {
  local path="$1" workdir="$2"

  if [[ -z "$path" ]]; then
    return 0
  fi

  case "$path" in
    /*|/dev/*)
      printf '%s\n' "$path"
      ;;
    *)
      if [[ -n "$workdir" ]]; then
        printf '%s/%s\n' "$workdir" "$path"
      else
        printf '%s\n' "$path"
      fi
      ;;
  esac
}

color_state() {
  local state="$1"
  case "$state" in
    RUNNING|COMPLETING) printf "%s%s%s" "$GREEN" "$state" "$RESET" ;;
    PENDING|CONFIGURING) printf "%s%s%s" "$YELLOW" "$state" "$RESET" ;;
    COMPLETED) printf "%s%s%s" "$CYAN" "$state" "$RESET" ;;
    FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY) printf "%s%s%s" "$RED" "$state" "$RESET" ;;
    *) printf "%s" "$state" ;;
  esac
}

sync_selected_job() {
  if (( JOB_COUNT > 0 )); then
    SELECTED_JOBID="${JOB_IDS[SELECTED_INDEX]}"

    if [[ -n "${USER_STDOUT_MAP[$SELECTED_JOBID]:-}" ]]; then
      CURRENT_OUT_LOG="${USER_STDOUT_MAP[$SELECTED_JOBID]}"
    else
      CURRENT_OUT_LOG="${STDOUT_MAP[$SELECTED_JOBID]:-}"
    fi

    if [[ -n "${USER_STDERR_MAP[$SELECTED_JOBID]:-}" ]]; then
      CURRENT_ERR_LOG="${USER_STDERR_MAP[$SELECTED_JOBID]}"
    else
      CURRENT_ERR_LOG="${STDERR_MAP[$SELECTED_JOBID]:-}"
    fi

    CURRENT_IN_LOG="${STDIN_MAP[$SELECTED_JOBID]:-}"
    CURRENT_WORKDIR="${WORKDIR_MAP[$SELECTED_JOBID]:-}"
  else
    SELECTED_INDEX=0
    SELECTED_JOBID=""
    CURRENT_OUT_LOG=""
    CURRENT_ERR_LOG=""
    CURRENT_IN_LOG=""
    CURRENT_WORKDIR=""
  fi
}

resolve_selected_job_stdio() {
  local jobid="$1"
  local line="" sacct_line=""
  local stdout_path="" stderr_path="" stdin_path="" workdir_path=""

  [[ -z "$jobid" ]] && return 0

  if command -v scontrol >/dev/null 2>&1; then
    line="$(scontrol show job "$jobid" 2>/dev/null | tr '\n' ' ' || true)"
    if [[ -n "$line" ]]; then
      stdout_path="$(printf '%s\n' "$line" | extract_key_value 'StdOut')"
      stderr_path="$(printf '%s\n' "$line" | extract_key_value 'StdErr')"
      stdin_path="$(printf '%s\n' "$line" | extract_key_value 'StdIn')"
      workdir_path="$(printf '%s\n' "$line" | extract_key_value 'WorkDir')"
    fi
  fi

  if [[ -z "$stdout_path" || -z "$stderr_path" || -z "$stdin_path" || -z "$workdir_path" ]]; then
    if command -v sacct >/dev/null 2>&1; then
      sacct_line="$(
        { sacct -n -P -X -j "$jobid" --format=JobIDRaw,StdOut,StdErr,StdIn,WorkDir --expand-patterns 2>/dev/null || true; } \
        | awk -F'|' -v id="$jobid" '$1 == id { print; exit }'
      )"
      if [[ -n "$sacct_line" ]]; then
        IFS='|' read -r _ stdout_path stderr_path stdin_path workdir_path <<< "$sacct_line"
      fi
    fi
  fi

  stdout_path="$(make_absolute_path "$stdout_path" "$workdir_path")"
  stderr_path="$(make_absolute_path "$stderr_path" "$workdir_path")"
  stdin_path="$(make_absolute_path "$stdin_path" "$workdir_path")"

  if [[ -z "$stderr_path" && -n "$stdout_path" ]]; then
    stderr_path="$stdout_path"
  fi

  STDOUT_MAP[$jobid]="$stdout_path"
  STDERR_MAP[$jobid]="$stderr_path"
  STDIN_MAP[$jobid]="$stdin_path"
  WORKDIR_MAP[$jobid]="$workdir_path"

  if [[ "$jobid" == "$SELECTED_JOBID" ]]; then
    sync_selected_job
  fi
}

refresh_selected_details() {
  local jobid="$1"

  DETAILS_LINES=()
  LAST_SELECTED_FOR_DETAILS="$jobid"

  if [[ -z "$jobid" ]]; then
    DETAILS_LINES=("No job selected.")
    return 0
  fi

  if ! command -v scontrol >/dev/null 2>&1; then
    DETAILS_LINES=("scontrol not found in PATH.")
    return 0
  fi

  mapfile -t DETAILS_LINES < <(
    scontrol show job "$jobid" 2>/dev/null |
      sed 's/ \([A-Za-z][A-Za-z0-9_\/]\+=\)/\n\1/g'
  )

  if (( ${#DETAILS_LINES[@]} == 0 )); then
    DETAILS_LINES=("No details available for job $jobid.")
  fi
}

refresh_slurm_cache() {
  local wanted_jobid="${SELECTED_JOBID:-}"
  local found_index=-1
  local row id st tm nd rs nm
  local raw_rows=()

  JOB_IDS=()
  JOB_STATES=()
  JOB_TIMES=()
  JOB_NODES=()
  JOB_REASONS=()
  JOB_NAMES=()
  JOB_COUNT=0
  QUEUE_ERROR=""

  if ! command -v squeue >/dev/null 2>&1; then
    QUEUE_ERROR="squeue not found in PATH."
    LAST_SLURM_REFRESH="$(timestamp_now)"
    LAST_SLURM_EPOCH="$(epoch_now)"
    return
  fi

  mapfile -t raw_rows < <(squeue -h -u "$USER_NAME" -o "%i|%T|%M|%D|%R|%j" 2>/dev/null || true)

  for row in "${raw_rows[@]}"; do
    IFS='|' read -r id st tm nd rs nm <<< "$row"
    JOB_IDS+=("$id")
    JOB_STATES+=("$st")
    JOB_TIMES+=("$tm")
    JOB_NODES+=("$nd")
    JOB_REASONS+=("$rs")
    JOB_NAMES+=("$nm")
  done

  JOB_COUNT=${#JOB_IDS[@]}

  if (( JOB_COUNT == 0 )); then
    SELECTED_INDEX=0
    SELECTED_JOBID=""
    CURRENT_OUT_LOG=""
    CURRENT_ERR_LOG=""
    CURRENT_IN_LOG=""
    CURRENT_WORKDIR=""
    DETAILS_LINES=("No jobs found for $USER_NAME.")
    LAST_SLURM_REFRESH="$(timestamp_now)"
    LAST_SLURM_EPOCH="$(epoch_now)"
    return
  fi

  if [[ -n "$wanted_jobid" ]]; then
    local i
    for i in "${!JOB_IDS[@]}"; do
      if [[ "${JOB_IDS[i]}" == "$wanted_jobid" ]]; then
        found_index="$i"
        break
      fi
    done
  fi

  if (( found_index >= 0 )); then
    SELECTED_INDEX="$found_index"
  elif (( SELECTED_INDEX >= JOB_COUNT )); then
    SELECTED_INDEX=$((JOB_COUNT - 1))
  fi

  sync_selected_job
  resolve_selected_job_stdio "$SELECTED_JOBID"
  refresh_selected_details "$SELECTED_JOBID"

  LAST_SLURM_REFRESH="$(timestamp_now)"
  LAST_SLURM_EPOCH="$(epoch_now)"
}

list_dir_files_sorted() {
  [[ -n "$LOG_DIR" && -d "$LOG_DIR" ]] || return 0

  find "$LOG_DIR" -maxdepth 1 -type f -printf '%T@|%p\n' 2>/dev/null \
    | sort -t'|' -k1,1nr \
    | cut -d'|' -f2-
}

candidate_add() {
  local file="$1"
  local existing

  [[ -n "$file" ]] || return 0
  [[ -f "$file" ]] || return 0

  for existing in "${PICKER_FILES[@]}"; do
    [[ "$existing" == "$file" ]] && return 0
  done

  PICKER_FILES+=("$file")
}

collect_log_candidates() {
  local jobid="$1"
  local root_jobid=""
  local file base matched=0

  PICKER_FILES=()

  [[ -n "$jobid" ]] && root_jobid="${jobid%%_*}"

  candidate_add "${USER_STDOUT_MAP[$jobid]:-}"
  candidate_add "${USER_STDERR_MAP[$jobid]:-}"
  candidate_add "${STDOUT_MAP[$jobid]:-}"
  candidate_add "${STDERR_MAP[$jobid]:-}"

  [[ -n "$LOG_DIR" && -d "$LOG_DIR" ]] || return 0

  while IFS= read -r file; do
    base="$(basename "$file")"
    if [[ -n "$jobid" && "$base" == *"$jobid"* ]]; then
      candidate_add "$file"
      matched=1
    elif [[ -n "$root_jobid" && "$root_jobid" != "$jobid" && "$base" == *"$root_jobid"* ]]; then
      candidate_add "$file"
      matched=1
    fi
  done < <(list_dir_files_sorted)

  if (( matched == 0 )); then
    while IFS= read -r file; do
      candidate_add "$file"
    done < <(list_dir_files_sorted)
  fi

  if (( PICKER_INDEX >= ${#PICKER_FILES[@]} )); then
    PICKER_INDEX=0
  fi
}

auto_assign_logs_for_selected_job() {
  local f base lower chosen_out="" chosen_err=""

  [[ -n "$SELECTED_JOBID" ]] || return 0

  collect_log_candidates "$SELECTED_JOBID"

  for f in "${PICKER_FILES[@]}"; do
    base="$(basename "$f")"
    lower="${base,,}"

    if [[ -z "$chosen_out" && ( "$lower" == *".out"* || "$lower" == *"stdout"* ) ]]; then
      chosen_out="$f"
    fi

    if [[ -z "$chosen_err" && ( "$lower" == *".err"* || "$lower" == *"stderr"* ) ]]; then
      chosen_err="$f"
    fi
  done

  if [[ -z "$chosen_out" && ${#PICKER_FILES[@]} -eq 1 ]]; then
    chosen_out="${PICKER_FILES[0]}"
  fi

  if [[ -z "$chosen_err" && -n "$chosen_out" ]]; then
    chosen_err="$chosen_out"
  fi

  if [[ -n "$chosen_out" ]]; then
    USER_STDOUT_MAP[$SELECTED_JOBID]="$chosen_out"
  fi
  if [[ -n "$chosen_err" ]]; then
    USER_STDERR_MAP[$SELECTED_JOBID]="$chosen_err"
  fi

  sync_selected_job
}

clear_manual_assignments_for_selected() {
  [[ -n "$SELECTED_JOBID" ]] || return 0
  unset USER_STDOUT_MAP["$SELECTED_JOBID"]
  unset USER_STDERR_MAP["$SELECTED_JOBID"]
  sync_selected_job
}

enter_picker() {
  PRE_PICKER_MODE="$MODE"
  MODE="picker"
  PICKER_INDEX=0
  collect_log_candidates "$SELECTED_JOBID"
}

leave_picker() {
  if [[ "$PRE_PICKER_MODE" == "picker" || -z "$PRE_PICKER_MODE" ]]; then
    MODE="both"
  else
    MODE="$PRE_PICKER_MODE"
  fi
}

resolve_output_path() {
  local stream="$1"
  local path=""

  case "$stream" in
    out)
      if [[ -n "$SELECTED_JOBID" && -n "${USER_STDOUT_MAP[$SELECTED_JOBID]:-}" ]]; then
        path="${USER_STDOUT_MAP[$SELECTED_JOBID]}"
      elif [[ -n "$CURRENT_OUT_LOG" ]]; then
        path="$CURRENT_OUT_LOG"
      elif [[ -n "$FALLBACK_OUT_LOG" ]]; then
        path="$FALLBACK_OUT_LOG"
      fi
      ;;
    err)
      if [[ -n "$SELECTED_JOBID" && -n "${USER_STDERR_MAP[$SELECTED_JOBID]:-}" ]]; then
        path="${USER_STDERR_MAP[$SELECTED_JOBID]}"
      elif [[ -n "$CURRENT_ERR_LOG" ]]; then
        path="$CURRENT_ERR_LOG"
      elif [[ -n "$FALLBACK_ERR_LOG" ]]; then
        path="$FALLBACK_ERR_LOG"
      fi
      ;;
  esac

  printf '%s\n' "$path"
}

queue_total_lines() {
  local available="$1"
  local visible_jobs wanted max_allowed

  if (( JOB_COUNT > 0 )); then
    visible_jobs="$(min_value "$JOB_COUNT" "$QUEUE_VISIBLE_ROWS")"
  else
    visible_jobs=1
  fi

  wanted=$((2 + visible_jobs))
  max_allowed=$((available - 6))
  (( max_allowed < 3 )) && max_allowed=3

  min_value "$wanted" "$max_allowed"
}

draw_header() {
  local live_state
  local user_disp selected_disp mode_disp

  user_disp="$(fit 16 "$(sanitize_line "$USER_NAME")")"
  selected_disp="$(fit 16 "$(sanitize_line "${SELECTED_JOBID:-none}")")"
  mode_disp="$(fit 8 "$(sanitize_line "${MODE^^}")")"

  if (( PAUSED == 1 )); then
    live_state="${YELLOW}PAUSED${RESET}"
  else
    live_state="${GREEN}LIVE${RESET}"
  fi

  print_row_ansi "%sSlurm Monitor%s  user=%s  logs=%ss  slurm=%ss  mode=%s  selected=%s  status=%s" \
    "$BOLD$CYAN" "$RESET" \
    "$user_disp" "$LOG_REFRESH" "$SLURM_REFRESH" "$mode_disp" "$selected_disp" "$live_state"

  hr
}

draw_queue_panel() {
  local total_lines="$1"
  local body_lines=$(( total_lines - 2 ))
  local id_w=8 state_w=12 time_w=10 nds_w=4 reason_w=26
  local name_w=$(( COLS - 1 - 1 - id_w - 1 - state_w - 1 - time_w - 1 - nds_w - 1 - reason_w - 2 ))
  local start=0 max_start=0 visible idx
  local mark id state_plain state_colored time nodes reason name

  (( body_lines < 1 )) && body_lines=1
  (( name_w < 10 )) && name_w=10

  print_row_ansi "%sQueue%s  jobs=%s  visible=%s  last_slurm=%s" \
    "$BOLD$MAGENTA" "$RESET" "$JOB_COUNT" "$body_lines" "$LAST_SLURM_REFRESH"

  print_row "  %-8s %-12s %-10s %-4s %-26s %s" \
    "JOBID" "STATE" "TIME" "NDS" "NODE/REASON" "NAME"

  if [[ -n "$QUEUE_ERROR" ]]; then
    print_row "%s" "$QUEUE_ERROR"
    blank_lines $(( body_lines - 1 ))
    return
  fi

  if (( JOB_COUNT == 0 )); then
    print_row "No jobs found for %s." "$USER_NAME"
    blank_lines $(( body_lines - 1 ))
    return
  fi

  if (( JOB_COUNT > body_lines )); then
    start=$(( SELECTED_INDEX - body_lines / 2 ))
    (( start < 0 )) && start=0
    max_start=$(( JOB_COUNT - body_lines ))
    (( start > max_start )) && start="$max_start"
  fi

  for ((visible = 0; visible < body_lines; visible++)); do
    idx=$(( start + visible ))

    if (( idx >= JOB_COUNT )); then
      tput el 2>/dev/null || true
      printf '\n'
      continue
    fi

    id="$(fit "$id_w" "${JOB_IDS[idx]}")"
    state_plain="$(fit "$state_w" "${JOB_STATES[idx]}")"
    state_colored="$(color_state "$state_plain")"
    time="$(fit "$time_w" "${JOB_TIMES[idx]}")"
    nodes="$(fit "$nds_w" "${JOB_NODES[idx]}")"
    reason="$(fit "$reason_w" "${JOB_REASONS[idx]}")"
    name="$(fit "$name_w" "${JOB_NAMES[idx]}")"

    if (( idx == SELECTED_INDEX )); then
      mark=">"
      printf "%s%s %-8s %-12b %-10s %-4s %-26s %s%s" \
        "$REV" "$mark" "$id" "$state_colored" "$time" "$nodes" "$reason" "$name" "$RESET"
      tput el 2>/dev/null || true
      printf '\n'
    else
      mark=" "
      printf "%s %-8s %-12b %-10s %-4s %-26s %s" \
        "$mark" "$id" "$state_colored" "$time" "$nodes" "$reason" "$name"
      tput el 2>/dev/null || true
      printf '\n'
    fi
  done
}

draw_unresolved_message() {
  local stream="$1"
  local total_lines="$2"
  local buf=()
  local i max_preview

  collect_log_candidates "$SELECTED_JOBID"

  buf+=("Path unresolved for $stream.")
  if [[ -n "$LOG_DIR" ]]; then
    buf+=("Press l to open the picker. In picker: o=stdout, e=stderr, a=auto, c=clear.")
    buf+=("LOG_DIR: $LOG_DIR")
    buf+=("Candidates for selected job: ${#PICKER_FILES[@]}")
    max_preview=$(( total_lines - ${#buf[@]} ))
    (( max_preview > 3 )) && max_preview=3
    for ((i = 0; i < max_preview && i < ${#PICKER_FILES[@]}; i++)); do
      buf+=("  - $(basename "${PICKER_FILES[i]}")")
    done
  else
    buf+=("No LOG_DIR configured.")
    buf+=("Start like: ./slurm-monitor.sh /path/to/logs")
  fi

  print_buffer buf "$total_lines"
}

draw_file_block() {
  local title="$1" color="$2" file="$3" total_lines="$4"
  local content_lines=$(( total_lines - 2 ))
  local buf=()

  (( total_lines < 1 )) && return 0
  (( content_lines < 0 )) && content_lines=0

  print_prefix_row_ansi "$BOLD$color" "[${title}] " "%s" "${file:-unresolved}"
  print_row "%sSelected:%s %s" "$DIM" "$RESET" "${SELECTED_JOBID:-none}"

  if (( content_lines == 0 )); then
    return 0
  fi

  if [[ -z "$file" ]]; then
    draw_unresolved_message "$title" "$content_lines"
  elif [[ "$file" == "/dev/null" ]]; then
    buf=("The selected job is using /dev/null for this stream.")
    print_buffer buf "$content_lines"
  elif [[ -f "$file" ]]; then
    mapfile -t buf < <(tail -n "$content_lines" "$file" 2>/dev/null || true)
    print_buffer buf "$content_lines"
  else
    buf=("File not found: $file")
    if [[ -n "$LOG_DIR" ]]; then
      buf+=("Press l to browse LOG_DIR and assign another file.")
    fi
    print_buffer buf "$content_lines"
  fi
}

draw_details_block() {
  local total_lines="$1"
  local content_lines=$(( total_lines - 6 ))
  local shown_out shown_err shown_in shown_workdir

  (( total_lines < 1 )) && return 0
  (( content_lines < 0 )) && content_lines=0

  shown_out="$(resolve_output_path out)"
  shown_err="$(resolve_output_path err)"
  shown_in="${CURRENT_IN_LOG:-/dev/null}"
  shown_workdir="${CURRENT_WORKDIR:-unknown}"

  print_prefix_row_ansi "$BOLD$BLUE" "[DETAILS] " "selected job=%s" "${SELECTED_JOBID:-none}"
  print_row "StdOut : %s" "${shown_out:-unresolved}"
  print_row "StdErr : %s" "${shown_err:-unresolved}"
  print_row "StdIn  : %s" "${shown_in:-unresolved}"
  print_row "WorkDir: %s" "$shown_workdir"
  print_row "LOG_DIR: %s" "${LOG_DIR:-not set}"

  if (( content_lines == 0 )); then
    return 0
  fi

  if [[ "$LAST_SELECTED_FOR_DETAILS" != "$SELECTED_JOBID" ]]; then
    DETAILS_LINES=("Details for this job will update on the next Slurm poll." "Press Shift+R to force a Slurm refresh now.")
  fi

  print_buffer DETAILS_LINES "$content_lines"
}

draw_picker_block() {
  local total_lines="$1"
  local body_lines=$(( total_lines - 4 ))
  local start=0 max_start=0 idx visible path current_out current_err

  (( body_lines < 1 )) && body_lines=1
  collect_log_candidates "$SELECTED_JOBID"

  current_out="$(resolve_output_path out)"
  current_err="$(resolve_output_path err)"

  print_prefix_row_ansi "$BOLD$YELLOW" "[LOG PICKER] " "job=%s  dir=%s" "${SELECTED_JOBID:-none}" "${LOG_DIR:-not set}"
  print_row "stdout=%s" "${current_out:-unresolved}"
  print_row "stderr=%s" "${current_err:-unresolved}"
  print_row "Use Up/Down, o=stdout, e=stderr, a=auto, c=clear, Enter/Esc/l=close"

  if (( ${#PICKER_FILES[@]} == 0 )); then
    print_row "No candidates found."
    blank_lines $(( body_lines - 1 ))
    return
  fi

  if (( ${#PICKER_FILES[@]} > body_lines )); then
    start=$(( PICKER_INDEX - body_lines / 2 ))
    (( start < 0 )) && start=0
    max_start=$(( ${#PICKER_FILES[@]} - body_lines ))
    (( start > max_start )) && start="$max_start"
  fi

  for ((visible = 0; visible < body_lines; visible++)); do
    idx=$(( start + visible ))
    if (( idx >= ${#PICKER_FILES[@]} )); then
      tput el 2>/dev/null || true
      printf '\n'
      continue
    fi

    path="${PICKER_FILES[idx]}"
    if (( idx == PICKER_INDEX )); then
      print_row "> %s" "$path"
    else
      print_row "  %s" "$path"
    fi
  done
}

draw_bottom_panel() {
  local total_lines="$1"
  local out_file err_file out_block err_block

  out_file="$(resolve_output_path out)"
  err_file="$(resolve_output_path err)"

  case "$MODE" in
    both)
      (( total_lines < 4 )) && total_lines=4
      out_block=$(( total_lines / 2 ))
      err_block=$(( total_lines - out_block ))
      draw_file_block "STDOUT" "$GREEN" "$out_file" "$out_block"
      draw_file_block "STDERR" "$RED" "$err_file" "$err_block"
      ;;
    out)
      draw_file_block "STDOUT" "$GREEN" "$out_file" "$total_lines"
      ;;
    err)
      draw_file_block "STDERR" "$RED" "$err_file" "$total_lines"
      ;;
    details)
      draw_details_block "$total_lines"
      ;;
    picker)
      draw_picker_block "$total_lines"
      ;;
    *)
      draw_file_block "STDOUT" "$GREEN" "$out_file" "$total_lines"
      ;;
  esac
}

draw_footer() {
  hr

  if [[ "$MODE" == "picker" ]]; then
    print_row "Keys: Up/Down files | o stdout | e stderr | a auto | c clear | Enter/Esc/l close | R refresh | q quit"
  else
    print_row "Keys: Up/Down select | Enter details | Tab cycle | 1/2/3/4 views | l picker | p pause | r redraw | R refresh | +/- log | g/G top/bottom | q quit"
  fi

  print_last_row "Last log refresh: %s   Last Slurm refresh: %s" \
    "$LAST_LOG_REFRESH" "$LAST_SLURM_REFRESH"
}

render() {
  term_size
  printf '\033[H\033[2J'

  local usable_lines=$(( ROWS - 5 ))
  (( usable_lines < 8 )) && usable_lines=8

  local queue_lines
  queue_lines="$(queue_total_lines "$usable_lines")"

  local bottom_lines=$(( usable_lines - queue_lines ))
  (( bottom_lines < 5 )) && bottom_lines=5

  draw_header
  draw_queue_panel "$queue_lines"
  draw_bottom_panel "$bottom_lines"
  draw_footer
}

read_key() {
  local key rest

  IFS= read -rsn1 -t 0.1 key || return 1

  if [[ "$key" == $'\x1b' ]]; then
    while IFS= read -rsn1 -t 0.001 rest; do
      key+="$rest"
      [[ ${#key} -ge 6 ]] && break
    done
  fi

  printf '%s' "$key"
}

cycle_mode() {
  case "$MODE" in
    both) MODE="out" ;;
    out) MODE="err" ;;
    err) MODE="details" ;;
    details) MODE="both" ;;
    picker) MODE="$PRE_PICKER_MODE" ;;
    *) MODE="both" ;;
  esac
}

move_up_job() {
  if (( JOB_COUNT > 0 && SELECTED_INDEX > 0 )); then
    ((SELECTED_INDEX--))
    sync_selected_job
  fi
}

move_down_job() {
  if (( JOB_COUNT > 0 && SELECTED_INDEX < JOB_COUNT - 1 )); then
    ((SELECTED_INDEX++))
    sync_selected_job
  fi
}

move_up_picker() {
  if (( PICKER_INDEX > 0 )); then
    ((PICKER_INDEX--))
  fi
}

move_down_picker() {
  if (( PICKER_INDEX + 1 < ${#PICKER_FILES[@]} )); then
    ((PICKER_INDEX++))
  fi
}

assign_picker_to_stdout() {
  [[ -n "$SELECTED_JOBID" ]] || return 0
  [[ ${#PICKER_FILES[@]} -gt 0 ]] || return 0
  USER_STDOUT_MAP[$SELECTED_JOBID]="${PICKER_FILES[$PICKER_INDEX]}"
  sync_selected_job
}

assign_picker_to_stderr() {
  [[ -n "$SELECTED_JOBID" ]] || return 0
  [[ ${#PICKER_FILES[@]} -gt 0 ]] || return 0
  USER_STDERR_MAP[$SELECTED_JOBID]="${PICKER_FILES[$PICKER_INDEX]}"
  sync_selected_job
}

handle_key_picker() {
  local key="$1"

  case "$key" in
    q) exit 0 ;;
    p|P) PAUSED=$((1 - PAUSED)) ;;
    r) render ;;
    R) refresh_slurm_cache; collect_log_candidates "$SELECTED_JOBID"; render ;;
    l|$'\n'|$'\r'|$'\x1b') leave_picker ;;
    o) assign_picker_to_stdout ;;
    e) assign_picker_to_stderr ;;
    a) auto_assign_logs_for_selected_job ;;
    c) clear_manual_assignments_for_selected ;;
    j|$'\x1b[B') move_down_picker ;;
    k|$'\x1b[A') move_up_picker ;;
  esac
}

handle_key_main() {
  local key="$1"

  case "$key" in
    q) exit 0 ;;
    p|P) PAUSED=$((1 - PAUSED)) ;;
    r) render ;;
    R) refresh_slurm_cache; render ;;
    1) MODE="both" ;;
    2) MODE="out" ;;
    3) MODE="err" ;;
    4) MODE="details" ;;
    $'\t') cycle_mode ;;
    l) enter_picker ;;
    $'\n'|$'\r') MODE="details" ;;
    '+')
      if (( LOG_REFRESH > 1 )); then
        ((LOG_REFRESH--))
      fi
      ;;
    '-')
      if (( LOG_REFRESH < 60 )); then
        ((LOG_REFRESH++))
      fi
      ;;
    g)
      if (( JOB_COUNT > 0 )); then
        SELECTED_INDEX=0
        sync_selected_job
      fi
      ;;
    G)
      if (( JOB_COUNT > 0 )); then
        SELECTED_INDEX=$((JOB_COUNT - 1))
        sync_selected_job
      fi
      ;;
    j|$'\x1b[B') move_down_job ;;
    k|$'\x1b[A') move_up_job ;;
  esac
}

maybe_refresh_slurm() {
  local now
  now="$(epoch_now)"
  if (( now - LAST_SLURM_EPOCH >= SLURM_REFRESH )); then
    refresh_slurm_cache
  fi
}

main_loop() {
  local last_log_epoch now key

  init_ui
  refresh_slurm_cache
  LAST_LOG_REFRESH="$(timestamp_now)"
  last_log_epoch="$(epoch_now)"
  render

  while true; do
    now="$(epoch_now)"
    maybe_refresh_slurm

    if (( PAUSED == 0 )) && (( now - last_log_epoch >= LOG_REFRESH )); then
      LAST_LOG_REFRESH="$(timestamp_now)"
      render
      last_log_epoch="$now"
    fi

    key=""
    if key="$(read_key)"; then
      if [[ "$MODE" == "picker" ]]; then
        handle_key_picker "$key"
      else
        handle_key_main "$key"
      fi
      render
    fi
  done
}

setup_colors
main_loop
