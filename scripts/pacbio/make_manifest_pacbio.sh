#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

RAW_DIR="${PROJECT_DIR}/raw_fastq"
SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"

if [ ! -d "${RAW_DIR}" ]; then
    echo "[ERROR] 找不到資料夾：${RAW_DIR}"
    echo "[ERROR] 請先建立 raw_fastq/，並將 PacBio fastq 或 tar.gz 放入其中"
    exit 1
fi

extract_tar_archives() {
    mapfile -t TAR_FILES < <(
        find "${RAW_DIR}" -maxdepth 1 -type f \( -name "*.fastq.tar.gz" -o -name "*.tar.gz" \) | sort
    )

    if [ "${#TAR_FILES[@]}" -eq 0 ]; then
        return 0
    fi

    echo "[INFO] 偵測到 tar 壓縮檔，開始解壓縮"

    for tarf in "${TAR_FILES[@]}"; do
        base="$(basename "${tarf}")"
        stem="${base%.tar.gz}"
        outdir="${RAW_DIR}/extracted_${stem}"

        if [ -d "${outdir}" ]; then
            echo "[INFO] 已存在解壓縮資料夾，略過：${outdir}"
            continue
        fi

        mkdir -p "${outdir}"
        echo "[INFO] 解壓縮 ${base} -> ${outdir}"
        tar -xzf "${tarf}" -C "${outdir}"
    done
}

collect_fastq_files() {
    mapfile -t FASTQ_FILES < <(
        find "${RAW_DIR}" -type f \( -name "*.fastq.gz" -o -name "*.fastq" \) \
        ! -name "*.tar.gz" \
        | sort
    )
}

infer_sample_name() {
    local filepath="$1"
    local base
    base="$(basename "${filepath}")"

    base="${base%.hifi_reads.fastq.gz}"
    base="${base%.hifi_reads.fastq}"
    base="${base%.fastq.gz}"
    base="${base%.fastq}"

    printf '%s\n' "${base}"
}

extract_tar_archives
collect_fastq_files

if [ "${#FASTQ_FILES[@]}" -eq 0 ]; then
    echo "[ERROR] ${RAW_DIR} 內沒有可用的 fastq 檔案"
    echo "[ERROR] 支援：*.fastq、*.fastq.gz、*.fastq.tar.gz"
    exit 1
fi

echo -e "sample-id\tabsolute-filepath" > "${SAMPLES_TSV}"
echo -e "sample_name\tcondition" > "${METADATA_TSV}"

for f in "${FASTQ_FILES[@]}"; do
    sample="$(infer_sample_name "${f}")"
    abs="$(realpath "${f}")"

    echo -e "${sample}\t${abs}" >> "${SAMPLES_TSV}"
    echo -e "${sample}\tUnknown" >> "${METADATA_TSV}"
done

echo "[INFO] 已建立：${SAMPLES_TSV}"
echo "[INFO] 已建立：${METADATA_TSV}"
echo "[INFO] 共納入 ${#FASTQ_FILES[@]} 個 FASTQ 檔案"
echo "[INFO] 請確認 metadata.tsv 的 condition 是否需要手動修改。"
