#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

WORKFLOW_DIR="${WORKFLOW_DIR:-/home/adprc/tools/HiFi-16S-workflow}"
OUTDIR="${OUTDIR:-${PROJECT_DIR}/pacbio_results}"
WORK_DIR="${WORK_DIR:-${PROJECT_DIR}/work}"
LOG_DIR="${LOG_DIR:-${PROJECT_DIR}/logs}"

SAMPLES_TSV="${SAMPLES_TSV:-${PROJECT_DIR}/samples.tsv}"
METADATA_TSV="${METADATA_TSV:-${PROJECT_DIR}/metadata.tsv}"

CPU="${CPU:-8}"
RESUME="${RESUME:-false}"
RUN_IN_TMUX="${RUN_IN_TMUX:-true}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
TIMEZONE="${TIMEZONE:-Asia/Taipei}"
NXF_CONDA_CACHEDIR="${NXF_CONDA_CACHEDIR:-/home/adprc/nf_conda}"

STDOUT_LOG="${LOG_DIR}/nextflow.stdout.log"
STDERR_LOG="${LOG_DIR}/nextflow.stderr.log"
STATUS_FILE="${LOG_DIR}/run_pacbio.status"
TRACE_FILE="${LOG_DIR}/nextflow.trace.txt"
REPORT_FILE="${LOG_DIR}/nextflow.report.html"
TIMELINE_FILE="${LOG_DIR}/nextflow.timeline.html"

TMUX_SESSION_NAME="pacbio_$(date +%Y%m%d_%H%M%S)"

check_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[ERROR] 找不到指令：${cmd}"
        exit 1
    fi
}

check_file() {
    local file="$1"
    if [ ! -f "${file}" ]; then
        echo "[ERROR] 找不到檔案：${file}"
        exit 1
    fi
}

write_status_running() {
    local start_time="$1"
    local start_epoch="$2"

    cat > "${STATUS_FILE}" <<EOF
status=running
start_time=${start_time}
start_epoch=${start_epoch}
end_time=
end_epoch=
duration_seconds=
exit_code=
session_name=${TMUX_SESSION_NAME}
project_dir=${PROJECT_DIR}
stdout_log=${STDOUT_LOG}
stderr_log=${STDERR_LOG}
timezone=${TIMEZONE}
nxf_conda_cachedir=${NXF_CONDA_CACHEDIR}
cpu=${CPU}
resume=${RESUME}
extra_args=${EXTRA_ARGS}
workflow_dir=${WORKFLOW_DIR}
trace_file=${TRACE_FILE}
report_file=${REPORT_FILE}
timeline_file=${TIMELINE_FILE}
EOF
}

write_status_final() {
    local start_time="$1"
    local start_epoch="$2"
    local end_time="$3"
    local end_epoch="$4"
    local duration_seconds="$5"
    local exit_code="$6"
    local final_status="$7"

    cat > "${STATUS_FILE}" <<EOF
status=${final_status}
start_time=${start_time}
start_epoch=${start_epoch}
end_time=${end_time}
end_epoch=${end_epoch}
duration_seconds=${duration_seconds}
exit_code=${exit_code}
session_name=${TMUX_SESSION_NAME}
project_dir=${PROJECT_DIR}
stdout_log=${STDOUT_LOG}
stderr_log=${STDERR_LOG}
timezone=${TIMEZONE}
nxf_conda_cachedir=${NXF_CONDA_CACHEDIR}
cpu=${CPU}
resume=${RESUME}
extra_args=${EXTRA_ARGS}
workflow_dir=${WORKFLOW_DIR}
trace_file=${TRACE_FILE}
report_file=${REPORT_FILE}
timeline_file=${TIMELINE_FILE}
EOF
}

