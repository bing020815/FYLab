#!/bin/bash

mkdir -p trimmed_fastq

FWD_PRIMER="CCTACGGGNGGCWGCAG"
REV_PRIMER="GACTACHVGGGTATCTAATCC"

FAILED_SAMPLES=()  

for R1 in raw_fastq/*_R1*.fastq.gz; do
    R2=${R1/_R1/_R2}

    if [ ! -f "$R2" ]; then
        BASENAME=$(basename "$R1")
        SAMPLE=${BASENAME%%_R1*}
        FAILED_SAMPLES+=("$SAMPLE")
        echo "Skipping: no R2 found for $BASENAME"
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

echo "🎉 All samples trimmed."

if [ ${#FAILED_SAMPLES[@]} -gt 0 ]; then
    echo ""
    echo "The following samples were skipped due to missing R2 files:"
    for sample in "${FAILED_SAMPLES[@]}"; do
        echo "  - $sample"
    done
else
    echo "All samples had matched R1 and R2 files."
fi
