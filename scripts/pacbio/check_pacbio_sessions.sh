#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

LOGS_DIR="${PROJECT_DIR}/logs"
STATUS_FILE="${LOGS_DIR}/run_pacbio.status"

SHOW_ALL="${SHOW_ALL:-false}"

format_duration() {
    local total="${1:-}"

    if ! [[ "${total}" =~ ^[0-9]+$ ]]; then
        echo "NA"
        return 0
    fi

    local days hours mins secs
    days=$(( total / 86400 ))
    hours=$(( (total % 86400) / 3600 ))
    mins=$(( (total % 3600) / 60 ))
    secs=$(( total % 60 ))

    printf "%02d:%02d:%02d:%02d\n" "${days}" "${hours}" "${mins}" "${secs}"
}

get_elapsed_from_start_epoch() {
    local start_epoch="${1:-}"

    if ! [[ "${start_epoch}" =~ ^[0-9]+$ ]]; then
        echo "NA"
        return 0
    fi

    local now elapsed
    now="$(date +%s)"
    elapsed=$(( now - start_epoch ))

    if [ "${elapsed}" -lt 0 ]; then
        echo "NA"
        return 0
    fi

    format_duration "${elapsed}"
}

get_cpu_total() {
    nproc 2>/dev/null || echo "NA"
}

get_cpu_used_and_total() {
    local total_cpus
    total_cpus="$(get_cpu_total)"

    if ! [[ "${total_cpus}" =~ ^[0-9]+$ ]]; then
        echo "NA/NA"
        return 0
    fi

    read -r _ u1 n1 s1 i1 w1 irq1 sirq1 st1 _ < /proc/stat
    local idle1 total1
    idle1=$((i1 + w1))
    total1=$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1 + st1))

    sleep 0.2

    read -r _ u2 n2 s2 i2 w2 irq2 sirq2 st2 _ < /proc/stat
    local idle2 total2
    idle2=$((i2 + w2))
    total2=$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2 + st2))

    local totald idled used_percent used_cpus
    totald=$((total2 - total1))
    idled=$((idle2 - idle1))

    if [ "${totald}" -le 0 ]; then
        echo "NA/${total_cpus}"
        return 0
    fi

    used_percent=$(( (100 * (totald - idled)) / totald ))
    used_cpus=$(( (used_percent * total_cpus + 50) / 100 ))

    echo "${used_cpus}/${total_cpus}"
}

