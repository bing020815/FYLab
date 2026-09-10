#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PICRUSt QC
#
# Usage:
#   ./check_picrust_qc.sh
#
# or:
#   ./check_picrust_qc.sh /path/to/project
#
# Supported Conda environments:
#   picrust2
#   picrust2sc
#
# Output:
#   <project>/picrust2/qc/*
#   <project>/picrust2sc/qc/*
# ============================================================


# ============================================================
# Project path
# ============================================================
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"


# ============================================================
# Detect PICRUSt environment
# ============================================================
CURRENT_ENV="${CONDA_DEFAULT_ENV:-}"

case "${CURRENT_ENV}" in
    picrust2)
        PICRUST_VERSION="picrust2"
        ;;

    picrust2sc)
        PICRUST_VERSION="picrust2sc"
        ;;

    *)
        echo "[ERROR] 無法判斷 PICRUSt 版本"
        echo "[ERROR] 目前 Conda environment = ${CURRENT_ENV:-<none>}"
        echo
        echo "[ERROR] 請先啟用支援的環境："
        echo "  conda activate picrust2"
        echo "  conda activate picrust2sc"
        exit 1
        ;;
esac


# ============================================================
# Paths
# ============================================================
PICRUST_DIR="${PROJECT_DIR}/${PICRUST_VERSION}"
QC_DIR="${PICRUST_DIR}/qc"

NSTI_GZ="${PROJECT_DIR}/marker_predicted_and_nsti.tsv.gz"

DEHOST_OTU="${PROJECT_DIR}/phyloseq/filtered_host/dehost_otu_table.tsv"
RAW_OTU="${PROJECT_DIR}/phyloseq/otu_table.tsv"

mkdir -p "${QC_DIR}"


# ============================================================
# Detect abundance table
# ============================================================
if [ -f "${DEHOST_OTU}" ]; then
    MODE="dehost"
    OTU_TABLE="${DEHOST_OTU}"

elif [ -f "${RAW_OTU}" ]; then
    MODE="raw"
    OTU_TABLE="${RAW_OTU}"

else
    echo "[ERROR] 找不到可用的 abundance table"
    echo "[ERROR] 請確認以下檔案至少存在一個："
    echo "  - ${DEHOST_OTU}"
    echo "  - ${RAW_OTU}"
    exit 1
fi


# ============================================================
# Check NSTI input
# ============================================================
if [ ! -f "${NSTI_GZ}" ]; then
    echo "[ERROR] 找不到 NSTI prediction："
    echo "  ${NSTI_GZ}"
    exit 1
fi


# ============================================================
# Output files
# ============================================================
TOTAL_ABUNDANCE_TSV="${QC_DIR}/total_abundance.tsv"
NSTI_TSV="${QC_DIR}/nsti.tsv"
NSTI_ONLY_TSV="${QC_DIR}/nsti_only.tsv"
NSTI_MERGED_TSV="${QC_DIR}/nsti_merged.tsv"
WEIGHTED_NSTI_TXT="${QC_DIR}/weighted_nsti.txt"


# ============================================================
# Summary
# ============================================================
echo
echo "============================================================"
echo " PICRUSt QC"
echo "============================================================"
echo "[INFO] PROJECT_DIR     = ${PROJECT_DIR}"
echo "[INFO] CONDA_ENV       = ${CURRENT_ENV}"
echo "[INFO] PICRUST_VERSION = ${PICRUST_VERSION}"
echo "[INFO] MODE            = ${MODE}"
echo "[INFO] OTU_TABLE       = ${OTU_TABLE}"
echo "[INFO] NSTI_GZ         = ${NSTI_GZ}"
echo "[INFO] QC_DIR          = ${QC_DIR}"
echo "============================================================"
echo


# ============================================================
# Step 1
# Calculate total abundance for each ASV
# ============================================================
echo "[INFO] Step 1. 從 abundance table 計算每個 ASV 的總 abundance"

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


