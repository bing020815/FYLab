#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

ENV_NAME="pacbio16s"
WORKFLOW_DIR="${HOME}/tools/HiFi-16S-workflow"
TIMEZONE="${TIMEZONE:-Asia/Taipei}"

NXF_CONDA_CACHEDIR="${NXF_CONDA_CACHEDIR:-/home/adprc/nf_conda}"
export NXF_CONDA_CACHEDIR
mkdir -p "${NXF_CONDA_CACHEDIR}"

SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"
OUTDIR="${PROJECT_DIR}/pacbio_results"
LOGS_DIR="${PROJECT_DIR}/logs"
WORK_DIR="${PROJECT_DIR}/work"

CPU="${CPU:-8}"
RESUME="${RESUME:-false}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
RUN_IN_TMUX="${RUN_IN_TMUX:-true}"

DEFAULT_SESSION_NAME="pacbio_$(TZ="${TIMEZONE}" date +%Y%m%d_%H%M%S)"
TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-${DEFAULT_SESSION_NAME}}"

STDOUT_LOG="${LOGS_DIR}/nextflow.stdout.log"
STDERR_LOG="${LOGS_DIR}/nextflow.stderr.log"
STATUS_FILE="${LOGS_DIR}/run_pacbio.status"
INNER_SCRIPT="${LOGS_DIR}/run_pacbio_inner.sh"

mkdir -p "${OUTDIR}" "${LOGS_DIR}" "${WORK_DIR}"

if [ ! -f "${SAMPLES_TSV}" ]; then
    echo "[ERROR] 找不到 ${SAMPLES_TSV}"
    exit 1
fi

if [ ! -f "${METADATA_TSV}" ]; then
    echo "[ERROR] 找不到 ${METADATA_TSV}"
    exit 1
fi

if [ ! -d "${WORKFLOW_DIR}" ]; then
    echo "[ERROR] 找不到 workflow：${WORKFLOW_DIR}"
    echo "[ERROR] 請先完成共用層安裝"
    exit 1
fi

if ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] 找不到 conda"
    exit 1
fi

write_inner_script() {
    cat > "${INNER_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -e
set -o pipefail
export TZ="${TIMEZONE}"

cd "${PROJECT_DIR}"

START_TIME="\$(date '+%Y-%m-%d %H:%M:%S')"
START_EPOCH="\$(date +%s)"

write_status() {
    local status="\$1"
    local end_time="\$2"
    local end_epoch="\$3"
    local duration_seconds="\$4"
    local exit_code="\$5"

    cat > "${STATUS_FILE}" <<EOSTATUS
status=\${status}
start_time=\${START_TIME}
start_epoch=\${START_EPOCH}
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
EOSTATUS
}

finish() {
    local exit_code="\$1"
    local end_time end_epoch duration_seconds final_status

    end_time="\$(date '+%Y-%m-%d %H:%M:%S')"
    end_epoch="\$(date +%s)"
    duration_seconds=\$((end_epoch - START_EPOCH))

    if [ "\${exit_code}" -eq 0 ]; then
        final_status="completed"
    else
        final_status="failed"
    fi

    write_status "\${final_status}" "\${end_time}" "\${end_epoch}" "\${duration_seconds}" "\${exit_code}"
}

trap 'finish $?' EXIT

write_status "running" "" "" "" ""

exec > "${STDOUT_LOG}" 2> "${STDERR_LOG}"

echo "[INFO] PacBio inner script started at \${START_TIME}"
echo "[INFO] PROJECT_DIR=${PROJECT_DIR}"
echo "[INFO] ENV_NAME=${ENV_NAME}"
echo "[INFO] RESUME=${RESUME}"
echo "[INFO] CPU=${CPU}"
echo "[INFO] NXF_CONDA_CACHEDIR=${NXF_CONDA_CACHEDIR}"

set +u
source "\$(conda info --base)/etc/profile.d/conda.sh"
conda deactivate >/dev/null 2>&1 || true
conda activate "${ENV_NAME}"
set -u

export NXF_CONDA_CACHEDIR="${NXF_CONDA_CACHEDIR}"

NEXTFLOW_CMD=(
    nextflow run "${WORKFLOW_DIR}/main.nf"
    --input "${SAMPLES_TSV}"
    --metadata "${METADATA_TSV}"
    --dada2_cpu "${CPU}"
    --vsearch_cpu "${CPU}"
    --outdir "${OUTDIR}"
    --publish_dir_mode copy
    -work-dir "${WORK_DIR}"
)

if [ "${RESUME}" = "true" ]; then
    NEXTFLOW_CMD+=(-resume)
fi

if [ -n "${EXTRA_ARGS}" ]; then
    # shellcheck disable=SC2206
    EXTRA_ARGS_ARRAY=( ${EXTRA_ARGS} )
    NEXTFLOW_CMD+=("\${EXTRA_ARGS_ARRAY[@]}")
fi

echo "[INFO] Running Nextflow command:"
printf ' %q' "\${NEXTFLOW_CMD[@]}"
echo

"\${NEXTFLOW_CMD[@]}"
EOF

    chmod +x "${INNER_SCRIPT}"
}