normalize_stdout_stream() {
    local stdout_log="$1"

    if [ ! -f "${stdout_log}" ]; then
        return 0
    fi

    perl -pe '
        s/\r/\n/g;
        s/\e\[[0-9;?]*[ -\/]*[@-~]//g;
    ' "${stdout_log}" \
    | sed 's/[[:space:]]\+$//' \
    | sed '/^[[:space:]]*$/d'
}

show_tail_lines() {
    local file="$1"
    local n="${2:-8}"
    local title="$3"

    echo
    echo "${title}"
    if [ -f "${file}" ]; then
        normalize_stdout_stream "${file}" | tail -n "${n}" || true
    else
        echo "[INFO] 找不到檔案：${file}"
    fi
}

read_status_value() {
    local key="$1"
    grep "^${key}=" "${STATUS_FILE}" 2>/dev/null | head -n 1 | cut -d'=' -f2- || true
}

extract_latest_executor_block() {
    local stdout_log="$1"

    normalize_stdout_stream "${stdout_log}" | awk '
    /^executor >[[:space:]]+Local/ {
        if (block != "") last_block = block
        block = $0 "\n"
        in_block = 1
        next
    }

    in_block {
        if (/^executor >[[:space:]]+Local/) {
            last_block = block
            block = $0 "\n"
            next
        }

        if (/pb16S:|Plus [0-9]+ more processes waiting for tasks/) {
            block = block $0 "\n"
        }
    }

    END {
        if (block != "") last_block = block
        printf "%s", last_block
    }' || true
}

extract_executor_line() {
    local block="$1"
    if [ -z "${block}" ]; then
        return 0
    fi
    printf '%s\n' "${block}" | grep '^executor >' | tail -n 1 | sed 's/^[[:space:]]*//' || true
}

extract_current_task_from_block() {
    local block="$1"
    if [ -z "${block}" ]; then
        return 0
    fi

    printf '%s\n' "${block}" \
      | grep 'pb16S:' \
      | grep -v '✔' \
      | grep -v '^\[-[[:space:]]*\]' \
      | head -n 1 \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
}

extract_pending_tasks_from_block() {
    local block="$1"
    if [ -z "${block}" ]; then
        return 0
    fi

    {
        printf '%s\n' "${block}" \
          | grep 'pb16S:' \
          | grep -v '✔' \
          | grep '^\[-[[:space:]]*\]' || true
        printf '%s\n' "${block}" \
          | grep 'Plus [0-9]\+ more processes waiting for tasks' || true
    } | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
}

extract_last_finished_task_from_block() {
    local block="$1"
    if [ -z "${block}" ]; then
        return 0
    fi

    printf '%s\n' "${block}" \
      | grep 'pb16S:' \
      | grep '✔' \
      | tail -n 1 \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
}

extract_completed_steps_from_block() {
    local block="$1"
    if [ -z "${block}" ]; then
        return 0
    fi

    printf '%s\n' "${block}" \
      | grep 'pb16S:' \
      | grep '✔' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
}

normalize_trace_step_name() {
    local name="$1"
    name="$(printf '%s' "${name}" | sed -E 's/[[:space:]]+\([0-9]+\)$//')"
    printf '%s\n' "${name}"
}

parse_duration_to_seconds() {
    local raw="$1"
    raw="$(printf '%s' "${raw}" | tr -d '[:space:]')"

    if [ -z "${raw}" ]; then
        echo ""
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+(\.[0-9]+)?)ms$ ]]; then
        echo "0"
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+(\.[0-9]+)?)s$ ]]; then
        awk -v v="${BASH_REMATCH[1]}" 'BEGIN{printf "%.0f\n", v}'
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+(\.[0-9]+)?)m$ ]]; then
        awk -v v="${BASH_REMATCH[1]}" 'BEGIN{printf "%.0f\n", v*60}'
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+(\.[0-9]+)?)h$ ]]; then
        awk -v v="${BASH_REMATCH[1]}" 'BEGIN{printf "%.0f\n", v*3600}'
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+)ms([0-9]+)s$ ]]; then
        echo "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+)m([0-9]+)s$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+)h([0-9]+)m([0-9]+)s$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 3600 + ${BASH_REMATCH[2]} * 60 + ${BASH_REMATCH[3]} ))
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+)h([0-9]+)m$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 3600 + ${BASH_REMATCH[2]} * 60 ))
        return 0
    fi

    if [[ "${raw}" =~ ^([0-9]+)m([0-9]+)ms$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 60 ))
        return 0
    fi

    echo ""
}

build_trace_duration_map() {
    local trace_file="$1"

    if [ ! -f "${trace_file}" ]; then
        return 0
    fi

    python3 - "$trace_file" <<'PY'
import csv
import re
import sys

trace_file = sys.argv[1]

def normalize_name(name: str) -> str:
    return re.sub(r'\s+\(\d+\)$', '', name.strip())

def parse_duration(raw: str):
    if not raw:
        return None
    raw = raw.strip().replace(" ", "")
    if not raw:
        return None

    patterns = [
        (r'^(\d+(?:\.\d+)?)ms$', lambda m: 0),
        (r'^(\d+(?:\.\d+)?)s$', lambda m: round(float(m.group(1)))),
        (r'^(\d+(?:\.\d+)?)m$', lambda m: round(float(m.group(1)) * 60)),
        (r'^(\d+(?:\.\d+)?)h$', lambda m: round(float(m.group(1)) * 3600)),
        (r'^(\d+)m(\d+)s$', lambda m: int(m.group(1)) * 60 + int(m.group(2))),
        (r'^(\d+)h(\d+)m(\d+)s$', lambda m: int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))),
        (r'^(\d+)h(\d+)m$', lambda m: int(m.group(1)) * 3600 + int(m.group(2)) * 60),
        (r'^(\d+)m(\d+)ms$', lambda m: int(m.group(1)) * 60),
        (r'^(\d+)ms(\d+)s$', lambda m: int(m.group(2))),
    ]

    for pat, fn in patterns:
        m = re.match(pat, raw)
        if m:
            return fn(m)
    return None

totals = {}

with open(trace_file, newline='') as f:
    reader = csv.DictReader(f, delimiter='\t')
    for row in reader:
        status = (row.get('status') or '').strip()
        if status != 'COMPLETED':
            continue

        name = normalize_name(row.get('name') or '')
        if not name:
            continue

        dur = parse_duration(row.get('duration') or '')
        if dur is None:
            continue

        totals[name] = totals.get(name, 0) + dur

