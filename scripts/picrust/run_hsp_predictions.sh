#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="."
INPUT_MODE=""
CORES=2

usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_hsp_predictions.sh --input raw|dehost [options]

Required:
  --input raw|dehost

Options:
  --cores N
      CPU cores per HSP job
      Default: 2

  --project-dir DIR
      Project root
      Default: .
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            INPUT_MODE="${2:-}"
            shift 2
            ;;
        --cores)
            CORES="${2:-}"
            shift 2
            ;;
        --project-dir)
            PROJECT_DIR="${2:-}"
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

if [[ "${INPUT_MODE}" != "raw" && "${INPUT_MODE}" != "dehost" ]]; then
    echo "[ERROR] --input raw|dehost is required"
    exit 1
fi

if ! [[ "${CORES}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --cores must be a positive integer"
    exit 1
fi

CURRENT_ENV="${CONDA_DEFAULT_ENV:-}"

case "${CURRENT_ENV}" in
    picrust2)
        METHOD="picrust2"
        ;;
    picrust2sc)
        METHOD="picrust2sc"
        ;;
    *)
        echo "[ERROR] Activate picrust2 or picrust2sc first."
        exit 1
        ;;
esac

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"

PICRUST_OUT="${PROJECT_DIR}/picrust/${METHOD}/${INPUT_MODE}"
TREE="${PICRUST_OUT}/out.tre"
PROVENANCE="${PICRUST_OUT}/provenance.txt"

MARKER_OUT="${PICRUST_OUT}/marker_predicted_and_nsti.tsv.gz"
KO_OUT="${PICRUST_OUT}/KO_predicted.tsv.gz"
EC_OUT="${PICRUST_OUT}/EC_predicted.tsv.gz"

validate_provenance() {
    if [[ ! -f "${PROVENANCE}" ]]; then
        echo "[ERROR] provenance.txt not found: ${PROVENANCE}"
        echo "[INFO] Run run_picrust_place.sh --input ${INPUT_MODE} first."
        exit 1
    fi

    local p_method p_input
    p_method="$(grep '^method=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"
    p_input="$(grep '^input_mode=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"

    if [[ "${p_method}" != "${METHOD}" || "${p_input}" != "${INPUT_MODE}" ]]; then
        echo "[ERROR] Provenance mismatch"
        echo "[INFO] Expected method=${METHOD}, input_mode=${INPUT_MODE}"
        echo "[INFO] Found    method=${p_method:-NA}, input_mode=${p_input:-NA}"
        exit 1
    fi
}

if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] Missing executable: ${RUN_IN_TMUX}"
    exit 1
fi

validate_provenance

if [[ ! -f "${TREE}" ]]; then
    echo "[ERROR] Placement tree not found: ${TREE}"
    exit 1
fi

if ! command -v hsp.py >/dev/null 2>&1; then
    echo "[ERROR] hsp.py not found"
    exit 1
fi

echo "============================================================"
echo " PICRUSt hidden-state prediction"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] Method      : ${METHOD}"
echo "[INFO] Input mode  : ${INPUT_MODE}"
echo "[INFO] PICRUSt dir : ${PICRUST_OUT}"
echo "[INFO] Tree        : ${TREE}"
echo "[INFO] Cores/job   : ${CORES}"
echo "[INFO] Maximum     : 3 jobs x ${CORES} cores"
echo "============================================================"

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${INPUT_MODE}_${METHOD}_hsp_marker_nsti" \
CMD="hsp.py -i 16S -t '${TREE}' -o '${MARKER_OUT}' -p ${CORES} -n" \
"${RUN_IN_TMUX}"

sleep 1

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${INPUT_MODE}_${METHOD}_hsp_ko" \
CMD="hsp.py -i KO -t '${TREE}' -o '${KO_OUT}' -p ${CORES}" \
"${RUN_IN_TMUX}"

sleep 1

JOB_TYPE=picrust_hsp \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${INPUT_MODE}_${METHOD}_hsp_ec" \
CMD="hsp.py -i EC -t '${TREE}' -o '${EC_OUT}' -p ${CORES}" \
"${RUN_IN_TMUX}"

echo
echo "[INFO] HSP jobs submitted."
echo "Check:"
echo "  MODE=all JOB_TYPE=picrust_hsp ./shell_tools/check_tmux_jobs.sh"
