#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
RAW_DIR="${PROJECT_DIR}/raw_fastq"
SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"

if [ ! -d "${RAW_DIR}" ]; then
    echo "[ERROR] 找不到資料夾：${RAW_DIR}"
    exit 1
fi

FASTQ_COUNT=$(find "${RAW_DIR}" -maxdepth 1 -name "*.fastq.gz" | wc -l)

if [ "${FASTQ_COUNT}" -eq 0 ]; then
    echo "[ERROR] ${RAW_DIR} 內沒有 fastq.gz 檔案"
    exit 1
fi

echo -e "sample-id\tabsolute-filepath" > "${SAMPLES_TSV}"
echo -e "sample_name\tcondition" > "${METADATA_TSV}"

for f in "${RAW_DIR}"/*.fastq.gz; do
    base=$(basename "${f}")
    sample=$(echo "${base}" | sed 's/\.hifi_reads\.fastq\.gz$//')
    abs=$(realpath "${f}")

    echo -e "${sample}\t${abs}" >> "${SAMPLES_TSV}"
    echo -e "${sample}\tUnknown" >> "${METADATA_TSV}"
done

echo "[INFO] 已建立：${SAMPLES_TSV}"
echo "[INFO] 已建立：${METADATA_TSV}"
echo "[INFO] 請確認 metadata.tsv 的 condition 是否需要手動修改。"