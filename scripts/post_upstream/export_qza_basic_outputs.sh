#!/usr/bin/env bash
set -euo pipefail

TABLE_QZA="${1:-table.qza}"
TAXONOMY_QZA="${2:-taxonomy.qza}"
REPSEQS_QZA="${3:-rep-seqs.qza}"
OUTDIR="${4:-phyloseq}"
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

if [ ! -f "${TABLE_QZA}" ]; then
    echo "[ERROR] 找不到輸入檔案：${TABLE_QZA}"
    exit 1
fi

if [ ! -f "${TAXONOMY_QZA}" ]; then
    echo "[ERROR] 找不到輸入檔案：${TAXONOMY_QZA}"
    exit 1
fi

if [ ! -f "${REPSEQS_QZA}" ]; then
    echo "[ERROR] 找不到輸入檔案：${REPSEQS_QZA}"
    exit 1
fi

mkdir -p "${OUTDIR}"

echo "[INFO] 輸出資料夾 = ${OUTDIR}"
echo "[INFO] 目前環境   = ${CONDA_DEFAULT_ENV:-unknown}"

echo "[INFO] 匯出 table.qza"
qiime tools export \
  --input-path "${TABLE_QZA}" \
  --output-path "${OUTDIR}"

if [ ! -f "${OUTDIR}/feature-table.biom" ]; then
    echo "[ERROR] 找不到輸出的 biom 檔案：${OUTDIR}/feature-table.biom"
    exit 1
fi

echo "[INFO] 將 biom 轉成 otu_table.tsv"
biom convert \
  -i "${OUTDIR}/feature-table.biom" \
  -o "${OUTDIR}/otu_table.tsv" \
  --to-tsv

if [ ! -f "${OUTDIR}/otu_table.tsv" ]; then
    echo "[ERROR] 找不到輸出的 tsv 檔案：${OUTDIR}/otu_table.tsv"
    exit 1
fi

echo "[INFO] 匯出 taxonomy.qza"
qiime tools export \
  --input-path "${TAXONOMY_QZA}" \
  --output-path "${OUTDIR}"

if [ ! -f "${OUTDIR}/taxonomy.tsv" ]; then
    echo "[ERROR] 找不到輸出的 taxonomy.tsv：${OUTDIR}/taxonomy.tsv"
    exit 1
fi

echo "[INFO] 匯出 rep-seqs.qza"
qiime tools export \
  --input-path "${REPSEQS_QZA}" \
  --output-path "${OUTDIR}"

if [ ! -f "${OUTDIR}/dna-sequences.fasta" ]; then
    echo "[ERROR] 找不到輸出的 dna-sequences.fasta：${OUTDIR}/dna-sequences.fasta"
    exit 1
fi

echo
echo "[INFO] 已完成"
echo "[INFO] biom 檔案   = ${OUTDIR}/feature-table.biom"
echo "[INFO] otu table   = ${OUTDIR}/otu_table.tsv"
echo "[INFO] taxonomy    = ${OUTDIR}/taxonomy.tsv"
echo "[INFO] rep-seqs    = ${OUTDIR}/dna-sequences.fasta"
