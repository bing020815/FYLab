#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

LOGS_DIR="${PROJECT_DIR}/logs"
STATUS_FILE="${LOGS_DIR}/run_pacbio.status"

format_duration() {
    local total="${1:-}"

    if ! [[ "${total}" =~ ^[0-9]+$ ]]; then
        echo "NA"
        return
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
        return
    fi

    local now elapsed
    now="$(date +%s)"
    elapsed=$(( now - start_epoch ))

    if [ "${elapsed}" -lt 0 ]; then
        echo "NA"
        return
    fi

    format_duration "${elapsed}"
}

show_tail_lines() {
    local file="$1"
    local n="${2:-8}"
    local title="$3"

    echo
    echo "${title}"
    if [ -f "${file}" ]; then
        tail -n "${n}" "${file}" || true
    else
        echo "[INFO] 找不到檔案：${file}"
    fi
}

read_status_value() {
    local key="$1"
    grep "^${key}=" "${STATUS_FILE}" 2>/dev/null | head -n 1 | cut -d'=' -f2-
}

extract_current_task_from_stdout() {
    local stdout_log="$1"

    if [ ! -f "${stdout_log}" ]; then
        return
    fi

    grep -E 'pb16S:|Plus [0-9]+ more processes waiting' "${stdout_log}" \
      | tail -n 8 \
      | tr '\n' ' ' \
      | sed 's/[[:space:]]\+/ /g' \
      | sed 's/^ *//; s/ *$//'
}

extract_current_task_from_nextflow_log() {
    local nf_log="$1"

    if [ ! -f "${nf_log}" ]; then
        return
    fi

    grep -E 'pb16S:' "${nf_log}" \
      | tail -n 5 \
      | tr '\n' ' ' \
      | sed 's/[[:space:]]\+/ /g' \
      | sed 's/^ *//; s/ *$//'
}

show_status_file_summary() {
    if [ ! -f "${STATUS_FILE}" ]; then
        echo "[INFO] 找不到 status 檔案：${STATUS_FILE}"
        return 1
    fi

    local status start_time start_epoch end_time duration_seconds exit_code
    local session_name project_dir stdout_log stderr_log
    local cpu resume extra_args workflow_dir timezone nxf_conda_cachedir
    local elapsed_fmt current_task nf_log stale_hint

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
    cpu="$(read_status_value cpu)"
    resume="$(read_status_value resume)"
    extra_args="$(read_status_value extra_args)"
    workflow_dir="$(read_status_value workflow_dir)"
    timezone="$(read_status_value timezone)"
    nxf_conda_cachedir="$(read_status_value nxf_conda_cachedir)"

    if [ "${status:-}" = "running" ]; then
        elapsed_fmt="$(get_elapsed_from_start_epoch "${start_epoch:-}")"
    else
        elapsed_fmt="$(format_duration "${duration_seconds:-}")"
    fi

    current_task="$(extract_current_task_from_stdout "${stdout_log:-}")"

    nf_log="${PROJECT_DIR}/.nextflow.log"
    if [ -z "${current_task}" ]; then
        current_task="$(extract_current_task_from_nextflow_log "${nf_log}")"
    fi

    stale_hint=""
    if [ "${status:-}" = "running" ] && ! tmux has-session -t "${session_name:-nonexistent}" 2>/dev/null; then
        stale_hint="可能 tmux session 已結束，但 status 檔尚未更新。"
    fi

    echo
    echo "=================================================="
    echo "[INFO] 目前無活著的 pacbio_* tmux session，改讀 status 檔案"
    echo "[INFO] SESSION       : ${session_name:-NA}"
    echo "[INFO] PROJECT       : ${project_dir:-NA}"
    echo "[INFO] STATUS        : ${status:-NA}"
    echo "[INFO] START_TIME    : ${start_time:-NA}"
    echo "[INFO] END_TIME      : ${end_time:-NA}"
    echo "[INFO] ELAPSED       : ${elapsed_fmt}"
    echo "[INFO] DURATION_SEC  : ${duration_seconds:-NA}"
    echo "[INFO] EXIT_CODE     : ${exit_code:-NA}"
    echo "[INFO] CPU           : ${cpu:-NA}"
    echo "[INFO] RESUME        : ${resume:-NA}"
    echo "[INFO] EXTRA_ARGS    : ${extra_args:-NA}"
    echo "[INFO] WORKFLOW_DIR  : ${workflow_dir:-NA}"
    echo "[INFO] TIMEZONE      : ${timezone:-NA}"
    echo "[INFO] NXF_CONDA     : ${nxf_conda_cachedir:-NA}"
    echo "[INFO] STATUS_FILE   : ${STATUS_FILE}"

    if [ -n "${stdout_log:-}" ]; then
        echo "[INFO] STDOUT_LOG    : ${stdout_log}"
    fi
    if [ -n "${stderr_log:-}" ]; then
        echo "[INFO] STDERR_LOG    : ${stderr_log}"
    fi
    if [ -n "${current_task:-}" ]; then
        echo "[INFO] CURRENT_TASK  : ${current_task}"
    fi
    if [ -n "${stale_hint}" ]; then
        echo "[WARN] ${stale_hint}"
    fi

    show_tail_lines "${stdout_log:-/dev/null}" 8 "[INFO] stdout 最後 8 行"
    show_tail_lines "${stderr_log:-/dev/null}" 5 "[INFO] stderr 最後 5 行"
}

