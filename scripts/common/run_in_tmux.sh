#!/usr/bin/env bash
set -euo pipefail

JOB_TYPE="${JOB_TYPE:-}"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
JOB_NAME="${JOB_NAME:-}"
PRE_CMD="${PRE_CMD:-}"
CMD="${CMD:-}"
CMD_FILE="${CMD_FILE:-}"
RUN_IN_TMUX="${RUN_IN_TMUX:-true}"
TIMEZONE="${TIMEZONE:-Asia/Taipei}"
LOG_DIR="${LOG_DIR:-${PROJECT_DIR}/logs}"

if [ -z "${JOB_TYPE}" ]; then
    echo "[ERROR] JOB_TYPE 不可為空"
    exit 1
fi

if [ -z "${JOB_NAME}" ]; then
    echo "[ERROR] JOB_NAME 不可為空"
    exit 1
fi

if [ -n "${CMD}" ] && [ -n "${CMD_FILE}" ]; then
    echo "[ERROR] CMD 與 CMD_FILE 只能擇一使用"
    exit 1
fi

if [ -z "${CMD}" ] && [ -z "${CMD_FILE}" ]; then
    echo "[ERROR] 必須提供 CMD 或 CMD_FILE"
    exit 1
fi

if [ -n "${CMD_FILE}" ] && [ ! -f "${CMD_FILE}" ]; then
    echo "[ERROR] 找不到 CMD_FILE：${CMD_FILE}"
    exit 1
fi

mkdir -p "${LOG_DIR}"

export TZ="${TIMEZONE}"

JOB_ID="${JOB_TYPE}_$(date +%Y%m%d_%H%M%S)"
SESSION_NAME="${JOB_ID}"

STDOUT_LOG="${LOG_DIR}/${JOB_ID}.stdout.log"
STDERR_LOG="${LOG_DIR}/${JOB_ID}.stderr.log"
STATUS_FILE="${LOG_DIR}/${JOB_ID}.status"

LATEST_STDOUT_LINK="${LOG_DIR}/latest_${JOB_TYPE}.stdout.log"
LATEST_STDERR_LINK="${LOG_DIR}/latest_${JOB_TYPE}.stderr.log"
LATEST_STATUS_LINK="${LOG_DIR}/latest_${JOB_TYPE}.status"

START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
START_EPOCH="$(date +%s)"

if [ -n "${CMD_FILE}" ]; then
    CMD_SOURCE="cmd_file"
    CMD_FULL="bash \"${CMD_FILE}\""
    CMD_PREVIEW="${CMD_FILE}"
else
    CMD_SOURCE="inline_cmd"
    CMD_FULL="${CMD}"
    CMD_PREVIEW="$(printf '%s' "${CMD}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-300)"
fi

PRE_CMD_PREVIEW="$(printf '%s' "${PRE_CMD}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-300)"

write_status_running() {
    cat > "${STATUS_FILE}" <<EOF
status=running
start_time=${START_TIME}
start_epoch=${START_EPOCH}
end_time=
end_epoch=
duration_seconds=
exit_code=
session_name=${SESSION_NAME}
job_id=${JOB_ID}
job_type=${JOB_TYPE}
job_name=${JOB_NAME}
project_dir=${PROJECT_DIR}
stdout_log=${STDOUT_LOG}
stderr_log=${STDERR_LOG}
cmd_source=${CMD_SOURCE}
pre_cmd=${PRE_CMD}
pre_cmd_preview=${PRE_CMD_PREVIEW}
cmd_preview=${CMD_PREVIEW}
cmd_full=${CMD_FULL}
timezone=${TIMEZONE}
run_in_tmux=${RUN_IN_TMUX}
EOF
}

write_status_running
ln -sfn "${STDOUT_LOG}" "${LATEST_STDOUT_LINK}"
ln -sfn "${STDERR_LOG}" "${LATEST_STDERR_LINK}"
ln -sfn "${STATUS_FILE}" "${LATEST_STATUS_LINK}"

