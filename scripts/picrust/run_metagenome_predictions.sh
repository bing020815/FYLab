#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PICRUSt metagenome prediction
#
# Supported:
#   picrust2
#   picrust2sc
#
# Parallel:
#   KO
#   EC
#
# Usage:
#   ./shell_tools/run_metagenome_predictions.sh --input raw
#   ./shell_tools/run_metagenome_predictions.sh --input dehost
# ============================================================


PROJECT_DIR="."
INPUT_MODE=""


usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_metagenome_predictions.sh --input MODE [options]

Required:
  --input raw|dehost

Options:
  --project-dir DIR
      Default: .

Examples:
  ./shell_tools/run_metagenome_predictions.sh --input dehost
  ./shell_tools/run_metagenome_predictions.sh --input raw
EOF
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            INPUT_MODE="$2"
            shift 2
            ;;
        --project-dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done


if [[ -z "${INPUT_MODE}" ]]; then
    echo "[ERROR] --input raw|dehost is required"
    exit 1
fi


# ============================================================
# Environment
# ============================================================

CURRENT_ENV="${CONDA_DEFAULT_ENV:-}"

case "${CURRENT_ENV}" in
    picrust2)
        METHOD="picrust2"
        ;;
    picrust2sc)
        METHOD="picrust2sc"
        ;;
    *)
        echo "[ERROR] Unsupported Conda environment: ${CURRENT_ENV:-<none>}"
        echo
        echo "Activate picrust2 or picrust2sc."
        exit 1
        ;;
esac


# ============================================================
# Project paths
# ============================================================

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"

PICRUST_OUT="${PROJECT_DIR}/picrust/${METHOD}"

MARKER_FILE="${PICRUST_OUT}/marker_predicted_and_nsti.tsv.gz"
KO_FILE="${PICRUST_OUT}/KO_predicted.tsv.gz"
EC_FILE="${PICRUST_OUT}/EC_predicted.tsv.gz"

KO_OUT="${PICRUST_OUT}/KO_metagenome_out"
EC_OUT="${PICRUST_OUT}/EC_metagenome_out"


case "${INPUT_MODE}" in
    raw)
        BIOM_INPUT="${PROJECT_DIR}/phyloseq/feature-table.biom"
        ;;
    dehost)
        BIOM_INPUT="${PROJECT_DIR}/phyloseq/dehost_output/dehost_otu_table.biom"
        ;;
    *)
        echo "[ERROR] --input must be raw or dehost"
        exit 1
        ;;
esac


# ============================================================
# Validate
# ============================================================

for f in \
    "${BIOM_INPUT}" \
    "${MARKER_FILE}" \
    "${KO_FILE}" \
    "${EC_FILE}"
do
    if [[ ! -f "${f}" ]]; then
        echo "[ERROR] Required file not found:"
        echo "  ${f}"
        exit 1
    fi
done


if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] Missing:"
    echo "  ${RUN_IN_TMUX}"
    exit 1
fi

if ! command -v metagenome_pipeline.py >/dev/null 2>&1; then
    echo "[ERROR] metagenome_pipeline.py not found"
    exit 1
fi


echo "============================================================"
echo " PICRUSt metagenome prediction"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] Method      : ${METHOD}"
echo "[INFO] Input mode  : ${INPUT_MODE}"
echo "[INFO] BIOM        : ${BIOM_INPUT}"
echo "[INFO] PICRUSt dir : ${PICRUST_OUT}"
echo "============================================================"


# ============================================================
# PICRUSt2
# ============================================================

if [[ "${METHOD}" == "picrust2" ]]; then

    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_${METHOD}_ko_metagenome" \
    CMD="metagenome_pipeline.py \
      -i '${BIOM_INPUT}' \
      -m '${MARKER_FILE}' \
      -f '${KO_FILE}' \
      -o '${KO_OUT}' \
      --strat_out" \
    "${RUN_IN_TMUX}"

    sleep 1

    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_${METHOD}_ec_metagenome" \
    CMD="metagenome_pipeline.py \
      -i '${BIOM_INPUT}' \
      -m '${MARKER_FILE}' \
      -f '${EC_FILE}' \
      -o '${EC_OUT}' \
      --strat_out" \
    "${RUN_IN_TMUX}"


# ============================================================
# PICRUSt2-SC
# ============================================================

else

    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_${METHOD}_ko_metagenome" \
    CMD="metagenome_pipeline.py \
      --input '${BIOM_INPUT}' \
      --marker '${MARKER_FILE}' \
      --function '${KO_FILE}' \
      --out_dir '${KO_OUT}' \
      --max_nsti 2.0 \
      --strat_out" \
    "${RUN_IN_TMUX}"

    sleep 1

    JOB_TYPE=picrust_metagenome \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${INPUT_MODE}_${METHOD}_ec_metagenome" \
    CMD="metagenome_pipeline.py \
      --input '${BIOM_INPUT}' \
      --marker '${MARKER_FILE}' \
      --function '${EC_FILE}' \
      --out_dir '${EC_OUT}' \
      --max_nsti 2.0 \
      --strat_out" \
    "${RUN_IN_TMUX}"

fi


echo
echo "============================================================"
echo " Metagenome jobs submitted"
echo "============================================================"
echo "[INFO] KO : ${KO_OUT}"
echo "[INFO] EC : ${EC_OUT}"
echo
echo "Check:"
echo "  MODE=all JOB_TYPE=picrust_metagenome ./shell_tools/check_tmux_jobs.sh"
echo
