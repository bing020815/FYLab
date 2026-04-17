#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

TRIMMED_DIR="${PROJECT_DIR}/trimmed_fastq"
MANIFEST_CSV="${PROJECT_DIR}/manifest.csv"
MANIFEST_TMP="${PROJECT_DIR}/manifest.tmp.csv"

if [ ! -d "${TRIMMED_DIR}" ]; then
    echo "[ERROR] 找不到 trimmed_fastq 資料夾：${TRIMMED_DIR}"
    exit 1
fi

shopt -s nullglob
FASTQ_FILES=("${TRIMMED_DIR}"/*.fastq.gz)
shopt -u nullglob

if [ "${#FASTQ_FILES[@]}" -eq 0 ]; then
    echo "[ERROR] ${TRIMMED_DIR} 內沒有 .fastq.gz 檔案"
    exit 1
fi

declare -A forward_map
declare -A reverse_map
declare -A sample_seen
declare -a unknown_files
declare -a missing_r1_samples
declare -a missing_r2_samples

for filepath in "${FASTQ_FILES[@]}"; do
    filename="$(basename "${filepath}")"

    if [[ "${filename}" =~ ^(.+)_R1(_001)?\.fastq\.gz$ ]]; then
        sample_id="${BASH_REMATCH[1]}"
        forward_map["${sample_id}"]="${filepath}"
        sample_seen["${sample_id}"]=1
    elif [[ "${filename}" =~ ^(.+)_R2(_001)?\.fastq\.gz$ ]]; then
        sample_id="${BASH_REMATCH[1]}"
        reverse_map["${sample_id}"]="${filepath}"
        sample_seen["${sample_id}"]=1
    else
        unknown_files+=("${filename}")
    fi
done

mapfile -t sample_ids < <(printf '%s\n' "${!sample_seen[@]}" | sort)

total_files="${#FASTQ_FILES[@]}"
recognized_samples="${#sample_ids[@]}"
unknown_count="${#unknown_files[@]}"

paired_count=0
unpaired_count=0

echo "sample-id,absolute-filepath,direction" > "${MANIFEST_TMP}"

for sample_id in "${sample_ids[@]}"; do
    forward_path="${forward_map[${sample_id}]:-}"
    reverse_path="${reverse_map[${sample_id}]:-}"

    if [ -n "${forward_path}" ] && [ -n "${reverse_path}" ]; then
        echo "${sample_id},${forward_path},forward" >> "${MANIFEST_TMP}"
        echo "${sample_id},${reverse_path},reverse" >> "${MANIFEST_TMP}"
        paired_count=$((paired_count + 1))
    else
        unpaired_count=$((unpaired_count + 1))
        [ -z "${forward_path}" ] && missing_r1_samples+=("${sample_id}")
        [ -z "${reverse_path}" ] && missing_r2_samples+=("${sample_id}")
    fi
done

echo "[INFO] MiSeq manifest 檢查摘要"
echo "[INFO] PROJECT_DIR         = ${PROJECT_DIR}"
echo "[INFO] TRIMMED_DIR         = ${TRIMMED_DIR}"
echo "[INFO] TOTAL_FASTQ_FILES   = ${total_files}"
echo "[INFO] RECOGNIZED_SAMPLES  = ${recognized_samples}"
echo "[INFO] PAIRED_SAMPLES      = ${paired_count}"
echo "[INFO] UNPAIRED_SAMPLES    = ${unpaired_count}"
echo "[INFO] UNKNOWN_NAME_FILES  = ${unknown_count}"

if [ "${unknown_count}" -gt 0 ]; then
    echo
    echo "[ERROR] 以下檔名無法辨識為 R1/R2："
    printf '  - %s\n' "${unknown_files[@]}"
    echo "[ERROR] 預期格式例如：sampleA_R1.fastq.gz 或 sampleA_R1_001.fastq.gz"
fi

if [ "${#missing_r1_samples[@]}" -gt 0 ]; then
    echo
    echo "[ERROR] 以下 sample 缺少 R1："
    printf '  - %s\n' "${missing_r1_samples[@]}"
fi

if [ "${#missing_r2_samples[@]}" -gt 0 ]; then
    echo
    echo "[ERROR] 以下 sample 缺少 R2："
    printf '  - %s\n' "${missing_r2_samples[@]}"
fi

if [ "${unknown_count}" -gt 0 ] || [ "${unpaired_count}" -gt 0 ]; then
    echo
    echo "[ERROR] 偵測到命名異常或 sample 不成對，未建立正式 manifest.csv"
    rm -f "${MANIFEST_TMP}"
    exit 1
fi

mv -f "${MANIFEST_TMP}" "${MANIFEST_CSV}"

echo
echo "[INFO] 已建立 manifest.csv"
echo "[INFO] MANIFEST_CSV        = ${MANIFEST_CSV}"
echo "[INFO] MANIFEST_ROWS       = $((paired_count * 2))"
