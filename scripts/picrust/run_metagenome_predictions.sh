#!/usr/bin/env bash

set -euo pipefail


# ============================================================
# PICRUSt2 / PICRUSt2-SC metagenome prediction launcher
#
# Usage:
#   ./shell_tools/run_metagenome_predictions.sh --input raw
#   ./shell_tools/run_metagenome_predictions.sh --input dehost
#
# Environment:
#   conda activate picrust2
#   conda activate picrust2sc
#
# This script:
#   1. Detects PICRUSt2 / PICRUSt2-SC from current Conda env
#   2. Selects raw / dehost BIOM input
#   3. Launches KO and EC metagenome predictions in parallel
# ============================================================


# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------
PROJECT_DIR="."
INPUT_MODE=""


# ------------------------------------------------------------
# Help
# ------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_metagenome_predictions.sh --input raw
  ./shell_tools/run_metagenome_predictions.sh --input dehost

Required:
  --input MODE

    raw
      Use:
        phyloseq/feature-table.biom

    dehost
      Use:
        phyloseq/dehost_output/dehost_otu_table.biom


Environment detection:

  PICRUSt2 2.5.2
    conda activate picrust2

  PICRUSt2-SC
    conda activate picrust2sc


Examples:

  conda activate picrust2
  ./shell_tools/run_metagenome_predictions.sh --input dehost

  conda activate picrust2sc
  ./shell_tools/run_metagenome_predictions.sh --input raw

EOF
}


# ------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --input requires a value: raw or dehost"
                exit 1
            fi

            INPUT_MODE="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "[ERROR] Unknown argument: $1"
            echo
            usage
            exit 1
            ;;
    esac
done


# ------------------------------------------------------------
# Validate input mode
# ------------------------------------------------------------
if [[ -z "${INPUT_MODE}" ]]; then
    echo "[ERROR] Please specify --input raw or --input dehost"
    echo
    usage
    exit 1
fi

case "${INPUT_MODE}" in
    raw)
        BIOM_INPUT="phyloseq/feature-table.biom"
        ;;

    dehost)
        BIOM_INPUT="phyloseq/dehost_output/dehost_otu_table.biom"
        ;;

    *)
        echo "[ERROR] Invalid --input value: ${INPUT_MODE}"
        echo "[INFO] Supported values: raw, dehost"
        exit 1
        ;;
esac


# ------------------------------------------------------------
# Detect current Conda environment
# ------------------------------------------------------------
CURRENT_ENV="${CONDA_DEFAULT_ENV:-}"

case "${CURRENT_ENV}" in
    picrust2)
        METHOD="picrust2"
        ;;

    picrust2sc)
        METHOD="picrust2sc"
        ;;

    *)
        echo "[ERROR] Unsupported Conda environment"
        echo "[INFO] Current environment: ${CURRENT_ENV:-None}"
        echo
        echo "[INFO] Please activate one of:"
        echo
        echo "  conda activate picrust2"
        echo "  conda activate picrust2sc"
        echo
        exit 1
        ;;
esac


# ------------------------------------------------------------
# Resolve project directory
# ------------------------------------------------------------
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"
CHECK_TMUX="${PROJECT_DIR}/shell_tools/check_tmux_jobs.sh"

BIOM_PATH="${PROJECT_DIR}/${BIOM_INPUT}"

MARKER_FILE="${PROJECT_DIR}/marker_predicted_and_nsti.tsv.gz"
KO_FILE="${PROJECT_DIR}/KO_predicted.tsv.gz"
EC_FILE="${PROJECT_DIR}/EC_predicted.tsv.gz"


# ------------------------------------------------------------
# Validate required files / commands
# ------------------------------------------------------------
if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] Missing executable:"
    echo "  ${RUN_IN_TMUX}"
    exit 1
fi

if [[ ! -x "${CHECK_TMUX}" ]]; then
    echo "[ERROR] Missing executable:"
    echo "  ${CHECK_TMUX}"
    exit 1
fi

if [[ ! -f "${BIOM_PATH}" ]]; then
    echo "[ERROR] Input BIOM file not found:"
    echo "  ${BIOM_PATH}"
    exit 1
fi

