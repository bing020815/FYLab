#!/bin/bash

mkdir -p trimmed_fastq

FWD_PRIMER="CCTACGGGNGGCWGCAG"
REV_PRIMER="GACTACHVGGGTATCTAATCC"

for R1 in raw_fastq/*R1*.fastq.gz; do
    R2=${R1/R1/R2}

    if [ ! -f "$R2" ]; then
        echo "Skip: Paired file not found for $R1"
        continue
    fi

    BASENAME=$(basename "$R1" .fastq.gz)
    SAMPLE=${BASENAME%%_R1*}

    OUT_R1="trimmed_fastq/${SAMPLE}_R1_trimmed.fastq.gz"
    OUT_R2="trimmed_fastq/${SAMPLE}_R2_trimmed.fastq.gz"

    echo "Trimming $SAMPLE ..."

    cutadapt \
        -g "$FWD_PRIMER" \
        -G "$REV_PRIMER" \
        -o "$OUT_R1" \
        -p "$OUT_R2" \
        "$R1" "$R2"

    echo "Finished $SAMPLE"
    echo ""
done

echo "All samples trimmed."
