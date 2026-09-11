#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PICRUSt weighted NSTI QC
#
# Usage:
#   ./shell_tools/check_picrust_qc.sh
#   ./shell_tools/check_picrust_qc.sh --input dehost
#   ./shell_tools/check_picrust_qc.sh --input raw
#
# Output:
#   picrust/<environment>/qc/
# ============================================================


PROJECT_DIR="."
INPUT_MODE="auto"


usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/check_picrust_qc.sh [options]

Options:
  --input auto|raw|dehost
      Default: auto

  --project-dir DIR
      Default: .
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
        echo "[ERROR] Activate picrust2 or picrust2sc first."
        exit 1
        ;;
esac


# ============================================================
# Paths
# ============================================================

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PICRUST_OUT="${PROJECT_DIR}/picrust/${METHOD}"
QC_DIR="${PICRUST_OUT}/qc"

NSTI_GZ="${PICRUST_OUT}/marker_predicted_and_nsti.tsv.gz"

DEHOST_OTU="${PROJECT_DIR}/phyloseq/dehost_output/dehost_otu_table.tsv"
RAW_OTU="${PROJECT_DIR}/phyloseq/otu_table.tsv"

mkdir -p "${QC_DIR}"


# ============================================================
# Select abundance table
# ============================================================

case "${INPUT_MODE}" in

    raw)
        OTU_TABLE="${RAW_OTU}"
        MODE="raw"
        ;;

    dehost)
        OTU_TABLE="${DEHOST_OTU}"
        MODE="dehost"
        ;;

    auto)
        if [[ -f "${DEHOST_OTU}" ]]; then
            OTU_TABLE="${DEHOST_OTU}"
            MODE="dehost"

        elif [[ -f "${RAW_OTU}" ]]; then
            OTU_TABLE="${RAW_OTU}"
            MODE="raw"

        else
            echo "[ERROR] No abundance table found."
            exit 1
        fi
        ;;

    *)
        echo "[ERROR] --input must be auto, raw or dehost"
        exit 1
        ;;
esac


if [[ ! -f "${OTU_TABLE}" ]]; then
    echo "[ERROR] Abundance table not found:"
    echo "  ${OTU_TABLE}"
    exit 1
fi

if [[ ! -f "${NSTI_GZ}" ]]; then
    echo "[ERROR] NSTI prediction not found:"
    echo "  ${NSTI_GZ}"
    exit 1
fi


# ============================================================
# Outputs
# ============================================================

TOTAL_ABUNDANCE_TSV="${QC_DIR}/total_abundance.tsv"
NSTI_TSV="${QC_DIR}/nsti.tsv"
NSTI_ONLY_TSV="${QC_DIR}/nsti_only.tsv"
NSTI_MERGED_TSV="${QC_DIR}/nsti_merged.tsv"
WEIGHTED_NSTI_TXT="${QC_DIR}/weighted_nsti.txt"


echo "============================================================"
echo " PICRUSt weighted NSTI QC"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] Input mode  : ${MODE}"
echo "[INFO] OTU table   : ${OTU_TABLE}"
echo "[INFO] NSTI        : ${NSTI_GZ}"
echo "[INFO] Output      : ${QC_DIR}"
echo "============================================================"


# ============================================================
# 1. ASV abundance
# ============================================================

awk -F'\t' '
NR <= 2 {
    next
}
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


# ============================================================
# 2. NSTI
# ============================================================

zcat "${NSTI_GZ}" > "${NSTI_TSV}"

awk -F'\t' '
NR == 1 {
    next
}
{
    print $1 "\t" $3
}
' "${NSTI_TSV}" > "${NSTI_ONLY_TSV}"


# ============================================================
# 3. Merge
# ============================================================

join -t $'\t' \
    <(sort "${TOTAL_ABUNDANCE_TSV}") \
    <(sort "${NSTI_ONLY_TSV}") \
    > "${NSTI_MERGED_TSV}"


if [[ ! -s "${NSTI_MERGED_TSV}" ]]; then
    echo "[ERROR] abundance and NSTI ASV IDs could not be matched"
    exit 1
fi


# ============================================================
# 4. Weighted NSTI
# ============================================================

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


# ============================================================
# 5. Interpretation
# ============================================================

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
echo "[INFO] Weighted NSTI = ${WEIGHTED_NSTI}"
echo "[INFO] QC Level      = ${QC_LEVEL}"
echo
echo "[INFO] Output:"
echo "  ${QC_DIR}"
echo "============================================================"
