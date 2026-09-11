#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="."
INPUT_MODE=""
CORES=2

usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_picrust_place.sh --input raw|dehost [options]

Required:
  --input raw|dehost

Options:
  --cores N
      CPU cores used by place_seqs.py
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
INTERMEDIATE="${PICRUST_OUT}/intermediate/place_seqs"
PROVENANCE="${PICRUST_OUT}/provenance.txt"

case "${INPUT_MODE}" in
    raw)
        FASTA="${PROJECT_DIR}/phyloseq/dna-sequences.fasta"
        BIOM="${PROJECT_DIR}/phyloseq/feature-table.biom"
        OTU_TABLE="${PROJECT_DIR}/phyloseq/otu_table.tsv"
        ;;
    dehost)
        FASTA="${PROJECT_DIR}/phyloseq/dehost_output/dehost_dna-sequences.fasta"
        BIOM="${PROJECT_DIR}/phyloseq/dehost_output/dehost_otu_table.biom"
        OTU_TABLE="${PROJECT_DIR}/phyloseq/dehost_output/dehost_otu_table.tsv"
        ;;
esac

if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] Missing executable: ${RUN_IN_TMUX}"
    exit 1
fi

if [[ ! -f "${FASTA}" ]]; then
    echo "[ERROR] FASTA not found: ${FASTA}"
    exit 1
fi

if ! command -v place_seqs.py >/dev/null 2>&1; then
    echo "[ERROR] place_seqs.py not found"
    exit 1
fi

mkdir -p "${PICRUST_OUT}"

cat > "${PROVENANCE}" <<EOF
method=${METHOD}
input_mode=${INPUT_MODE}
conda_env=${CURRENT_ENV}
source_fasta=${FASTA}
source_biom=${BIOM}
source_otu_table=${OTU_TABLE}
created_at=$(date '+%Y-%m-%d %H:%M:%S')
EOF

echo "============================================================"
echo " PICRUSt sequence placement"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] Method      : ${METHOD}"
echo "[INFO] Input mode  : ${INPUT_MODE}"
echo "[INFO] FASTA       : ${FASTA}"
echo "[INFO] Output dir  : ${PICRUST_OUT}"
echo "[INFO] Output tree : ${TREE}"
echo "[INFO] Provenance  : ${PROVENANCE}"
echo "[INFO] Cores       : ${CORES}"
echo "============================================================"

JOB_TYPE=picrust_place \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${INPUT_MODE}_${METHOD}_place" \
PRE_CMD="rm -rf '${INTERMEDIATE}' && rm -f '${TREE}' && mkdir -p '${PICRUST_OUT}/intermediate'" \
CMD="place_seqs.py \
  -s '${FASTA}' \
  -o '${TREE}' \
  -p ${CORES} \
  --intermediate '${INTERMEDIATE}'" \
"${RUN_IN_TMUX}"

echo
echo "[INFO] Job submitted."
echo "Check:"
echo "  MODE=latest JOB_TYPE=picrust_place ./shell_tools/check_tmux_jobs.sh"
