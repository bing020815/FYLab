#!/usr/bin/env bash
set -euo pipefail

INPUT_QZA="${1:-table.qza}"
OUTDIR="${2:-phyloseq}"
QIIME_ENV_NAME="${QIIME_ENV_NAME:-qiime2-2023.2}"

if [ ! -f "${INPUT_QZA}" ]; then
    echo "[ERROR] 找不到輸入檔案：${INPUT_QZA}"
    exit 1
fi

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

mkdir -p "${OUTDIR}"

echo "[INFO] 輸入 QZA      = ${INPUT_QZA}"
echo "[INFO] 輸出資料夾   = ${OUTDIR}"
echo "[INFO] 目前環境     = ${CONDA_DEFAULT_ENV:-unknown}"

echo "[INFO] 匯出 QIIME2 feature table"
qiime tools export \
  --input-path "${INPUT_QZA}" \
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

echo
echo "[INFO] 已完成"
echo "[INFO] biom 檔案 = ${OUTDIR}/feature-table.biom"
echo "[INFO] tsv 檔案  = ${OUTDIR}/otu_table.tsv"