for k, v in sorted(totals.items()):
    print(f"{k}\t{v}")
PY
}

get_trace_duration_seconds_for_step() {
    local trace_file="$1"
    local step_name="$2"

    if [ ! -f "${trace_file}" ]; then
        echo ""
        return 0
    fi

    build_trace_duration_map "${trace_file}" \
      | awk -F'\t' -v target="${step_name}" '$1 == target {print $2; exit}'
}

format_completed_steps_with_duration() {
    local completed_steps="$1"
    local trace_file="$2"

    if [ -z "${completed_steps}" ]; then
        return 0
    fi

    while IFS= read -r line; do
        [ -z "${line}" ] && continue

        local step_name duration_seconds duration_fmt
        step_name="$(printf '%s\n' "${line}" | sed -E 's/^.*(pb16S:[^|]+)\|.*$/\1/' | sed 's/[[:space:]]*$//')"
        step_name="$(normalize_trace_step_name "${step_name}")"

        duration_seconds="$(get_trace_duration_seconds_for_step "${trace_file}" "${step_name}")"

        if [[ "${duration_seconds}" =~ ^[0-9]+$ ]]; then
            duration_fmt="$(format_duration "${duration_seconds}")"
        else
            duration_fmt="NA"
        fi

        echo "${line} | duration=${duration_fmt}"
    done <<< "${completed_steps}"
}

show_status_file_summary() {
    if [ ! -f "${STATUS_FILE}" ]; then
        echo "[INFO] 找不到 status 檔案：${STATUS_FILE}"
        return 1
    fi

    local status start_time start_epoch end_time duration_seconds exit_code
    local session_name project_dir stdout_log stderr_log trace_file
    local cpu resume extra_args workflow_dir timezone nxf_conda_cachedir
    local elapsed_fmt stale_hint
    local task_block executor_line current_task pending_tasks last_finished_task completed_steps completed_steps_with_duration

    status="$(read_status_value status)"
    start_time="$(read_status_value start_time)"
    start_epoch="$(read_status_value start_epoch)"
    end_time="$(read_status_value end_time)"
    duration_seconds="$(read_status_value duration_seconds)"
    exit_code="$(read_status_value exit_code)"
    session_name="$(read_status_value session_name)"
    project_dir="$(read_status_value project_dir)"
    stdout_log="$(read_status_value stdout_log)"
    stderr_log="$(read_status_value stderr_log)"
    trace_file="$(read_status_value trace_file)"
    cpu="$(read_status_value cpu)"
    resume="$(read_status_value resume)"
    extra_args="$(read_status_value extra_args)"
    workflow_dir="$(read_status_value workflow_dir)"
    timezone="$(read_status_value timezone)"
    nxf_conda_cachedir="$(read_status_value nxf_conda_cachedir)"

    if [ -z "${trace_file}" ]; then
        trace_file="${PROJECT_DIR}/logs/nextflow.trace.txt"
    fi

    if [ "${status:-}" = "running" ]; then
        elapsed_fmt="$(get_elapsed_from_start_epoch "${start_epoch:-}")"
    else
        elapsed_fmt="$(format_duration "${duration_seconds:-}")"
    fi

    task_block="$(extract_latest_executor_block "${stdout_log:-}" || true)"
    executor_line="$(extract_executor_line "${task_block}" || true)"
    current_task="$(extract_current_task_from_block "${task_block}" || true)"
    pending_tasks="$(extract_pending_tasks_from_block "${task_block}" || true)"
    last_finished_task="$(extract_last_finished_task_from_block "${task_block}" || true)"
    completed_steps="$(extract_completed_steps_from_block "${task_block}" || true)"
    completed_steps_with_duration="$(format_completed_steps_with_duration "${completed_steps}" "${trace_file}" || true)"

    stale_hint=""
    if [ "${status:-}" = "running" ] && ! tmux has-session -t "${session_name:-nonexistent}" 2>/dev/null; then
        stale_hint="可能 tmux session 已結束，但 status 檔尚未更新。"
    fi

    echo
    echo "=================================================="
    if [ "${SHOW_ALL}" = "true" ]; then
        echo "[INFO] 目前無活躍 pacbio_* tmux session，改讀目前專案 status 檔案"
    else
        echo "[INFO] 目前無屬於此專案的活躍 pacbio_* tmux session，改讀 status 檔案"
    fi
    echo "[INFO] SESSION       : ${session_name:-NA}"
    echo "[INFO] PROJECT       : ${project_dir:-NA}"
    echo "[INFO] STATUS        : ${status:-NA}"
    echo "[INFO] START_TIME    : ${start_time:-NA}"
    echo "[INFO] END_TIME      : ${end_time:-NA}"
    echo "[INFO] ELAPSED       : ${elapsed_fmt}"
    echo "[INFO] DURATION_SEC  : ${duration_seconds:-NA}"
    echo "[INFO] EXIT_CODE     : ${exit_code:-NA}"
    echo "[INFO] THREADS       : ${cpu:-NA}"
    echo "[INFO] RESUME        : ${resume:-NA}"
    echo "[INFO] EXTRA_ARGS    : ${extra_args:-NA}"
    echo "[INFO] WORKFLOW_DIR  : ${workflow_dir:-NA}"
    echo "[INFO] TIMEZONE      : ${timezone:-NA}"
    echo "[INFO] NXF_CONDA     : ${nxf_conda_cachedir:-NA}"
    echo "[INFO] STATUS_FILE   : ${STATUS_FILE}"
    echo "[INFO] TRACE_FILE    : ${trace_file:-NA}"

    if [ -n "${stdout_log:-}" ]; then
        echo "[INFO] STDOUT_LOG    : ${stdout_log}"
    fi
    if [ -n "${stderr_log:-}" ]; then
        echo "[INFO] STDERR_LOG    : ${stderr_log}"
    fi
    if [ -n "${executor_line:-}" ]; then
        echo "[INFO] EXECUTOR      : ${executor_line}"
    fi
    if [ -n "${completed_steps_with_duration:-}" ]; then
        echo "[INFO] COMPLETED_STEPS :"
        while IFS= read -r line; do
            [ -n "${line}" ] && echo "  - ${line}"
        done <<< "${completed_steps_with_duration}"
    fi
    if [ -n "${current_task:-}" ]; then
        echo "[INFO] CURRENT_TASK  : ${current_task}"
    fi
    if [ -n "${pending_tasks:-}" ]; then
        echo "[INFO] PENDING_TASKS :"
        while IFS= read -r line; do
            [ -n "${line}" ] && echo "  - ${line}"
        done <<< "${pending_tasks}"
    fi
    if [ -z "${current_task:-}" ] && [ -n "${last_finished_task:-}" ]; then
        echo "[INFO] LAST_FINISHED : ${last_finished_task}"
    fi
    if [ -n "${stale_hint}" ]; then
        echo "[WARN] ${stale_hint}"
    fi

    show_tail_lines "${stdout_log:-/dev/null}" 8 "[INFO] stdout 最後 8 行"
    show_tail_lines "${stderr_log:-/dev/null}" 5 "[INFO] stderr 最後 5 行"
}

