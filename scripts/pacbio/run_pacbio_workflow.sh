#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
ENV_NAME="pacbio16s"
WORKFLOW_DIR="${HOME}/tools/HiFi-16S-workflow"

SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"
OUTDIR="${PROJECT_DIR}/pacbio_results"
LOGS_DIR="${PROJECT_DIR}/logs"
WORK_DIR="${PROJECT_DIR}/work"

CPU="${CPU:-8}"
RESUME="${RESUME:-false}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
RUN_IN_TMUX="${RUN_IN_TMUX:-true}"

DEFAULT_SESSION_NAME="pacbio_$(date +%Y%m%d_%H%M%S)"
TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-${DEFAULT_SESSION_NAME}}"

STDOUT_LOG="${LOGS_DIR}/nextflow.stdout.log"
STDERR_LOG="${LOGS_DIR}/nextflow.stderr.log"

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

build_workflow_cmd() {
    local cmd=""
    cmd+="cd \"${PROJECT_DIR}\" && "
    cmd+="source \"\$(conda info --base)/etc/profile.d/conda.sh\" && "
    cmd+="conda activate \"${ENV_NAME}\" && "
    cmd+="nextflow run \"${WORKFLOW_DIR}/main.nf\" "
    cmd+="--input \"${SAMPLES_TSV}\" "
    cmd+="--metadata \"${METADATA_TSV}\" "
    cmd+="--dada2_cpu \"${CPU}\" "
    cmd+="--vsearch_cpu \"${CPU}\" "
    cmd+="--outdir \"${OUTDIR}\" "
    cmd+="--publish_dir_mode copy "
    cmd+="-work-dir \"${WORK_DIR}\" "

    if [ "${RESUME}" = "true" ]; then
        cmd+="-resume "
    fi

    if [ -n "${EXTRA_ARGS}" ]; then
        cmd+="${EXTRA_ARGS} "
    fi

    printf "%s" "${cmd}"
}

WORKFLOW_CMD="$(build_workflow_cmd)"

echo "[INFO] PROJECT_DIR = ${PROJECT_DIR}"
echo "[INFO] OUTDIR      = ${OUTDIR}"
echo "[INFO] CPU         = ${CPU}"
echo "[INFO] RESUME      = ${RESUME}"
echo "[INFO] RUN_IN_TMUX = ${RUN_IN_TMUX}"
echo "[INFO] EXTRA_ARGS  = ${EXTRA_ARGS}"

if [ "${RUN_IN_TMUX}" = "true" ]; then
    if ! command -v tmux >/dev/null 2>&1; then
        echo "[ERROR] 找不到 tmux，但 RUN_IN_TMUX=true"
        echo "[ERROR] 可改用 RUN_IN_TMUX=false 前景執行"
        exit 1
    fi

    if tmux has-session -t "${TMUX_SESSION_NAME}" 2>/dev/null; then
        echo "[ERROR] tmux session 已存在：${TMUX_SESSION_NAME}"
        echo "[ERROR] 請改用其他名稱，例如："
        echo "TMUX_SESSION_NAME=${TMUX_SESSION_NAME}_v2 ./run_pacbio_workflow.sh ${PROJECT_DIR}"
        exit 1
    fi

    TMUX_CMD=$(cat <<EOF
bash -lc '${WORKFLOW_CMD} > "${STDOUT_LOG}" 2> "${STDERR_LOG}"'
EOF
)

    tmux new-session -d -s "${TMUX_SESSION_NAME}" "${TMUX_CMD}"

    echo "[INFO] 已建立 tmux session: ${TMUX_SESSION_NAME}"
    echo "[INFO] 重新接回畫面：tmux attach -t ${TMUX_SESSION_NAME}"
    echo "[INFO] 查看 session 清單：tmux ls"
    echo "[INFO] 若要離開畫面但不中止工作，請按：Ctrl+b 然後按 d"
    echo "[INFO] stdout log: ${STDOUT_LOG}"
    echo "[INFO] stderr log: ${STDERR_LOG}"

else
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate "${ENV_NAME}"

    echo "[INFO] 前景執行 workflow"
    bash -lc "${WORKFLOW_CMD}" > "${STDOUT_LOG}" 2> "${STDERR_LOG}"

    echo "[INFO] 執行完成"
    echo "[INFO] stdout log: ${STDOUT_LOG}"
    echo "[INFO] stderr log: ${STDERR_LOG}"
fi
