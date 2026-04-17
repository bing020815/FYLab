#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

INPUT_DIR_NAME="${INPUT_DIR_NAME:-auto}"

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

cd "${TARGET_DIR}"

shopt -s nullglob
FASTQ_FILES=(*.fastq.gz)
shopt -u nullglob

if [ "${#FASTQ_FILES[@]}" -eq 0 ]; then
    echo "[ERROR] ${TARGET_DIR} 內沒有 .fastq.gz 檔案"
    exit 1
fi

echo "[INFO] 使用資料夾：${TARGET_DIR}"
echo "[INFO] FASTQ 檔案數：${#FASTQ_FILES[@]}"

echo
echo "[INFO] 建立整批長度分布：fastq_length_distribution_all.tsv"

gzip -cd ./*.fastq.gz | \
awk 'NR%4==2 {print length($0)}' | \
sort -n | uniq -c | \
awk '{print $2 "\t" $1}' | \
tee fastq_length_distribution_all.tsv | \
awk '
{
  len=$1; count=$2;
  sum += len * count;
  n += count;
  if (min == "" || len < min) min = len;
  if (len > max) max = len;
}
END {
  print "[INFO] All FASTQ summary"
  print "[INFO] N=" n
  print "[INFO] Min=" min
  printf "[INFO] Mean=%.2f\n", sum/n
  print "[INFO] Max=" max
}'

echo
echo "[INFO] 建立每檔長度摘要：fastq_length_summary.tsv"

echo -e "file\treads\tmin\tmode\tmean\tmax" > fastq_length_summary.tsv

for f in ./*.fastq.gz; do
  gzip -cd "$f" | \
  awk -v file="$(basename "$f")" '
    NR%4==2 {
      len = length($0)
      count[len]++
      sum += len
      n++
      if (min == "" || len < min) min = len
      if (len > max) max = len
    }
    END {
      mode_len = ""
      mode_count = 0
      for (l in count) {
        if (count[l] > mode_count) {
          mode_count = count[l]
          mode_len = l
        }
      }
      printf "%s\t%d\t%s\t%s\t%.2f\t%s\n", file, n, min, mode_len, sum/n, max
    }
  ' >> fastq_length_summary.tsv
done

echo
echo "[INFO] 每檔長度摘要預覽"
column -t -s $'\t' fastq_length_summary.tsv || cat fastq_length_summary.tsv

echo
echo "[INFO] 已完成"
echo "[INFO] 輸出檔案："
echo "[INFO]   ${TARGET_DIR}/fastq_length_distribution_all.tsv"
echo "[INFO]   ${TARGET_DIR}/fastq_length_summary.tsv"
