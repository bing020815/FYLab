#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

TABLE_QZA="${PROJECT_DIR}/table.qza"
REPSEQS_QZA="${PROJECT_DIR}/rep-seqs.qza"
TAXONOMY_SOURCE_TXT="${PROJECT_DIR}/taxonomy_source.txt"

OUTDIR_NAME="${OUTDIR_NAME:-phyloseq}"
OUTDIR="${PROJECT_DIR}/${OUTDIR_NAME}"

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

if [ ! -f "${REPSEQS_QZA}" ]; then
    echo "[ERROR] 找不到輸入檔案：${REPSEQS_QZA}"
    exit 1
fi

if [ ! -f "${TAXONOMY_SOURCE_TXT}" ]; then
    echo "[ERROR] 找不到 taxonomy_source.txt：${TAXONOMY_SOURCE_TXT}"
    exit 1
fi

read_taxonomy_source_value() {
    local key="$1"
    grep "^${key}=" "${TAXONOMY_SOURCE_TXT}" 2>/dev/null | head -n 1 | cut -d'=' -f2-
}

TAXONOMY_MODE="$(read_taxonomy_source_value "taxonomy_mode")"
TAXONOMY_SOURCE_TYPE="$(read_taxonomy_source_value "taxonomy_source_type")"
TAXONOMY_SOURCE_FILE="$(read_taxonomy_source_value "taxonomy_source_file")"

if [ -z "${TAXONOMY_MODE}" ]; then
    echo "[ERROR] taxonomy_source.txt 缺少 taxonomy_mode"
    exit 1
fi

if [ -z "${TAXONOMY_SOURCE_FILE}" ]; then
    echo "[ERROR] taxonomy_source.txt 缺少 taxonomy_source_file"
    exit 1
fi

TAXONOMY_INPUT="${PROJECT_DIR}/${TAXONOMY_SOURCE_FILE}"

mkdir -p "${OUTDIR}"

echo "[INFO] PROJECT_DIR           = ${PROJECT_DIR}"
echo "[INFO] 輸出資料夾            = ${OUTDIR}"
echo "[INFO] 目前環境              = ${CONDA_DEFAULT_ENV:-unknown}"
echo "[INFO] TAXONOMY_MODE         = ${TAXONOMY_MODE}"
echo "[INFO] TAXONOMY_SOURCE_TYPE  = ${TAXONOMY_SOURCE_TYPE}"
echo "[INFO] TAXONOMY_SOURCE_FILE  = ${TAXONOMY_SOURCE_FILE}"

if [ ! -f "${TAXONOMY_INPUT}" ]; then
    echo "[ERROR] 找不到 taxonomy 來源檔案：${TAXONOMY_INPUT}"
    if [ "${TAXONOMY_MODE}" = "fylab" ]; then
        echo "[ERROR] FYLab 模式下，請先完成 classifier，產生 ${TAXONOMY_SOURCE_FILE}"
    fi
    exit 1
fi

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

echo "[INFO] 匯出 rep-seqs.qza"
qiime tools export \
  --input-path "${REPSEQS_QZA}" \
  --output-path "${OUTDIR}"

if [ ! -f "${OUTDIR}/dna-sequences.fasta" ]; then
    echo "[ERROR] 找不到輸出的 dna-sequences.fasta：${OUTDIR}/dna-sequences.fasta"
    exit 1
fi

case "${TAXONOMY_INPUT}" in
    *.qza)
        echo "[INFO] taxonomy 來源為 qza，先匯出成 taxonomy.tsv"
        TAX_EXPORT_DIR="${OUTDIR}/taxonomy_export_tmp"
        rm -rf "${TAX_EXPORT_DIR}"
        mkdir -p "${TAX_EXPORT_DIR}"

        qiime tools export \
          --input-path "${TAXONOMY_INPUT}" \
          --output-path "${TAX_EXPORT_DIR}"

        if [ ! -f "${TAX_EXPORT_DIR}/taxonomy.tsv" ]; then
            echo "[ERROR] 從 ${TAXONOMY_INPUT} 匯出後找不到 taxonomy.tsv"
            exit 1
        fi

        cp "${TAX_EXPORT_DIR}/taxonomy.tsv" "${OUTDIR}/taxonomy.tsv"
        rm -rf "${TAX_EXPORT_DIR}"
        ;;
    *.tsv)
        echo "[INFO] taxonomy 來源為 tsv，直接複製"
        cp "${TAXONOMY_INPUT}" "${OUTDIR}/taxonomy.tsv"
        ;;
    *)
        echo "[ERROR] 不支援的 taxonomy 來源格式：${TAXONOMY_INPUT}"
        echo "[ERROR] 目前僅支援 .qza 或 .tsv"
        exit 1
        ;;
esac

if [ ! -f "${OUTDIR}/taxonomy.tsv" ]; then
    echo "[ERROR] 找不到輸出的 taxonomy.tsv：${OUTDIR}/taxonomy.tsv"
    exit 1
fi

cat > "${OUTDIR}/taxonomy_source.txt" <<EOF
taxonomy_mode=${TAXONOMY_MODE}
taxonomy_source_type=${TAXONOMY_SOURCE_TYPE}
taxonomy_source_file=${TAXONOMY_SOURCE_FILE}
EOF

echo
echo "[INFO] 已完成"
echo "[INFO] biom 檔案      = ${OUTDIR}/feature-table.biom"
echo "[INFO] otu_table.tsv  = ${OUTDIR}/otu_table.tsv"
echo "[INFO] rep-seqs fasta = ${OUTDIR}/dna-sequences.fasta"
echo "[INFO] taxonomy.tsv   = ${OUTDIR}/taxonomy.tsv"
echo "[INFO] source 記錄    = ${OUTDIR}/taxonomy_source.txt"