echo
echo "[INFO] PacBio tmux session 狀態總覽"

mapfile -t PACBIO_SESSIONS < <(tmux ls 2>/dev/null | awk -F: '/^pacbio_/ {print $1}')

if [ "${#PACBIO_SESSIONS[@]}" -eq 0 ]; then
    echo
    echo "[INFO] 目前沒有 pacbio_* 的 tmux session"
    show_status_file_summary
    exit 0
fi

for SESSION in "${PACBIO_SESSIONS[@]}"; do
    echo
    echo "=================================================="
    echo "[INFO] SESSION       : ${SESSION}"

    PROJECT="$(tmux show-environment -t "${SESSION}" 2>/dev/null | awk -F= '/^PROJECT_DIR=/ {print $2}')"
    [ -z "${PROJECT:-}" ] && PROJECT="${PROJECT_DIR}"

    LOGS_DIR_SESSION="${PROJECT}/logs"
    STATUS_FILE_SESSION="${LOGS_DIR_SESSION}/run_pacbio.status"
    STDOUT_LOG="${LOGS_DIR_SESSION}/nextflow.stdout.log"
    STDERR_LOG="${LOGS_DIR_SESSION}/nextflow.stderr.log"

    STATUS="running"
    START_TIME="NA"
    START_EPOCH=""
    ELAPSED="NA"
    CURRENT_TASK=""

    if [ -f "${STATUS_FILE_SESSION}" ]; then
        START_TIME="$(grep '^start_time=' "${STATUS_FILE_SESSION}" | cut -d= -f2- || true)"
        START_EPOCH="$(grep '^start_epoch=' "${STATUS_FILE_SESSION}" | cut -d= -f2- || true)"
        STATUS="$(grep '^status=' "${STATUS_FILE_SESSION}" | cut -d= -f2- || true)"
    fi

    if [ -n "${START_EPOCH}" ]; then
        ELAPSED="$(get_elapsed_from_start_epoch "${START_EPOCH}")"
    fi

    CURRENT_TASK="$(extract_current_task_from_stdout "${STDOUT_LOG}")"

    echo "[INFO] PROJECT       : ${PROJECT}"
    echo "[INFO] STATUS        : ${STATUS:-running}"
    echo "[INFO] START_TIME    : ${START_TIME:-NA}"
    echo "[INFO] ELAPSED       : ${ELAPSED:-NA}"

    if [ -n "${CURRENT_TASK}" ]; then
        echo "[INFO] CURRENT_TASK  : ${CURRENT_TASK}"
    fi

    show_tail_lines "${STDOUT_LOG}" 8 "[INFO] stdout 最後 8 行"
    show_tail_lines "${STDERR_LOG}" 5 "[INFO] stderr 最後 5 行"
done
