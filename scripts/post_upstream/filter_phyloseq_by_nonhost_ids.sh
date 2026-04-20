#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PHYLOSEQ_DIR="${PROJECT_DIR}/phyloseq"
DEHOST_WORK_DIR="${PHYLOSEQ_DIR}/dehost_work"
DEHOST_OUTPUT_DIR="${PHYLOSEQ_DIR}/dehost_output"

NONHOST_FASTA="${DEHOST_WORK_DIR}/nonhost.fasta"
TAXONOMY_TSV="${PHYLOSEQ_DIR}/taxonomy.tsv"
OTU_TABLE_TSV="${PHYLOSEQ_DIR}/otu_table.tsv"

KEEP_IDS_TXT="${DEHOST_OUTPUT_DIR}/keep_ids.txt"
DEHOST_TAXONOMY_TSV="${DEHOST_OUTPUT_DIR}/dehost_taxonomy.tsv"
DEHOST_OTU_TABLE_TSV="${DEHOST_OUTPUT_DIR}/dehost_otu_table.tsv"

check_file() {
    local file="$1"
    local label="$2"

    if [ ! -f "${file}" ]; then
        echo "[ERROR] 找不到 ${label}：${file}"
        exit 1
    fi
}

main() {
    check_file "${NONHOST_FASTA}" "nonhost fasta"
    check_file "${TAXONOMY_TSV}" "taxonomy.tsv"
    check_file "${OTU_TABLE_TSV}" "otu_table.tsv"

    mkdir -p "${DEHOST_OUTPUT_DIR}"

    echo "[INFO] PROJECT_DIR         = ${PROJECT_DIR}"
    echo "[INFO] DEHOST_WORK_DIR     = ${DEHOST_WORK_DIR}"
    echo "[INFO] DEHOST_OUTPUT_DIR   = ${DEHOST_OUTPUT_DIR}"

    echo "[INFO] Step 1. 從 nonhost.fasta 建立 keep_ids.txt"
    grep '^>' "${NONHOST_FASTA}" | sed 's/^>//' > "${KEEP_IDS_TXT}"

    if [ ! -s "${KEEP_IDS_TXT}" ]; then
        echo "[ERROR] keep_ids.txt 為空，請確認 nonhost.fasta 是否仍有保留序列"
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
    echo "[INFO] 已完成 dehost_output 表格過濾"
}

main "$@"
