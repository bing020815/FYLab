#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  make_manifest_miseq.sh [PROJECT_DIR] [options]

Description:
  建立 MiSeq paired-end FASTQ 的 QIIME 2 manifest.csv。

  預設支援：
    Illumina / MiSeq style:
      sampleA_S1_L001_R1_001.fastq.gz
      sampleA_S1_L001_R2_001.fastq.gz
      sampleA_S1_L001_R1_trimmed.fastq.gz
      sampleA_S1_L001_R2_trimmed.fastq.gz

    Simple style:
      sampleA_R1.fastq.gz
      sampleA_R2.fastq.gz
      sampleA_R1_001.fastq.gz
      sampleA_R2_001.fastq.gz
      sampleA_R1_trimmed.fastq.gz
      sampleA_R2_trimmed.fastq.gz

  INPUT_DIR_NAME=auto 時：
    trimmed_fastq/ 有 FASTQ -> 優先使用 trimmed_fastq/
    否則使用 raw_fastq/

Arguments:
  PROJECT_DIR
      專案根目錄。預設為目前所在目錄。

Options:
  --remove STRING
      從自動辨識完成的 sample ID 額外移除指定固定字串。
      若 delimiter（例如 "_"、"-"）也不要保留，請包含在 STRING 中。
      可重複指定。

  -h, --help
      顯示此使用說明。

Examples:
  make_manifest_miseq.sh

  make_manifest_miseq.sh /path/to/project

  make_manifest_miseq.sh . --remove "_test"

  make_manifest_miseq.sh . \
      --remove "_test" \
      --remove "_batch1"

  INPUT_DIR_NAME=raw make_manifest_miseq.sh .

Example:
  ABC_test_S35_L001_R1_001.fastq.gz
  ABC_test_S35_L001_R2_001.fastq.gz

  make_manifest_miseq.sh . --remove "_test"

  sample-id:
  ABC

Output:
  PROJECT_DIR/manifest.csv
EOF
}

PROJECT_DIR=""
REMOVE_STRINGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --remove)
            if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
                echo "[ERROR] --remove 需要指定要移除的字串" >&2
                exit 1
            fi
            REMOVE_STRINGS+=("$2")
            shift 2
            ;;
        --*)
            echo "[ERROR] 未知參數：$1" >&2
            echo "[INFO] 使用 --help 查看使用方法" >&2
            exit 1
            ;;
        *)
            if [ -n "${PROJECT_DIR}" ]; then
                echo "[ERROR] 只能指定一個 PROJECT_DIR：$1" >&2
                exit 1
            fi
            PROJECT_DIR="$1"
            shift
            ;;
    esac
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

if [ ! -d "${PROJECT_DIR}" ]; then
    echo "[ERROR] PROJECT_DIR 不存在：${PROJECT_DIR}" >&2
    exit 1
fi

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

apply_sample_name_removals() {
    local sample_id="$1"
    local remove_string

    for remove_string in "${REMOVE_STRINGS[@]}"; do
        sample_id="${sample_id//"${remove_string}"/}"
    done

    printf '%s\n' "${sample_id}"
}

validate_sample_id() {
    local sample_id="$1"
    local filename="$2"

    if [ -z "${sample_id}" ]; then
        echo "[ERROR] 套用命名規則後 Sample ID 為空：${filename}" >&2
        exit 1
    fi

    if [[ "${sample_id}" == *$'\t'* ]] || [[ "${sample_id}" == *$'\n'* ]] || [[ "${sample_id}" == *$'\r'* ]]; then
        echo "[ERROR] Sample ID 含有不允許的 tab/newline：${sample_id}" >&2
        exit 1
    fi
}

TARGET_DIR="$(resolve_input_dir)"

if [ -z "${TARGET_DIR}" ]; then
    echo "[ERROR] 找不到可用的 FASTQ 資料夾"
    echo "[ERROR] 請確認 raw_fastq/ 或 trimmed_fastq/ 內至少有一個 .fastq.gz 檔案"
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

    # Case 1: Illumina / MiSeq style
    if [[ "${filename}" =~ ^(.+)_S[0-9]+_L[0-9]{3}_R([12])(_[0-9]{3})?(_trimmed)?\.fastq\.gz$ ]]; then
        sample_id="${BASH_REMATCH[1]}"
        read_direction="${BASH_REMATCH[2]}"

    # Case 2: simple style
    elif [[ "${filename}" =~ ^(.+)_R([12])(_[0-9]{3})?(_trimmed)?\.fastq\.gz$ ]]; then
        sample_id="${BASH_REMATCH[1]}"
        read_direction="${BASH_REMATCH[2]}"

    else
        unknown_files+=("${filename}")
        continue
    fi

    # 客製化移除只作用在已辨識完成的 sample ID，
    # 不影響 R1/R2、lane、index 等 FASTQ 結構判斷。
    sample_id="$(apply_sample_name_removals "${sample_id}")"
    validate_sample_id "${sample_id}" "${filename}"

    if [ "${read_direction}" = "1" ]; then
        if [ -n "${forward_map[${sample_id}]:-}" ]; then
            duplicate_r1_samples+=("${sample_id}")
        else
            forward_map["${sample_id}"]="${filepath}"
        fi

    elif [ "${read_direction}" = "2" ]; then
        if [ -n "${reverse_map[${sample_id}]:-}" ]; then
            duplicate_r2_samples+=("${sample_id}")
        else
            reverse_map["${sample_id}"]="${filepath}"
        fi
    fi

    sample_seen["${sample_id}"]=1
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

if [ "${#REMOVE_STRINGS[@]}" -gt 0 ]; then
    echo "[INFO] REMOVE_STRINGS      = ${REMOVE_STRINGS[*]}"
fi

if [ "${unknown_count}" -gt 0 ]; then
    echo
    echo "[ERROR] 以下檔名無法辨識為 R1/R2："
    printf '  - %s\n' "${unknown_files[@]}"
    echo "[ERROR] 支援格式例如："
    echo "  - sampleA_R1.fastq.gz"
    echo "  - sampleA_R2.fastq.gz"
    echo "  - sampleA_R1_001.fastq.gz"
    echo "  - sampleA_R2_001.fastq.gz"
    echo "  - sampleA_R1_trimmed.fastq.gz"
    echo "  - sampleA_R2_trimmed.fastq.gz"
    echo "  - sampleA_S1_L001_R1_001.fastq.gz"
    echo "  - sampleA_S1_L001_R2_001.fastq.gz"
    echo "  - sampleA_S1_L001_R1_trimmed.fastq.gz"
    echo "  - sampleA_S1_L001_R2_trimmed.fastq.gz"
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

if [ "${unknown_count}" -gt 0 ] || \
   [ "${unpaired_count}" -gt 0 ] || \
   [ "${duplicate_r1_count}" -gt 0 ] || \
   [ "${duplicate_r2_count}" -gt 0 ]; then
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
