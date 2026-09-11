#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PICRUSt sequence placement launcher
#
# Supported environments:
#   picrust2
#   picrust2sc
#
# Usage:
#   ./shell_tools/run_picrust_place.sh --input raw
#   ./shell_tools/run_picrust_place.sh --input dehost
#   ./shell_tools/run_picrust_place.sh --input dehost --cores 4
#
# Output:
#   picrust/<environment>/out.tre
#   picrust/<environment>/intermediate/place_seqs/
# ============================================================


PROJECT_DIR="."
INPUT_MODE=""
CORES=2


usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_picrust_place.sh --input MODE [options]

Required:
  --input raw|dehost

Options:
  --cores N
      CPU cores used by place_seqs.py
      Default: 2

  --project-dir DIR
      Project root
      Default: .

Examples:
  conda activate picrust2
  ./shell_tools/run_picrust_place.sh --input dehost --cores 4

  conda activate picrust2sc
  ./shell_tools/run_picrust_place.sh --input raw --cores 4
EOF
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            INPUT_MODE="$2"
            shift 2
            ;;
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


if [[ -z "${INPUT_MODE}" ]]; then
    echo "[ERROR] --input raw|dehost is required"
    exit 1
fi

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
        echo "Activate:"
        echo "  conda activate picrust2"
        echo "or"
        echo "  conda activate picrust2sc"
        exit 1
        ;;
esac


# ============================================================
# Paths
# ============================================================

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"

PICRUST_ROOT="${PROJECT_DIR}/picrust"
PICRUST_OUT="${PICRUST_ROOT}/${METHOD}"

TREE="${PICRUST_OUT}/out.tre"
INTERMEDIATE="${PICRUST_OUT}/intermediate/place_seqs"


case "${INPUT_MODE}" in
    raw)
        FASTA="${PROJECT_DIR}/phyloseq/dna-sequences.fasta"
        ;;
    dehost)
        FASTA="${PROJECT_DIR}/phyloseq/dehost_output/dehost_dna-sequences.fasta"
        ;;
    *)
        echo "[ERROR] --input must be raw or dehost"
        exit 1
        ;;
esac


# ============================================================
# Validate
# ============================================================

if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] Missing executable:"
    echo "  ${RUN_IN_TMUX}"
    exit 1
fi

if [[ ! -f "${FASTA}" ]]; then
    echo "[ERROR] FASTA not found:"
    echo "  ${FASTA}"
    exit 1
fi

if ! command -v place_seqs.py >/dev/null 2>&1; then
    echo "[ERROR] place_seqs.py not found"
    echo "[INFO] Current environment = ${CURRENT_ENV}"
    exit 1
fi


mkdir -p "${PICRUST_OUT}"


echo "============================================================"
echo " PICRUSt sequence placement"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] Method      : ${METHOD}"
echo "[INFO] Input mode  : ${INPUT_MODE}"
echo "[INFO] FASTA       : ${FASTA}"
echo "[INFO] Output tree : ${TREE}"
echo "[INFO] Cores       : ${CORES}"
echo "============================================================"


JOB_TYPE=picrust_place \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${INPUT_MODE}_${METHOD}_place" \
PRE_CMD="rm -rf '${INTERMEDIATE}' && \
         rm -f '${TREE}' && \
         mkdir -p '${PICRUST_OUT}/intermediate'" \
CMD="place_seqs.py \
  -s '${FASTA}' \
  -o '${TREE}' \
  -p ${CORES} \
  --intermediate '${INTERMEDIATE}'" \
"${RUN_IN_TMUX}"


echo
echo "[INFO] Job submitted."
echo
echo "Check:"
echo "  MODE=latest JOB_TYPE=picrust_place ./shell_tools/check_tmux_jobs.sh"
echo