write_inner_script

echo "[INFO] PROJECT_DIR        = ${PROJECT_DIR}"
echo "[INFO] WORKFLOW_DIR       = ${WORKFLOW_DIR}"
echo "[INFO] OUTDIR             = ${OUTDIR}"
echo "[INFO] CPU                = ${CPU}"
echo "[INFO] RESUME             = ${RESUME}"
echo "[INFO] RUN_IN_TMUX        = ${RUN_IN_TMUX}"
echo "[INFO] EXTRA_ARGS         = ${EXTRA_ARGS}"
echo "[INFO] TIMEZONE           = ${TIMEZONE}"
echo "[INFO] NXF_CONDA_CACHEDIR = ${NXF_CONDA_CACHEDIR}"
echo "[INFO] STATUS_FILE        = ${STATUS_FILE}"

if [ "${RUN_IN_TMUX}" = "true" ]; then
    if ! command -v tmux >/dev/null 2>&1; then
        echo "[ERROR] 找不到 tmux，但 RUN_IN_TMUX=true"
        echo "[ERROR] 可改用 RUN_IN_TMUX=false 前景執行"
        exit 1
    fi

    if tmux has-session -t "${TMUX_SESSION_NAME}" 2>/dev/null; then
        echo "[ERROR] tmux session 已存在：${TMUX_SESSION_NAME}"
        echo "[ERROR] 請改用其他名稱，例如："
        echo "TMUX_SESSION_NAME=${TMUX_SESSION_NAME}_v2 ./shell_tools/run_pacbio_workflow.sh ${PROJECT_DIR}"
        exit 1
    fi

    tmux new-session -d -s "${TMUX_SESSION_NAME}" "bash '${INNER_SCRIPT}'"

    echo "[INFO] 已建立 tmux session: ${TMUX_SESSION_NAME}"
    echo "[INFO] 此 session 主要用途為避免遠端斷線導致任務中止"
    echo "[INFO] 請以以下方式監看進度："
    echo "[INFO]   ./shell_tools/check_pacbio_sessions.sh"
    echo "[INFO]   tail -f ${STDOUT_LOG}"
    echo "[INFO]   tail -f ${STDERR_LOG}"
    echo "[INFO]   cat ${STATUS_FILE}"
    echo "[INFO] 若需檢查 session 是否仍存在：tmux ls"
    echo "[INFO] 若需關閉 session：tmux kill-session -t ${TMUX_SESSION_NAME}"
else
    echo "[INFO] 前景執行 workflow"
    bash "${INNER_SCRIPT}"

    echo "[INFO] 執行完成"
    echo "[INFO] stdout log: ${STDOUT_LOG}"
    echo "[INFO] stderr log: ${STDERR_LOG}"
    echo "[INFO] status file: ${STATUS_FILE}"
fi
