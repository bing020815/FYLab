#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# PacBio Vega HiFi BAM demultiplex pipeline
#
# Usage:
#   cd <run>/hifi_reads
#   pacbio_demux
#
# Expected:
#   ./<movie>.hifi_reads.bam
#   ./barcode/*.fasta
#
# Output:
#   ./lima/
#   ./fastq/
# ============================================================

WORKDIR="$(pwd)"

echo "========================================"
echo "PacBio HiFi Demultiplex Pipeline"
echo "========================================"
echo "Working directory:"
echo "${WORKDIR}"
echo

# ------------------------------------------------------------
# 1. Find HiFi BAM
# ------------------------------------------------------------

mapfile -t BAM_FILES < <(
    find . -maxdepth 1 -type f -name "*.hifi_reads.bam" | sort
)

if [[ ${#BAM_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No *.hifi_reads.bam found."
    exit 1
fi

if [[ ${#BAM_FILES[@]} -gt 1 ]]; then
    echo "ERROR: Multiple *.hifi_reads.bam files found:"
    printf '  %s\n' "${BAM_FILES[@]}"
    echo
    echo "Expected exactly one HiFi BAM per hifi_reads directory."
    exit 1
fi

BAM="${BAM_FILES[0]}"
BAM="${BAM#./}"

# ------------------------------------------------------------
# 2. Check PBI
# ------------------------------------------------------------

if [[ ! -f "${BAM}.pbi" ]]; then
    echo "ERROR: Missing BAM index:"
    echo "  ${BAM}.pbi"
    exit 1
fi

# ------------------------------------------------------------
# 3. Find barcode FASTA
# ------------------------------------------------------------

if [[ ! -d "barcode" ]]; then
    echo "ERROR: barcode/ directory not found."
    exit 1
fi

mapfile -t BARCODE_FILES < <(
    find barcode -maxdepth 1 -type f \
        \( -name "*.fasta" -o -name "*.fa" -o -name "*.fas" \) \
        | sort
)

if [[ ${#BARCODE_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No barcode FASTA found in barcode/."
    exit 1
fi

if [[ ${#BARCODE_FILES[@]} -gt 1 ]]; then
    echo "ERROR: Multiple barcode FASTA files found:"
    printf '  %s\n' "${BARCODE_FILES[@]}"
    echo
    echo "Keep exactly one barcode FASTA in barcode/."
    exit 1
fi

BARCODES="${BARCODE_FILES[0]}"

# ------------------------------------------------------------
# 4. Derive sample/movie prefix
# ------------------------------------------------------------

PREFIX="${BAM%.hifi_reads.bam}"

echo "Input BAM:"
echo "  ${BAM}"

echo "Barcode FASTA:"
echo "  ${BARCODES}"

echo "Prefix:"
echo "  ${PREFIX}"

echo

# ------------------------------------------------------------
# 5. Check dependencies
# ------------------------------------------------------------

for CMD in lima bam2fastq; do
    if ! command -v "${CMD}" >/dev/null 2>&1; then
        echo "ERROR: ${CMD} not found in PATH."
        echo "Activate the PacBio environment first."
        exit 1
    fi
done

# ------------------------------------------------------------
# 6. Create output directories
# ------------------------------------------------------------

mkdir -p lima fastq

LIMA_BAM="lima/${PREFIX}.demux.bam"
FASTQ_PREFIX="fastq/${PREFIX}"

# ------------------------------------------------------------
# 7. Prevent accidental overwrite
# ------------------------------------------------------------

if [[ -e "${LIMA_BAM}" ]]; then
    echo "ERROR: Lima output already exists:"
    echo "  ${LIMA_BAM}"
    echo
    echo "Pipeline stopped to avoid overwriting an existing run."
    exit 1
fi

if compgen -G "${FASTQ_PREFIX}"'*.fastq.gz' > /dev/null; then
    echo "ERROR: FASTQ output already exists for:"
    echo "  ${FASTQ_PREFIX}"
    echo
    echo "Pipeline stopped to avoid overwriting an existing run."
    exit 1
fi

# ------------------------------------------------------------
# 8. Lima demultiplex
# ------------------------------------------------------------

echo "========================================"
echo "Step 1/3: Lima demultiplex"
echo "========================================"

lima \
    "${BAM}" \
    "${BARCODES}" \
    "${LIMA_BAM}" \
    --hifi-preset SYMMETRIC

echo
echo "Lima completed."
echo

# ------------------------------------------------------------
# 9. Show Lima QC
# ------------------------------------------------------------

echo "========================================"
echo "Step 2/3: Lima QC"
echo "========================================"

if compgen -G "lima/*.lima.summary" > /dev/null; then
    echo
    echo "----- Lima summary -----"
    cat lima/*.lima.summary
fi

if compgen -G "lima/*.lima.counts" > /dev/null; then
    echo
    echo "----- Lima counts -----"
    cat lima/*.lima.counts
fi

echo

# ------------------------------------------------------------
# 10. BAM -> FASTQ
# ------------------------------------------------------------

echo "========================================"
echo "Step 3/3: bam2fastq"
echo "========================================"

bam2fastq \
    --split-barcodes \
    -o "${FASTQ_PREFIX}" \
    "${LIMA_BAM}"

echo
echo "bam2fastq completed."
echo

# ------------------------------------------------------------
# 11. Validate FASTQ gzip files
# ------------------------------------------------------------

mapfile -t FASTQ_FILES < <(
    find fastq -maxdepth 1 -type f -name "${PREFIX}*.fastq.gz" | sort
)

if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No FASTQ.gz files generated."
    exit 1
fi

echo "Validating FASTQ.gz files..."

for FASTQ in "${FASTQ_FILES[@]}"; do
    gzip -t "${FASTQ}"
done

echo
echo "========================================"
echo "Pipeline completed successfully"
echo "========================================"

echo
echo "FASTQ files:"
printf '  %s\n' "${FASTQ_FILES[@]}"

echo
echo "Output directories:"
echo "  ${WORKDIR}/lima"
echo "  ${WORKDIR}/fastq"