main() {
    check_cmd nextflow
    check_cmd tmux
    check_file "${SAMPLES_TSV}"
    check_file "${METADATA_TSV}"

    if [ ! -d "${WORKFLOW_DIR}" ]; then
        echo "[ERROR] 找不到 WORKFLOW_DIR：${WORKFLOW_DIR}"
        exit 1
    fi

    mkdir -p "${OUTDIR}" "${WORK_DIR}" "${LOG_DIR}"

    export TZ="${TIMEZONE}"
    export NXF_CONDA_CACHEDIR

    echo "[INFO] PROJECT_DIR        = ${PROJECT_DIR}"
    echo "[INFO] WORKFLOW_DIR       = ${WORKFLOW_DIR}"
    echo "[INFO] OUTDIR             = ${OUTDIR}"
    echo "[INFO] WORK_DIR           = ${WORK_DIR}"
    echo "[INFO] CPU                = ${CPU}"
    echo "[INFO] RESUME             = ${RESUME}"
    echo "[INFO] RUN_IN_TMUX        = ${RUN_IN_TMUX}"
    echo "[INFO] EXTRA_ARGS         = ${EXTRA_ARGS}"
    echo "[INFO] TIMEZONE           = ${TIMEZONE}"
    echo "[INFO] NXF_CONDA_CACHEDIR = ${NXF_CONDA_CACHEDIR}"
    echo "[INFO] STATUS_FILE        = ${STATUS_FILE}"
    echo "[INFO] TRACE_FILE         = ${TRACE_FILE}"
    echo "[INFO] REPORT_FILE        = ${REPORT_FILE}"
    echo "[INFO] TIMELINE_FILE      = ${TIMELINE_FILE}"

    local start_time start_epoch resume_flag
    start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    start_epoch="$(date +%s)"

    if [ "${RESUME}" = "true" ]; then
        resume_flag="-resume"
    else
        resume_flag=""
    fi

    write_status_running "${start_time}" "${start_epoch}"

    local runner_script
    runner_script="${LOG_DIR}/${TMUX_SESSION_NAME}.runner.sh"

    cat > "${runner_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export TZ="${TIMEZONE}"
export NXF_CONDA_CACHEDIR="${NXF_CONDA_CACHEDIR}"

cd "${PROJECT_DIR}"

START_TIME="${start_time}"
START_EPOCH="${start_epoch}"

finish() {
    local exit_code="\$1"
    local end_time end_epoch duration_seconds final_status
    end_time="\$(date '+%Y-%m-%d %H:%M:%S')"
    end_epoch="\$(date +%s)"
    duration_seconds=\$((end_epoch - START_EPOCH))

    if [ "\${exit_code}" = "0" ]; then
        final_status="completed"
    else
        final_status="failed"
    fi

    cat > "${STATUS_FILE}" <<EOSTATUS
status=\${final_status}
start_time=${start_time}
start_epoch=${start_epoch}
end_time=\${end_time}
end_epoch=\${end_epoch}
duration_seconds=\${duration_seconds}
exit_code=\${exit_code}
session_name=${TMUX_SESSION_NAME}
project_dir=${PROJECT_DIR}
stdout_log=${STDOUT_LOG}
stderr_log=${STDERR_LOG}
timezone=${TIMEZONE}
nxf_conda_cachedir=${NXF_CONDA_CACHEDIR}
cpu=${CPU}
resume=${RESUME}
extra_args=${EXTRA_ARGS}
workflow_dir=${WORKFLOW_DIR}
trace_file=${TRACE_FILE}
report_file=${REPORT_FILE}
timeline_file=${TIMELINE_FILE}
EOSTATUS
}

trap 'finish \$?' EXIT

nextflow run "${WORKFLOW_DIR}/main.nf" \
  --input "${SAMPLES_TSV}" \
  --metadata "${METADATA_TSV}" \
  --outdir "${OUTDIR}" \
  --dada2_cpu "${CPU}" \
  --vsearch_cpu "${CPU}" \
  -work-dir "${WORK_DIR}" \
  -with-trace "${TRACE_FILE}" \
  -with-report "${REPORT_FILE}" \
  -with-timeline "${TIMELINE_FILE}" \
  ${resume_flag} \
  ${EXTRA_ARGS} \
  > "${STDOUT_LOG}" 2> "${STDERR_LOG}"
EOF

    chmod +x "${runner_script}"

    if [ "${RUN_IN_TMUX}" = "true" ]; then
        if tmux has-session -t "${TMUX_SESSION_NAME}" 2>/dev/null; then
            echo "[ERROR] tmux session 已存在：${TMUX_SESSION_NAME}"
            exit 1
        fi

        tmux new-session -d -s "${TMUX_SESSION_NAME}" "bash '${runner_script}'"
        tmux set-environment -t "${TMUX_SESSION_NAME}" PROJECT_DIR "${PROJECT_DIR}"

        echo "[INFO] 已建立 tmux session: ${TMUX_SESSION_NAME}"
        echo "[INFO] 此 session 主要用途為避免遠端斷線導致任務中止"
        echo "[INFO] 請以以下方式監看進度："
        echo "[INFO]   ./shell_tools/check_pacbio_sessions.sh"
        echo "[INFO]   SHOW_ALL=true ./shell_tools/check_pacbio_sessions.sh"
        echo "[INFO]   tail -f ${STDOUT_LOG}"
        echo "[INFO]   tail -f ${STDERR_LOG}"
        echo "[INFO]   cat ${STATUS_FILE}"
        echo "[INFO] 若需檢查 session 是否仍存在：tmux ls"
        echo "[INFO] 若需關閉 session：tmux kill-session -t ${TMUX_SESSION_NAME}"
    else
        echo "[INFO] 前景執行 workflow"
        bash "${runner_script}"
    fi
}

main "$@"
