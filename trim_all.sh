#!/bin/bash

mkdir -p trimmed_fastq logs

# primer 設定（17 bp）
FWD_PRIMER="CCTACGGGNGGCWGCAG"
REV_PRIMER="GACTACHVGGGTATCTAATCC"
ERROR_RATE=0.15
OVERLAP=15

# 統計變數
TOTAL_SAMPLES=0
FAILED_SAMPLES=()

for R1 in raw_fastq/*_R1*.fastq.gz; do
    R2=${R1/_R1/_R2}

    if [ ! -f "$R2" ]; then
        BASENAME=$(basename "$R1")
        SAMPLE=${BASENAME%%_R1*}
        FAILED_SAMPLES+=("$SAMPLE")
        echo "跳過 $SAMPLE：找不到對應的 R2"
        continue
    fi

    BASENAME=$(basename "$R1" .fastq.gz)
    SAMPLE=${BASENAME%%_R1*}
    OUT_R1="trimmed_fastq/${SAMPLE}_R1_trimmed.fastq.gz"
    OUT_R2="trimmed_fastq/${SAMPLE}_R2_trimmed.fastq.gz"
    LOG="logs/${SAMPLE}.log"

    echo "Trimming $SAMPLE..."

    cutadapt \
        -e $ERROR_RATE \
        --overlap $OVERLAP \
        -g "$FWD_PRIMER" \
        -G "$REV_PRIMER" \
        -o "$OUT_R1" \
        -p "$OUT_R2" \
        "$R1" "$R2" > "$LOG"

    TOTAL_SAMPLES=$((TOTAL_SAMPLES+1))

done

# 統計輸出
echo "完成所有樣本處理"
echo "總樣本數：$TOTAL_SAMPLES"

if [ ${#FAILED_SAMPLES[@]} -gt 0 ]; then
    echo ""
    echo "以下樣本因找不到 R2 而被跳過："
    for sample in "${FAILED_SAMPLES[@]}"; do
        echo "  - $sample"
    done
fi
