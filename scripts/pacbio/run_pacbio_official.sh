#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
ENV_NAME="pacbio16s"
WORKFLOW_DIR="${HOME}/tools/HiFi-16S-workflow"

SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"
PACBIO_RESULTS_DIR="${PROJECT_DIR}/pacbio_results"
LOGS_DIR="${PROJECT_DIR}/logs"
WORK_DIR="${PROJECT_DIR}/work"

CPU="${CPU:-8}"

mkdir -p "${PACBIO_RESULTS_DIR}" "${LOGS_DIR}" "${WORK_DIR}"

if [ ! -f "${SAMPLES_TSV}" ]; then
    echo "[ERROR] 找不到 ${SAMPLES_TSV}"
    exit 1
fi

if [ ! -f "${METADATA_TSV}" ]; then
    echo "[ERROR] 找不到 ${METADATA_TSV}"
    exit 1
fi

if [ ! -d "${WORKFLOW_DIR}" ]; then
    echo "[ERROR] 找不到官方 workflow：${WORKFLOW_DIR}"
    echo "請先執行 setup_pacbio_workflow.sh"
    exit 1
fi

if ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] 找不到 conda"
    exit 1
fi

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "${ENV_NAME}"

cd "${PROJECT_DIR}"

echo "[INFO] 開始執行 PacBio workflow"
echo "[INFO] PROJECT_DIR = ${PROJECT_DIR}"
echo "[INFO] CPU = ${CPU}"

nextflow run "${WORKFLOW_DIR}/main.nf" \
    --input "${SAMPLES_TSV}" \
    --metadata "${METADATA_TSV}" \
    --dada2_cpu "${CPU}" \
    --vsearch_cpu "${CPU}" \
    -work-dir "${WORK_DIR}" \
    > "${LOGS_DIR}/nextflow.stdout.log" \
    2> "${LOGS_DIR}/nextflow.stderr.log"

echo "[INFO] PacBio workflow 執行完成"
echo "[INFO] 請查看 logs/ 與 workflow 輸出資料夾"