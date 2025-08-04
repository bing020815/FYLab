#!/bin/bash

mkdir -p fastp_out
mkdir -p fastp_report

# 取出 sample-id（唯一）
cut -d',' -f1 manifest.txt | grep -v sample-id | sort | uniq | while read sample; do
  # 抓 forward/reverse 對應的行
  FWD_LINE=$(grep "^$sample," manifest.txt | grep forward)
  REV_LINE=$(grep "^$sample," manifest.txt | grep reverse)

  FWD_PATH=$(echo "$FWD_LINE" | cut -d',' -f2)
  REV_PATH=$(echo "$REV_LINE" | cut -d',' -f2)

  FWD_NAME=$(basename "$FWD_PATH")
  REV_NAME=$(basename "$REV_PATH")

  # 檔案存在確認
  if [[ ! -f "$FWD_PATH" || ! -f "$REV_PATH" ]]; then
    echo "$sample 缺少檔案，略過"
    continue
  fi

  # 輸出檔名：插入 _head
  OUT_FWD="fastp_out/${FWD_NAME/.fastq.gz/_head.fastq.gz}"
  OUT_REV="fastp_out/${REV_NAME/.fastq.gz/_head.fastq.gz}"
  HTML_OUT="fastp_report/${sample}_fastp.html"
  JSON_OUT="fastp_report/${sample}_fastp.json"

  echo "正在處理 $sample"
  fastp \
    -i "$FWD_PATH" \
    -I "$REV_PATH" \
    -o "$OUT_FWD" \
    -O "$OUT_REV" \
    --trim_front2 17 \
    --length_required 100 \
    --thread 4 \
    --html "$HTML_OUT" \
    --json "$JSON_OUT"
done
