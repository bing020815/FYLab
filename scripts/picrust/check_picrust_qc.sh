#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="."
INPUT_MODE=""

usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/check_picrust_qc.sh --input raw|dehost [options]

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
PICRUST_OUT="${PROJECT_DIR}/picrust/${METHOD}/${INPUT_MODE}"
PROVENANCE="${PICRUST_OUT}/provenance.txt"
QC_DIR="${PICRUST_OUT}/qc"
NSTI_GZ="${PICRUST_OUT}/marker_predicted_and_nsti.tsv.gz"

case "${INPUT_MODE}" in
    raw)
        OTU_TABLE="${PROJECT_DIR}/phyloseq/otu_table.tsv"
        ;;
    dehost)
        OTU_TABLE="${PROJECT_DIR}/phyloseq/dehost_output/dehost_otu_table.tsv"
        ;;
esac

validate_provenance() {
    if [[ ! -f "${PROVENANCE}" ]]; then
        echo "[ERROR] provenance.txt not found: ${PROVENANCE}"
        exit 1
    fi

    local p_method p_input p_otu
    p_method="$(grep '^method=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"
    p_input="$(grep '^input_mode=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"
    p_otu="$(grep '^source_otu_table=' "${PROVENANCE}" | head -n1 | cut -d= -f2- || true)"

    if [[ "${p_method}" != "${METHOD}" || "${p_input}" != "${INPUT_MODE}" ]]; then
        echo "[ERROR] Provenance mismatch"
        exit 1
    fi

    if [[ -n "${p_otu}" && "${p_otu}" != "${OTU_TABLE}" ]]; then
        echo "[ERROR] OTU source does not match provenance"
        exit 1
    fi
}

validate_provenance

if [[ ! -f "${OTU_TABLE}" ]]; then
    echo "[ERROR] Abundance table not found: ${OTU_TABLE}"
    exit 1
fi

if [[ ! -f "${NSTI_GZ}" ]]; then
    echo "[ERROR] NSTI prediction not found: ${NSTI_GZ}"
    exit 1
fi

mkdir -p "${QC_DIR}"

TOTAL_ABUNDANCE_TSV="${QC_DIR}/total_abundance.tsv"
NSTI_TSV="${QC_DIR}/nsti.tsv"
NSTI_ONLY_TSV="${QC_DIR}/nsti_only.tsv"
NSTI_MERGED_TSV="${QC_DIR}/nsti_merged.tsv"
WEIGHTED_NSTI_TXT="${QC_DIR}/weighted_nsti.txt"

echo "============================================================"
echo " PICRUSt weighted NSTI QC"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] Method      : ${METHOD}"
echo "[INFO] Input mode  : ${INPUT_MODE}"
echo "[INFO] OTU table   : ${OTU_TABLE}"
echo "[INFO] NSTI        : ${NSTI_GZ}"
echo "[INFO] Output      : ${QC_DIR}"
echo "============================================================"

awk -F'\t' '
NR <= 2 { next }
{
    sum = 0
    for (i = 2; i <= NF; i++) {
        sum += $i
    }
    print $1 "\t" sum
}
' "${OTU_TABLE}" > "${TOTAL_ABUNDANCE_TSV}"

if [[ ! -s "${TOTAL_ABUNDANCE_TSV}" ]]; then
    echo "[ERROR] Empty abundance output"
    exit 1
fi

zcat "${NSTI_GZ}" > "${NSTI_TSV}"

awk -F'\t' '
NR == 1 { next }
{ print $1 "\t" $3 }
' "${NSTI_TSV}" > "${NSTI_ONLY_TSV}"

join -t $'\t' \
    <(sort "${TOTAL_ABUNDANCE_TSV}") \
    <(sort "${NSTI_ONLY_TSV}") \
    > "${NSTI_MERGED_TSV}"

if [[ ! -s "${NSTI_MERGED_TSV}" ]]; then
    echo "[ERROR] abundance and NSTI ASV IDs could not be matched"
    exit 1
fi

WEIGHTED_NSTI="$(
    awk -F'\t' '
    {
        numerator += $2 * $3
        denominator += $2
    }
    END {
        if (denominator == 0) {
            print "NA"
        } else {
            printf "%.6f\n", numerator / denominator
        }
    }
    ' "${NSTI_MERGED_TSV}"
)"

if [[ "${WEIGHTED_NSTI}" == "NA" ]]; then
    echo "[ERROR] Weighted NSTI denominator = 0"
    exit 1
fi

echo "${WEIGHTED_NSTI}" > "${WEIGHTED_NSTI_TXT}"

QC_LEVEL="$(
    awk -v x="${WEIGHTED_NSTI}" '
    BEGIN {
        if (x < 0.05) {
            print "Excellent"
        } else if (x < 0.10) {
            print "Acceptable"
        } else if (x < 0.15) {
            print "Borderline"
        } else {
            print "Low reliability"
        }
    }
    '
)"

echo
echo "============================================================"
echo " ${METHOD} Weighted NSTI QC"
echo "============================================================"
echo "[INFO] Input mode    = ${INPUT_MODE}"
echo "[INFO] Weighted NSTI = ${WEIGHTED_NSTI}"
echo "[INFO] QC Level      = ${QC_LEVEL}"
echo "[INFO] Output        = ${QC_DIR}"
echo "============================================================"