print_session_block() {
    local session="$1"
    local project="$2"

    local logs_dir_session status_file_session stdout_log stderr_log trace_file
    local status start_time start_epoch elapsed threads
    local task_block executor_line current_task pending_tasks last_finished_task completed_steps completed_steps_with_duration

    logs_dir_session="${project}/logs"
    status_file_session="${logs_dir_session}/run_pacbio.status"
    stdout_log="${logs_dir_session}/nextflow.stdout.log"
    stderr_log="${logs_dir_session}/nextflow.stderr.log"
    trace_file="${logs_dir_session}/nextflow.trace.txt"

    status="running"
    start_time="NA"
    start_epoch=""
    elapsed="NA"
    threads="NA"
    task_block=""
    executor_line=""
    current_task=""
    pending_tasks=""
    last_finished_task=""
    completed_steps=""
    completed_steps_with_duration=""

    if [ -f "${status_file_session}" ]; then
        start_time="$(grep '^start_time=' "${status_file_session}" | cut -d= -f2- || true)"
        start_epoch="$(grep '^start_epoch=' "${status_file_session}" | cut -d= -f2- || true)"
        status="$(grep '^status=' "${status_file_session}" | cut -d= -f2- || true)"
        threads="$(grep '^cpu=' "${status_file_session}" | cut -d= -f2- || true)"
        trace_file_from_status="$(grep '^trace_file=' "${status_file_session}" | cut -d= -f2- || true)"
        if [ -n "${trace_file_from_status:-}" ]; then
            trace_file="${trace_file_from_status}"
        fi
    fi

    if [ -n "${start_epoch}" ]; then
        elapsed="$(get_elapsed_from_start_epoch "${start_epoch}")"
    fi

    task_block="$(extract_latest_executor_block "${stdout_log}" || true)"
    executor_line="$(extract_executor_line "${task_block}" || true)"
    current_task="$(extract_current_task_from_block "${task_block}" || true)"
    pending_tasks="$(extract_pending_tasks_from_block "${task_block}" || true)"
    last_finished_task="$(extract_last_finished_task_from_block "${task_block}" || true)"
    completed_steps="$(extract_completed_steps_from_block "${task_block}" || true)"
    completed_steps_with_duration="$(format_completed_steps_with_duration "${completed_steps}" "${trace_file}" || true)"

    echo
    echo "=================================================="
    echo "[INFO] SESSION       : ${session}"
    echo "[INFO] PROJECT       : ${project}"
    echo "[INFO] STATUS        : ${status:-running}"
    echo "[INFO] START_TIME    : ${start_time:-NA}"
    echo "[INFO] ELAPSED       : ${elapsed:-NA}"
    echo "[INFO] THREADS       : ${threads:-NA}"

    if [ -n "${executor_line}" ]; then
        echo "[INFO] EXECUTOR      : ${executor_line}"
    fi
    if [ -n "${completed_steps_with_duration}" ]; then
        echo "[INFO] COMPLETED_STEPS :"
        while IFS= read -r line; do
            [ -n "${line}" ] && echo "  - ${line}"
        done <<< "${completed_steps_with_duration}"
    fi
    if [ -n "${current_task}" ]; then
        echo "[INFO] CURRENT_TASK  : ${current_task}"
    fi
    if [ -n "${pending_tasks}" ]; then
        echo "[INFO] PENDING_TASKS :"
        while IFS= read -r line; do
            [ -n "${line}" ] && echo "  - ${line}"
        done <<< "${pending_tasks}"
    fi
    if [ -z "${current_task}" ] && [ -n "${last_finished_task}" ]; then
        echo "[INFO] LAST_FINISHED : ${last_finished_task}"
    fi

    show_tail_lines "${stdout_log}" 5 "[INFO] stdout 最後 5 行"
    show_tail_lines "${stderr_log}" 5 "[INFO] stderr 最後 5 行"
}

