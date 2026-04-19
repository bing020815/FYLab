#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PHYLOSEQ_DIR="${PROJECT_DIR}/phyloseq"
HOST_FILTER_DIR="${PHYLOSEQ_DIR}/host_filter"
FILTERED_HOST_DIR="${PHYLOSEQ_DIR}/filtered_host"

NONHOST_FASTA="${HOST_FILTER_DIR}/nonhost.fasta"
TAXONOMY_TSV="${PHYLOSEQ_DIR}/taxonomy.tsv"
OTU_TABLE_TSV="${PHYLOSEQ_DIR}/otu_table.tsv"

KEEP_IDS_TXT="${FILTERED_HOST_DIR}/keep_ids.txt"
DEHOST_TAXONOMY_TSV="${FILTERED_HOST_DIR}/dehost_taxonomy.tsv"
DEHOST_OTU_TABLE_TSV="${FILTERED_HOST_DIR}/dehost_otu_table.tsv"

if [ ! -f "${NONHOST_FASTA}" ]; then
    echo "[ERROR] 找不到 nonhost fasta：${NONHOST_FASTA}"
    echo "[ERROR] 請先執行 dehost 序列過濾步驟，產生 nonhost.fasta"
    exit 1
fi

if [ ! -f "${TAXONOMY_TSV}" ]; then
    echo "[ERROR] 找不到 taxonomy.tsv：${TAXONOMY_TSV}"
    exit 1
fi

if [ ! -f "${OTU_TABLE_TSV}" ]; then
    echo "[ERROR] 找不到 otu_table.tsv：${OTU_TABLE_TSV}"
    exit 1
fi

mkdir -p "${FILTERED_HOST_DIR}"

echo "[INFO] Step 1. 從 nonhost.fasta 建立 keep_ids.txt"
grep '^>' "${NONHOST_FASTA}" | sed 's/^>//' > "${KEEP_IDS_TXT}"

if [ ! -s "${KEEP_IDS_TXT}" ]; then
    echo "[ERROR] keep_ids.txt 為空，請確認 nonhost.fasta 是否有保留序列"
    exit 1
fi

echo "[INFO] Step 2. 產生 dehost_taxonomy.tsv"
awk 'FNR==NR {keep[$1]; next} FNR==1 || $1 in keep' \
    "${KEEP_IDS_TXT}" \
    "${TAXONOMY_TSV}" \
    > "${DEHOST_TAXONOMY_TSV}"

if [ ! -f "${DEHOST_TAXONOMY_TSV}" ]; then
    echo "[ERROR] 建立失敗：${DEHOST_TAXONOMY_TSV}"
    exit 1
fi

echo "[INFO] Step 3. 產生 dehost_otu_table.tsv"
awk 'FNR==NR {keep[$1]; next} FNR<=2 || $1 in keep' \
    "${KEEP_IDS_TXT}" \
    "${OTU_TABLE_TSV}" \
    > "${DEHOST_OTU_TABLE_TSV}"

if [ ! -f "${DEHOST_OTU_TABLE_TSV}" ]; then
    echo "[ERROR] 建立失敗：${DEHOST_OTU_TABLE_TSV}"
    exit 1
fi

echo "[INFO] Step 4. 顯示結果摘要"
echo "[INFO] keep_ids.txt          = ${KEEP_IDS_TXT}"
echo "[INFO] dehost_taxonomy.tsv   = ${DEHOST_TAXONOMY_TSV}"
echo "[INFO] dehost_otu_table.tsv  = ${DEHOST_OTU_TABLE_TSV}"

echo
echo "[INFO] 已完成 filtered_host 表格過濾"
