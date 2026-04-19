#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PHYLOSEQ_DIR="${PROJECT_DIR}/phyloseq"
FILTERED_HOST_DIR="${PHYLOSEQ_DIR}/filtered_host"

DEHOST_OTU_TSV="${FILTERED_HOST_DIR}/dehost_otu_table.tsv"
DEHOST_OTU_BIOM="${FILTERED_HOST_DIR}/dehost_otu_table.biom"
DEHOST_OTU_QZA="${FILTERED_HOST_DIR}/dehost_otu_table.qza"

DEHOST_TAXONOMY_TSV="${FILTERED_HOST_DIR}/dehost_taxonomy.tsv"
DEHOST_TAXONOMY_QZA="${FILTERED_HOST_DIR}/dehost_taxonomy.qza"

REPSEQS_QZA="${PROJECT_DIR}/rep-seqs.qza"
DEHOST_REPSEQS_QZA="${FILTERED_HOST_DIR}/dehost_rep_seqs.qza"

QIIME_ENV_NAME="${QIIME_ENV_NAME:-qiime2-2023.2}"

if ! command -v qiime >/dev/null 2>&1; then
    echo "[ERROR] 找不到 qiime 指令"
    echo "[ERROR] 請先啟用 QIIME2 環境，例如：conda activate ${QIIME_ENV_NAME}"
    exit 1
fi

if ! command -v biom >/dev/null 2>&1; then
    echo "[ERROR] 找不到 biom 指令"
    echo "[ERROR] 請先確認目前已啟用正確環境，例如：conda activate ${QIIME_ENV_NAME}"
    exit 1
fi

if [ ! -f "${DEHOST_OTU_TSV}" ]; then
    echo "[ERROR] 找不到 ${DEHOST_OTU_TSV}"
    exit 1
fi

if [ ! -f "${DEHOST_TAXONOMY_TSV}" ]; then
    echo "[ERROR] 找不到 ${DEHOST_TAXONOMY_TSV}"
    exit 1
fi

if [ ! -f "${REPSEQS_QZA}" ]; then
    echo "[ERROR] 找不到 ${REPSEQS_QZA}"
    exit 1
fi

mkdir -p "${FILTERED_HOST_DIR}"

echo "[INFO] Step 1. dehost_otu_table.tsv 轉成 biom"
biom convert \
  -i "${DEHOST_OTU_TSV}" \
  -o "${DEHOST_OTU_BIOM}" \
  --to-hdf5 \
  --table-type="OTU table"

if [ ! -f "${DEHOST_OTU_BIOM}" ]; then
    echo "[ERROR] 找不到輸出的 biom：${DEHOST_OTU_BIOM}"
    exit 1
fi

echo "[INFO] Step 2. biom 匯入為 QIIME2 table"
qiime tools import \
  --input-path "${DEHOST_OTU_BIOM}" \
  --type 'FeatureTable[Frequency]' \
  --input-format BIOMV210Format \
  --output-path "${DEHOST_OTU_QZA}"

if [ ! -f "${DEHOST_OTU_QZA}" ]; then
    echo "[ERROR] 找不到輸出的 qza：${DEHOST_OTU_QZA}"
    exit 1
fi

echo "[INFO] Step 3. 由 dehost table 過濾 rep-seqs.qza"
qiime feature-table filter-seqs \
  --i-data "${REPSEQS_QZA}" \
  --i-table "${DEHOST_OTU_QZA}" \
  --o-filtered-data "${DEHOST_REPSEQS_QZA}"

if [ ! -f "${DEHOST_REPSEQS_QZA}" ]; then
    echo "[ERROR] 找不到輸出的 dehost rep-seqs：${DEHOST_REPSEQS_QZA}"
    exit 1
fi

echo "[INFO] Step 4. 將 dehost_taxonomy.tsv 匯入為 QIIME2 taxonomy"
qiime tools import \
  --input-path "${DEHOST_TAXONOMY_TSV}" \
  --type 'FeatureData[Taxonomy]' \
  --input-format HeaderlessTSVTaxonomyFormat \
  --output-path "${DEHOST_TAXONOMY_QZA}"

if [ ! -f "${DEHOST_TAXONOMY_QZA}" ]; then
    echo "[ERROR] 找不到輸出的 dehost taxonomy qza：${DEHOST_TAXONOMY_QZA}"
    exit 1
fi

echo "[INFO] Step 5. 匯出 dehost rep-seqs fasta"
TMP_EXPORT_DIR="${FILTERED_HOST_DIR}/repseqs_export_tmp"
rm -rf "${TMP_EXPORT_DIR}"
mkdir -p "${TMP_EXPORT_DIR}"

qiime tools export \
  --input-path "${DEHOST_REPSEQS_QZA}" \
  --output-path "${TMP_EXPORT_DIR}"

if [ ! -f "${TMP_EXPORT_DIR}/dna-sequences.fasta" ]; then
    echo "[ERROR] 匯出後找不到 dna-sequences.fasta"
    exit 1
fi

cp "${TMP_EXPORT_DIR}/dna-sequences.fasta" "${FILTERED_HOST_DIR}/dehost_dna-sequences.fasta"
rm -rf "${TMP_EXPORT_DIR}"

echo
echo "[INFO] 已完成 dehost pathway 前期準備"
echo "[INFO] biom                 = ${DEHOST_OTU_BIOM}"
echo "[INFO] table.qza            = ${DEHOST_OTU_QZA}"
echo "[INFO] rep-seqs.qza         = ${DEHOST_REPSEQS_QZA}"
echo "[INFO] taxonomy.qza         = ${DEHOST_TAXONOMY_QZA}"
echo "[INFO] dna-sequences.fasta  = ${FILTERED_HOST_DIR}/dehost_dna-sequences.fasta"
