#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-per_file}"   # single / all / per_file
TARGET="${1:-.}"

if [ -d "${TARGET}" ]; then
    cd "${TARGET}"
fi

shopt -s nullglob
files=(*.fastq.gz)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
    echo "[ERROR] 找不到 .fastq.gz 檔案"
    exit 1
fi

case "${MODE}" in
  single)
    if [ "${#files[@]}" -ne 1 ]; then
      echo "[ERROR] MODE=single 時請目錄內只放一個 .fastq.gz，或自行指定單檔目錄"
      exit 1
    fi
    gzip -cd "${files[0]}" | \
    awk 'NR%4==2 {print length($0)}' | \
    sort -n | uniq -c | \
    awk '{print $2 "\t" $1}'
    ;;

  all)
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
      print "N=" n, "Min=" min, "Mean=" sum/n, "Max=" max > "/dev/stderr"
    }'
    ;;

  per_file)
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
    echo "[INFO] 已輸出 fastq_length_summary.tsv"
    ;;

  *)
    echo "[ERROR] MODE 僅支援 single / all / per_file"
    exit 1
    ;;
esac
