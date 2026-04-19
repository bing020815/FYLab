#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

LOGS_DIR="${PROJECT_DIR}/logs"
STATUS_FILE="${LOGS_DIR}/run_pacbio.status"

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

show_status_file_summary() {
    if [ ! -f "${STATUS_FILE}" ]; then
        echo "[INFO] 找不到 status 檔案：${STATUS_FILE}"
        return 1
    fi

    local status start_time end_time duration_seconds exit_code
    local session_name project_dir stdout_log stderr_log
    local cpu resume extra_args workflow_dir timezone nxf_conda_cachedir

    status="$(read_status_value status)"
    start_time="$(read_status_value start_time)"
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

    echo
    echo "=================================================="
    echo "[INFO] 目前無活著的 pacbio_* tmux session，改讀 status 檔案"
    echo "[INFO] SESSION       : ${session_name:-NA}"
    echo "[INFO] PROJECT       : ${project_dir:-NA}"
    echo "[INFO] STATUS        : ${status:-NA}"
    echo "[INFO] START_TIME    : ${start_time:-NA}"
    echo "[INFO] END_TIME      : ${end_time:-NA}"
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
    ELAPSED="NA"

    if [ -f "${STATUS_FILE_SESSION}" ]; then
        START_TIME="$(grep '^start_time=' "${STATUS_FILE_SESSION}" | cut -d= -f2- || true)"
        STATUS="$(grep '^status=' "${STATUS_FILE_SESSION}" | cut -d= -f2- || true)"
    fi

    if [ -f "${STDOUT_LOG}" ]; then
        CURRENT_TASK="$(grep -E 'pb16S:|Plus [0-9]+ more processes waiting' "${STDOUT_LOG}" | tail -n 2 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"
    else
        CURRENT_TASK=""
    fi

    if tmux has-session -t "${SESSION}" 2>/dev/null; then
        ELAPSED="$(ps -eo etime,cmd | grep "tmux.*${SESSION}" | grep -v grep | head -n 1 | awk '{print $1}' || true)"
        [ -z "${ELAPSED}" ] && ELAPSED="running"
    fi

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
