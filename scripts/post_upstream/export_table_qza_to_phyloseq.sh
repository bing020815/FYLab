#!/usr/bin/env bash
set -euo pipefail

INPUT_QZA="${1:-table.qza}"
OUTDIR="${2:-phyloseq}"

if [ ! -f "${INPUT_QZA}" ]; then
    echo "[ERROR] 找不到輸入檔案：${INPUT_QZA}"
    exit 1
fi

if ! command -v biom >/dev/null 2>&1; then
    echo "[ERROR] 找不到 biom 指令"
    exit 1
fi

mkdir -p "${OUTDIR}"

echo "[INFO] 匯出 QIIME2 table.qza"
qiime tools export \
  --input-path "${INPUT_QZA}" \
  --output-path "${OUTDIR}"

if [ ! -f "${OUTDIR}/feature-table.biom" ]; then
    echo "[ERROR] 找不到輸出的 biom 檔：${OUTDIR}/feature-table.biom"
    exit 1
fi

echo "[INFO] 轉換 biom 為 otu_table.tsv"
biom convert \
  -i "${OUTDIR}/feature-table.biom" \
  -o "${OUTDIR}/otu_table.tsv" \
  --to-tsv

echo "[INFO] 已完成"
echo "[INFO] biom 檔案：${OUTDIR}/feature-table.biom"
echo "[INFO] tsv  檔案：${OUTDIR}/otu_table.tsv"
