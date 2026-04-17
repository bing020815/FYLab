#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

INPUT_DIR_NAME="${INPUT_DIR_NAME:-auto}"
MANIFEST_CSV="${PROJECT_DIR}/manifest.csv"
MANIFEST_TMP="${PROJECT_DIR}/manifest.tmp.csv"

RAW_DIR="${PROJECT_DIR}/raw_fastq"
TRIMMED_DIR="${PROJECT_DIR}/trimmed_fastq"

resolve_input_dir() {
    if [ "${INPUT_DIR_NAME}" != "auto" ]; then
        echo "${PROJECT_DIR}/${INPUT_DIR_NAME}"
        return
    fi

    shopt -s nullglob
    local trimmed_files=("${TRIMMED_DIR}"/*.fastq.gz)
    local raw_files=("${RAW_DIR}"/*.fastq.gz)
    shopt -u nullglob

    if [ -d "${TRIMMED_DIR}" ] && [ "${#trimmed_files[@]}" -gt 0 ]; then
        echo "${TRIMMED_DIR}"
    elif [ -d "${RAW_DIR}" ] && [ "${#raw_files[@]}" -gt 0 ]; then
        echo "${RAW_DIR}"
    else
        echo ""
    fi
}

TARGET_DIR="$(resolve_input_dir)"

if [ -z "${TARGET_DIR}" ]; then
    echo "[ERROR] 找不到可用的 FASTQ 資料夾"
    echo "[ERROR] 請確認 raw_fastq/ 或 trimmed_fastq/ 內至少有一個含有 .fastq.gz 檔案"
    exit 1
fi

if [ ! -d "${TARGET_DIR}" ]; then
    echo "[ERROR] 找不到指定資料夾：${TARGET_DIR}"
    exit 1
fi

shopt -s nullglob
FASTQ_FILES=("${TARGET_DIR}"/*.fastq.gz)
shopt -u nullglob

if [ "${#FASTQ_FILES[@]}" -eq 0 ]; then
    echo "[ERROR] ${TARGET_DIR} 內沒有 .fastq.gz 檔案"
    exit 1
fi

declare -A forward_map=()
declare -A reverse_map=()
declare -A sample_seen=()

declare -a unknown_files=()
declare -a missing_r1_samples=()
declare -a missing_r2_samples=()
declare -a duplicate_r1_samples=()
declare -a duplicate_r2_samples=()

for filepath in "${FASTQ_FILES[@]}"; do
    filename="$(basename "${filepath}")"

    if [[ "${filename}" =~ ^(.+)_R1(_[0-9]+)?(_trimmed)?\.fastq\.gz$ ]]; then
        sample_id="${BASH_REMATCH[1]}"
        if [ -n "${forward_map[${sample_id}]:-}" ]; then
            duplicate_r1_samples+=("${sample_id}")
        else
            forward_map["${sample_id}"]="${filepath}"
        fi
        sample_seen["${sample_id}"]=1

    elif [[ "${filename}" =~ ^(.+)_R2(_[0-9]+)?(_trimmed)?\.fastq\.gz$ ]]; then
        sample_id="${BASH_REMATCH[1]}"
        if [ -n "${reverse_map[${sample_id}]:-}" ]; then
            duplicate_r2_samples+=("${sample_id}")
        else
            reverse_map["${sample_id}"]="${filepath}"
        fi
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

if [ "${#duplicate_r1_samples[@]}" -gt 0 ]; then
    mapfile -t duplicate_r1_samples < <(printf '%s\n' "${duplicate_r1_samples[@]}" | sort -u)
fi
if [ "${#duplicate_r2_samples[@]}" -gt 0 ]; then
    mapfile -t duplicate_r2_samples < <(printf '%s\n' "${duplicate_r2_samples[@]}" | sort -u)
fi

duplicate_r1_count="${#duplicate_r1_samples[@]}"
duplicate_r2_count="${#duplicate_r2_samples[@]}"

echo "[INFO] MiSeq manifest 檢查摘要"
echo "[INFO] PROJECT_DIR         = ${PROJECT_DIR}"
echo "[INFO] TARGET_DIR          = ${TARGET_DIR}"
echo "[INFO] TOTAL_FASTQ_FILES   = ${total_files}"
echo "[INFO] RECOGNIZED_SAMPLES  = ${recognized_samples}"
echo "[INFO] PAIRED_SAMPLES      = ${paired_count}"
echo "[INFO] UNPAIRED_SAMPLES    = ${unpaired_count}"
echo "[INFO] DUPLICATE_R1        = ${duplicate_r1_count}"
echo "[INFO] DUPLICATE_R2        = ${duplicate_r2_count}"
echo "[INFO] UNKNOWN_NAME_FILES  = ${unknown_count}"

if [ "${unknown_count}" -gt 0 ]; then
    echo
    echo "[ERROR] 以下檔名無法辨識為 R1/R2："
    printf '  - %s\n' "${unknown_files[@]}"
    echo "[ERROR] 支援格式例如："
    echo "  - sampleA_R1.fastq.gz"
    echo "  - sampleA_R2.fastq.gz"
    echo "  - sampleA_R1_001.fastq.gz"
    echo "  - sampleA_R2_123.fastq.gz"
    echo "  - sampleA_R1_trimmed.fastq.gz"
    echo "  - sampleA_R2_007_trimmed.fastq.gz"
fi

if [ "${duplicate_r1_count}" -gt 0 ]; then
    echo
    echo "[ERROR] 以下 sample 出現重複的 R1 檔案："
    printf '  - %s\n' "${duplicate_r1_samples[@]}"
fi

if [ "${duplicate_r2_count}" -gt 0 ]; then
    echo
    echo "[ERROR] 以下 sample 出現重複的 R2 檔案："
    printf '  - %s\n' "${duplicate_r2_samples[@]}"
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

if [ "${unknown_count}" -gt 0 ] || [ "${unpaired_count}" -gt 0 ] || [ "${duplicate_r1_count}" -gt 0 ] || [ "${duplicate_r2_count}" -gt 0 ]; then
    echo
    echo "[ERROR] 偵測到命名異常、sample 不成對，或 R1/R2 重複，未建立正式 manifest.csv"
    rm -f "${MANIFEST_TMP}"
    exit 1
fi

mv -f "${MANIFEST_TMP}" "${MANIFEST_CSV}"

echo
echo "[INFO] 已建立 manifest.csv"
echo "[INFO] MANIFEST_CSV        = ${MANIFEST_CSV}"
echo "[INFO] MANIFEST_ROWS       = $((paired_count * 2))"