if [[ ! -f "${MARKER_FILE}" ]]; then
    echo "[ERROR] Marker prediction file not found:"
    echo "  ${MARKER_FILE}"
    echo
    echo "[INFO] Step 2 HSP must be completed first."
    exit 1
fi

if [[ ! -f "${KO_FILE}" ]]; then
    echo "[ERROR] KO prediction file not found:"
    echo "  ${KO_FILE}"
    echo
    echo "[INFO] Step 2 HSP must be completed first."
    exit 1
fi

if [[ ! -f "${EC_FILE}" ]]; then
    echo "[ERROR] EC prediction file not found:"
    echo "  ${EC_FILE}"
    echo
    echo "[INFO] Step 2 HSP must be completed first."
    exit 1
fi

if ! command -v metagenome_pipeline.py >/dev/null 2>&1; then
    echo "[ERROR] metagenome_pipeline.py not found in current environment."
    echo "[INFO] Current environment: ${CURRENT_ENV}"
    exit 1
fi


# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
echo "============================================================"
echo " PICRUSt metagenome predictions"
echo "============================================================"
echo
echo "[INFO] Project directory : ${PROJECT_DIR}"
echo "[INFO] Conda environment : ${CURRENT_ENV}"
echo "[INFO] Method            : ${METHOD}"
echo "[INFO] Input mode        : ${INPUT_MODE}"
echo "[INFO] BIOM input        : ${BIOM_INPUT}"
echo
echo "[INFO] Jobs:"
echo "  - KO"
echo "  - EC"
echo


# ============================================================
# PICRUSt2
# ============================================================
if [[ "${METHOD}" == "picrust2" ]]; then

    # --------------------------------------------------------
    # KO
    # --------------------------------------------------------
    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_picrust2_ko_metagenome" \
    CMD="metagenome_pipeline.py \
      -i ${BIOM_INPUT} \
      -m marker_predicted_and_nsti.tsv.gz \
      -f KO_predicted.tsv.gz \
      -o KO_metagenome_out \
      --strat_out" \
    "${RUN_IN_TMUX}"

    # Prevent JOB_ID collision in current run_in_tmux.sh
    sleep 1

    # --------------------------------------------------------
    # EC
    # --------------------------------------------------------
    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_picrust2_ec_metagenome" \
    CMD="metagenome_pipeline.py \
      -i ${BIOM_INPUT} \
      -m marker_predicted_and_nsti.tsv.gz \
      -f EC_predicted.tsv.gz \
      -o EC_metagenome_out \
      --strat_out" \
    "${RUN_IN_TMUX}"


# ============================================================
# PICRUSt2-SC
# ============================================================
elif [[ "${METHOD}" == "picrust2sc" ]]; then

    # --------------------------------------------------------
    # KO
    # --------------------------------------------------------
    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_picrust2sc_ko_metagenome" \
    CMD="metagenome_pipeline.py \
      --input ${BIOM_INPUT} \
      --marker marker_predicted_and_nsti.tsv.gz \
      --function KO_predicted.tsv.gz \
      --out_dir KO_metagenome_out \
      --max_nsti 2.0 \
      --strat_out" \
    "${RUN_IN_TMUX}"

    # Prevent JOB_ID collision in current run_in_tmux.sh
    sleep 1

    # --------------------------------------------------------
    # EC
    # --------------------------------------------------------
    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_picrust2sc_ec_metagenome" \
    CMD="metagenome_pipeline.py \
      --input ${BIOM_INPUT} \
      --marker marker_predicted_and_nsti.tsv.gz \
      --function EC_predicted.tsv.gz \
      --out_dir EC_metagenome_out \
      --max_nsti 2.0 \
      --strat_out" \
    "${RUN_IN_TMUX}"

fi


# ------------------------------------------------------------
# Status instructions
# ------------------------------------------------------------
echo
echo "============================================================"
echo " Metagenome prediction jobs submitted"
echo "============================================================"
echo
echo "[INFO] KO and EC are running as separate tmux jobs."
echo
echo "[INFO] 查詢任務摘要："
echo
echo "  JOB_TYPE=picrust_metagenome ./shell_tools/check_tmux_jobs.sh"
echo
echo "[INFO] 查詢任務詳細進度："
echo
echo "  MODE=all JOB_TYPE=picrust_metagenome ./shell_tools/check_tmux_jobs.sh"
echo
