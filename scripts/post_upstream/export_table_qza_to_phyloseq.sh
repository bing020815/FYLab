#!/usr/bin/env bash
set -euo pipefail

INPUT_QZA="${1:-table.qza}"
OUTDIR="${2:-phyloseq}"
QIIME_ENV_NAME="${QIIME_ENV_NAME:-qiime2-2023.2}"

if [ ! -f "${INPUT_QZA}" ]; then
    echo "[ERROR] 找不到輸入檔案：${INPUT_QZA}"
    exit 1
fi

# 判斷 qiime 指令來源
if command -v qiime >/dev/null 2>&1; then
    QIIME_CMD=(qiime)
elif command -v conda >/dev/null 2>&1; then
    QIIME_CMD=(conda run -n "${QIIME_ENV_NAME}" qiime)
else
    echo "[ERROR] 找不到 qiime 指令，也找不到 conda"
    echo "[ERROR] 請先 conda activate ${QIIME_ENV_NAME}，或安裝 QIIME2"
    exit 1
fi

# 判斷 biom 指令來源
if command -v biom >/dev/null 2>&1; then
    BIOM_CMD=(biom)
elif command -v conda >/dev/null 2>&1; then
    BIOM_CMD=(conda run -n "${QIIME_ENV_NAME}" biom)
else
    echo "[ERROR] 找不到 biom 指令，也找不到 conda"
    echo "[ERROR] 請先 conda activate ${QIIME_ENV_NAME}，或安裝 biom-format"
    exit 1
fi

mkdir -p "${OUTDIR}"

echo "[INFO] 輸入 QZA      = ${INPUT_QZA}"
echo "[INFO] 輸出資料夾   = ${OUTDIR}"
echo "[INFO] QIIME 環境   = ${QIIME_ENV_NAME}"

echo "[INFO] 匯出 QIIME2 feature table"
"${QIIME_CMD[@]}" tools export \
  --input-path "${INPUT_QZA}" \
  --output-path "${OUTDIR}"

if [ ! -f "${OUTDIR}/feature-table.biom" ]; then
    echo "[ERROR] 找不到輸出的 biom 檔案：${OUTDIR}/feature-table.biom"
    exit 1
fi

echo "[INFO] 將 biom 轉成 otu_table.tsv"
"${BIOM_CMD[@]}" convert \
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
