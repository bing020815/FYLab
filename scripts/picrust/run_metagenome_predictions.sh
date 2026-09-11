#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="."
INPUT_MODE=""

usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_metagenome_predictions.sh --input raw|dehost [options]

Required:
  --input raw|dehost

Options:
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
PROVENANCE="${PICRUST_OUT}/provenance.txt"

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
esac

validate_provenance() {
    if [[ ! -f "${PROVENANCE}" ]]; then
        echo "[ERROR] provenance.txt not found: ${PROVENANCE}"
        exit 1
    fi

    local p_method p_input p_biom
    p_method="$(grep '^method=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"
    p_input="$(grep '^input_mode=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"
    p_biom="$(grep '^source_biom=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"

    if [[ "${p_method}" != "${METHOD}" || "${p_input}" != "${INPUT_MODE}" ]]; then
        echo "[ERROR] Provenance mismatch"
        exit 1
    fi

    if [[ -n "${p_biom}" && "${p_biom}" != "${BIOM_INPUT}" ]]; then
        echo "[ERROR] BIOM source does not match provenance"
        echo "[INFO] Provenance: ${p_biom}"
        echo "[INFO] Current   : ${BIOM_INPUT}"
        exit 1
    fi
}

if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] Missing executable: ${RUN_IN_TMUX}"
    exit 1
fi

validate_provenance

for f in "${BIOM_INPUT}" "${MARKER_FILE}" "${KO_FILE}" "${EC_FILE}"; do
    if [[ ! -f "${f}" ]]; then
        echo "[ERROR] Required file not found: ${f}"
        exit 1
    fi
done

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
echo "[INFO] Metagenome jobs submitted."
echo "Check:"
echo "  MODE=all JOB_TYPE=picrust_metagenome ./shell_tools/check_tmux_jobs.sh"