build_runner_script() {
    cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
export TZ="${TIMEZONE}"
cd "${PROJECT_DIR}"

END_TIME=""
END_EPOCH=""
DURATION_SECONDS=""
EXIT_CODE=""

finish() {
    EXIT_CODE="\$1"
    END_TIME="\$(date '+%Y-%m-%d %H:%M:%S')"
    END_EPOCH="\$(date +%s)"
    DURATION_SECONDS=\$((END_EPOCH - ${START_EPOCH}))

    if [ "\${EXIT_CODE}" = "0" ]; then
        FINAL_STATUS="completed"
    else
        FINAL_STATUS="failed"
    fi

    cat > "${STATUS_FILE}" <<EOSTATUS
status=\${FINAL_STATUS}
start_time=${START_TIME}
start_epoch=${START_EPOCH}
end_time=\${END_TIME}
end_epoch=\${END_EPOCH}
duration_seconds=\${DURATION_SECONDS}
exit_code=\${EXIT_CODE}
session_name=${SESSION_NAME}
job_id=${JOB_ID}
job_type=${JOB_TYPE}
job_name=${JOB_NAME}
project_dir=${PROJECT_DIR}
stdout_log=${STDOUT_LOG}
stderr_log=${STDERR_LOG}
cmd_source=${CMD_SOURCE}
pre_cmd=${PRE_CMD}
pre_cmd_preview=${PRE_CMD_PREVIEW}
cmd_preview=${CMD_PREVIEW}
cmd_full=${CMD_FULL}
timezone=${TIMEZONE}
run_in_tmux=${RUN_IN_TMUX}
EOSTATUS
}

trap 'finish $?' EXIT

{
EOF

    if [ -n "${PRE_CMD}" ]; then
        cat <<EOF
${PRE_CMD}

EOF
    fi

    cat <<EOF
${CMD_FULL}
} > "${STDOUT_LOG}" 2> "${STDERR_LOG}"
EOF
}

RUNNER_SCRIPT="${LOG_DIR}/${JOB_ID}.runner.sh"
build_runner_script > "${RUNNER_SCRIPT}"
chmod +x "${RUNNER_SCRIPT}"

echo "[INFO] JOB_TYPE      = ${JOB_TYPE}"
echo "[INFO] JOB_NAME      = ${JOB_NAME}"
echo "[INFO] PROJECT_DIR   = ${PROJECT_DIR}"
echo "[INFO] JOB_ID        = ${JOB_ID}"
echo "[INFO] SESSION_NAME  = ${SESSION_NAME}"
echo "[INFO] LOG_DIR       = ${LOG_DIR}"
echo "[INFO] STATUS_FILE   = ${STATUS_FILE}"
echo "[INFO] STDOUT_LOG    = ${STDOUT_LOG}"
echo "[INFO] STDERR_LOG    = ${STDERR_LOG}"
if [ -n "${PRE_CMD}" ]; then
    echo "[INFO] PRE_CMD       = ${PRE_CMD_PREVIEW}"
fi
echo "[INFO] CMD_SOURCE    = ${CMD_SOURCE}"
echo "[INFO] CMD_PREVIEW   = ${CMD_PREVIEW}"

if [ "${RUN_IN_TMUX}" = "true" ]; then
    if ! command -v tmux >/dev/null 2>&1; then
        echo "[ERROR] 找不到 tmux，但 RUN_IN_TMUX=true"
        exit 1
    fi

    if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
        echo "[ERROR] tmux session 已存在：${SESSION_NAME}"
        exit 1
    fi

    tmux new-session -d -s "${SESSION_NAME}" "bash \"${RUNNER_SCRIPT}\""

    echo "[INFO] 已建立 tmux session: ${SESSION_NAME}"
    echo "[INFO] 查詢 session 任務清單：./shell_tools/check_tmux_jobs.sh"
    echo "[INFO] 查詢詳細任務進度：MODE=latest ./shell_tools/check_tmux_jobs.sh"
else
    echo "[INFO] 前景執行"
    bash "${RUNNER_SCRIPT}"
fi