echo
echo "[INFO] PacBio tmux session 狀態總覽"
if [ "${SHOW_ALL}" = "true" ]; then
    echo "[INFO] 模式：全部專案"
else
    echo "[INFO] 目前專案目錄：${PROJECT_DIR}"
fi
echo "[INFO] CPU_USAGE     : $(get_cpu_used_and_total)"

mapfile -t ALL_PACBIO_SESSIONS < <(tmux ls 2>/dev/null | awk -F: '/^pacbio_/ {print $1}' || true)

PACBIO_SESSIONS=()
PACBIO_PROJECTS=()

for SESSION in "${ALL_PACBIO_SESSIONS[@]}"; do
    if ! tmux has-session -t "${SESSION}" 2>/dev/null; then
        continue
    fi

    SESSION_PROJECT="$(tmux show-environment -t "${SESSION}" 2>/dev/null | awk -F= '/^PROJECT_DIR=/ {print $2}' || true)"

    if [ "${SHOW_ALL}" = "true" ]; then
        if [ -n "${SESSION_PROJECT:-}" ]; then
            PACBIO_SESSIONS+=("${SESSION}")
            PACBIO_PROJECTS+=("${SESSION_PROJECT}")
        fi
    else
        if [ -n "${SESSION_PROJECT:-}" ] && [ "${SESSION_PROJECT}" = "${PROJECT_DIR}" ]; then
            PACBIO_SESSIONS+=("${SESSION}")
            PACBIO_PROJECTS+=("${SESSION_PROJECT}")
        fi
    fi
done

if [ "${#PACBIO_SESSIONS[@]}" -eq 0 ]; then
    echo
    if [ "${SHOW_ALL}" = "true" ]; then
        echo "[INFO] 目前沒有任何帶有 PROJECT_DIR 的 pacbio_* tmux session"
    else
        echo "[INFO] 目前沒有屬於此專案的 pacbio_* tmux session"
    fi
    show_status_file_summary
    exit 0
fi

for idx in "${!PACBIO_SESSIONS[@]}"; do
    print_session_block "${PACBIO_SESSIONS[$idx]}" "${PACBIO_PROJECTS[$idx]}"
done
