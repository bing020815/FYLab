#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PICRUSt2 Hidden-state prediction launcher
#
# Parallel jobs:
#   1. Marker gene + NSTI
#   2. KO prediction
#   3. EC prediction
#
# Default:
#   --cores 2
#
# Usage:
#   ./shell_tools/run_hsp_predictions.sh
#   ./shell_tools/run_hsp_predictions.sh --cores 4
# ============================================================


# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------
PROJECT_DIR="."
CORES=2


# ------------------------------------------------------------
# Help
# ------------------------------------------------------------
usage() {
    cat <<EOF
Usage:
  ./shell_tools/run_hsp_predictions.sh [options]

Options:
  --cores N         CPU cores for each HSP job (default: 2)
  --project-dir DIR Project root directory (default: .)
  -h, --help        Show this help

Examples:
  ./shell_tools/run_hsp_predictions.sh

  ./shell_tools/run_hsp_predictions.sh --cores 4

  ./shell_tools/run_hsp_predictions.sh \
    --project-dir . \
    --cores 4
EOF
}


# ------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cores)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --cores requires a value"
                exit 1
            fi
            CORES="$2"
            shift 2
            ;;

        --project-dir)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --project-dir requires a value"
                exit 1
            fi
            PROJECT_DIR="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "[ERROR] Unknown option: $1"
            echo
            usage
            exit 1
            ;;
    esac
done


# ------------------------------------------------------------
# Validate arguments
# ------------------------------------------------------------
if ! [[ "${CORES}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --cores must be a positive integer"
    exit 1
fi

if [[ ! -d "${PROJECT_DIR}" ]]; then
    echo "[ERROR] Project directory not found: ${PROJECT_DIR}"
    exit 1
fi

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"
CHECK_TMUX="${PROJECT_DIR}/shell_tools/check_tmux_jobs.sh"


# ------------------------------------------------------------
# Validate required files / commands
# ------------------------------------------------------------
if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] run_in_tmux.sh not found or not executable:"
    echo "        ${RUN_IN_TMUX}"
    exit 1
fi

if [[ ! -f "${PROJECT_DIR}/out.tre" ]]; then
    echo "[ERROR] Required placement tree not found:"
    echo "        ${PROJECT_DIR}/out.tre"
    echo
    echo "[INFO] Run PICRUSt2 sequence placement first."
    exit 1
fi

if ! command -v hsp.py >/dev/null 2>&1; then
    echo "[ERROR] hsp.py not found in the current environment"
    echo
    echo "[INFO] Please activate the PICRUSt2 environment first."
    exit 1
fi


# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo "=================================================="
echo " PICRUSt2 Hidden-state Prediction"
echo "=================================================="
echo "[INFO] PROJECT_DIR : ${PROJECT_DIR}"
echo "[INFO] CORES/JOB   : ${CORES}"
echo
echo "[INFO] Jobs:"
echo "       1. Marker gene + NSTI"
echo "       2. KO prediction"
echo "       3. EC prediction"
echo


# ------------------------------------------------------------
# 1. Marker gene + NSTI
# ------------------------------------------------------------
echo "[INFO] Submitting Marker gene + NSTI prediction..."

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME=picrust2_hsp_marker_nsti \
CMD="hsp.py \
  -i 16S \
  -t out.tre \
  -o marker_predicted_and_nsti.tsv.gz \
  -p ${CORES} \
  -n" \
"${RUN_IN_TMUX}"


# run_in_tmux.sh currently uses:
#   JOB_ID="${JOB_TYPE}_YYYYMMDD_HHMMSS"
#
# All three jobs use JOB_TYPE=picrust_hsp.
# Wait one second to prevent JOB_ID / session / log collisions.
sleep 1


# ------------------------------------------------------------
# 2. KO
# ------------------------------------------------------------
echo
echo "[INFO] Submitting KO prediction..."

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME=picrust2_hsp_ko \
CMD="hsp.py \
  -i KO \
  -t out.tre \
  -o KO_predicted.tsv.gz \
  -p ${CORES}" \
"${RUN_IN_TMUX}"


sleep 1


# ------------------------------------------------------------
# 3. EC
# ------------------------------------------------------------
echo
echo "[INFO] Submitting EC prediction..."

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME=picrust2_hsp_ec \
CMD="hsp.py \
  -i EC \
  -t out.tre \
  -o EC_predicted.tsv.gz \
  -p ${CORES}" \
"${RUN_IN_TMUX}"


# ------------------------------------------------------------
# Status information
# ------------------------------------------------------------
echo
echo "=================================================="
echo " HSP jobs submitted"
echo "=================================================="
echo "[INFO] Marker gene + NSTI : ${CORES} cores"
echo "[INFO] KO                 : ${CORES} cores"
echo "[INFO] EC                 : ${CORES} cores"
echo
echo "[INFO] The three jobs are running independently in tmux."
echo

if [[ -x "${CHECK_TMUX}" ]]; then
    echo "[INFO] 查詢 HSP 任務摘要："
    echo "  JOB_TYPE=picrust_hsp ./shell_tools/check_tmux_jobs.sh"
    echo
    echo "[INFO] 查詢 HSP 任務詳細進度："
    echo "  MODE=all JOB_TYPE=picrust_hsp ./shell_tools/check_tmux_jobs.sh"
else
    echo "[WARN] check_tmux_jobs.sh not found or not executable:"
    echo "       ${CHECK_TMUX}"
fi

echo