if [ ! -s "${TOTAL_ABUNDANCE_TSV}" ]; then
    echo "[ERROR] total_abundance.tsv 為空："
    echo "  ${TOTAL_ABUNDANCE_TSV}"
    exit 1
fi


# ============================================================
# Step 2
# Extract ASV and NSTI
# ============================================================
echo "[INFO] Step 2. 解壓 NSTI 並擷取 ASV 與 NSTI"

zcat "${NSTI_GZ}" > "${NSTI_TSV}"


awk -F'\t' '
NR == 1 {
    next
}
{
    print $1 "\t" $3
}
' "${NSTI_TSV}" > "${NSTI_ONLY_TSV}"


if [ ! -s "${NSTI_ONLY_TSV}" ]; then
    echo "[ERROR] nsti_only.tsv 為空："
    echo "  ${NSTI_ONLY_TSV}"
    exit 1
fi


# ============================================================
# Step 3
# Merge abundance and NSTI
# ============================================================
echo "[INFO] Step 3. 合併 abundance 與 NSTI"

join -t $'\t' \
    <(sort "${TOTAL_ABUNDANCE_TSV}") \
    <(sort "${NSTI_ONLY_TSV}") \
    > "${NSTI_MERGED_TSV}"


if [ ! -s "${NSTI_MERGED_TSV}" ]; then
    echo "[ERROR] nsti_merged.tsv 為空："
    echo "  ${NSTI_MERGED_TSV}"
    echo
    echo "[ERROR] 可能原因："
    echo "  abundance table 與 NSTI prediction 的 ASV ID 無法對應"
    exit 1
fi


# ============================================================
# Step 4
# Calculate weighted NSTI
# ============================================================
echo "[INFO] Step 4. 計算 weighted NSTI"

WEIGHTED_NSTI=$(
    awk -F'\t' '
    {
        num += $2 * $3
        den += $2
    }

    END {
        if (den == 0) {
            print "NA"
        } else {
            printf "%.6f\n", num / den
        }
    }
    ' "${NSTI_MERGED_TSV}"
)


if [ "${WEIGHTED_NSTI}" = "NA" ]; then
    echo "[ERROR] denominator 為 0，無法計算 weighted NSTI"
    exit 1
fi


echo "${WEIGHTED_NSTI}" > "${WEIGHTED_NSTI_TXT}"


# ============================================================
# Step 5
# QC interpretation
# ============================================================
echo "[INFO] Step 5. 判定 QC 等級"

QC_LEVEL=$(
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
)


QC_DESC=$(
    awk -v x="${WEIGHTED_NSTI}" '
    BEGIN {
        if (x < 0.05) {
            print "預測非常可靠，人類腸道常見"
        } else if (x < 0.10) {
            print "預測可信度良好，可用於功能路徑分析"
        } else if (x < 0.15) {
            print "部分 ASV 缺乏近親基因組，需謹慎解讀"
        } else {
            print "預測可信度偏低，reference genomes 涵蓋面不足"
        }
    }
    '
)


# ============================================================
# Final report
# ============================================================
echo
echo "============================================================"
echo " ${PICRUST_VERSION} Weighted NSTI QC"
echo "============================================================"
echo "[INFO] Weighted NSTI = ${WEIGHTED_NSTI}"
echo "[INFO] QC Level      = ${QC_LEVEL}"
echo "[INFO] 說明           = ${QC_DESC}"
echo
echo "[INFO] 輸出檔案："
echo "[INFO] total_abundance.tsv = ${TOTAL_ABUNDANCE_TSV}"
echo "[INFO] nsti.tsv            = ${NSTI_TSV}"
echo "[INFO] nsti_only.tsv       = ${NSTI_ONLY_TSV}"
echo "[INFO] nsti_merged.tsv     = ${NSTI_MERGED_TSV}"
echo "[INFO] weighted_nsti.txt   = ${WEIGHTED_NSTI_TXT}"
echo "============================================================"
