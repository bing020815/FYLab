#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PICRUSt hidden-state prediction
#
# Parallel:
#   1. Marker + NSTI
#   2. KO
#   3. EC
#
# Output:
#   picrust/<environment>/
# ============================================================


PROJECT_DIR="."
CORES=2


usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_hsp_predictions.sh [options]

Options:
  --cores N
      CPU cores per HSP job
      Default: 2

  --project-dir DIR
      Project root
      Default: .

Example:
  ./shell_tools/run_hsp_predictions.sh --cores 4
EOF
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --cores)
            CORES="$2"
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


if ! [[ "${CORES}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --cores must be a positive integer"
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
        echo "Activate picrust2 or picrust2sc first."
        exit 1
        ;;
esac


# ============================================================
# Paths
# ============================================================

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"
CHECK_TMUX="${PROJECT_DIR}/shell_tools/check_tmux_jobs.sh"

PICRUST_OUT="${PROJECT_DIR}/picrust/${METHOD}"

TREE="${PICRUST_OUT}/out.tre"

MARKER_OUT="${PICRUST_OUT}/marker_predicted_and_nsti.tsv.gz"
KO_OUT="${PICRUST_OUT}/KO_predicted.tsv.gz"
EC_OUT="${PICRUST_OUT}/EC_predicted.tsv.gz"


# ============================================================
# Validate
# ============================================================

if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] run_in_tmux.sh not found:"
    echo "  ${RUN_IN_TMUX}"
    exit 1
fi

if [[ ! -f "${TREE}" ]]; then
    echo "[ERROR] Placement tree not found:"
    echo "  ${TREE}"
    echo
    echo "[INFO] Run run_picrust_place.sh first."
    exit 1
fi

if ! command -v hsp.py >/dev/null 2>&1; then
    echo "[ERROR] hsp.py not found"
    echo "[INFO] Environment = ${CURRENT_ENV}"
    exit 1
fi


echo "============================================================"
echo " PICRUSt hidden-state prediction"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] PICRUSt dir : ${PICRUST_OUT}"
echo "[INFO] Tree        : ${TREE}"
echo "[INFO] Cores/job   : ${CORES}"
echo
echo "[INFO] Total maximum requested cores:"
echo "       3 jobs x ${CORES} cores"
echo "============================================================"


# ============================================================
# Marker + NSTI
# ============================================================

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${METHOD}_hsp_marker_nsti" \
CMD="hsp.py \
  -i 16S \
  -t '${TREE}' \
  -o '${MARKER_OUT}' \
  -p ${CORES} \
  -n" \
"${RUN_IN_TMUX}"

sleep 1


# ============================================================
# KO
# ============================================================

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${METHOD}_hsp_ko" \
CMD="hsp.py \
  -i KO \
  -t '${TREE}' \
  -o '${KO_OUT}' \
  -p ${CORES}" \
"${RUN_IN_TMUX}"

sleep 1


# ============================================================
# EC
# ============================================================

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${METHOD}_hsp_ec" \
CMD="hsp.py \
  -i EC \
  -t '${TREE}' \
  -o '${EC_OUT}' \
  -p ${CORES}" \
"${RUN_IN_TMUX}"


echo
echo "============================================================"
echo " HSP jobs submitted"
echo "============================================================"
echo "[INFO] Marker : ${MARKER_OUT}"
echo "[INFO] KO     : ${KO_OUT}"
echo "[INFO] EC     : ${EC_OUT}"
echo
echo "Check all HSP jobs:"
echo "  MODE=all JOB_TYPE=picrust_hsp ./shell_tools/check_tmux_jobs.sh"
echo
