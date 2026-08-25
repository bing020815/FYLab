#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# PacBio Vega HiFi BAM -> Demultiplexed FASTQ
#
# Default usage:
#   cd <run>/1_A01/hifi_reads
#   ~/scripts/pacbio_demux2fastq.sh
#
# Custom barcode:
#   ~/scripts/pacbio_demux2fastq.sh -b /path/to/barcodes.fasta
#
# Help:
#   ~/scripts/pacbio_demux2fastq.sh -h
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

DEFAULT_BARCODES="$HOME/pacbio_reference/Sequel_16S_barcodes_for_192-Plex.fasta"

BARCODES="$DEFAULT_BARCODES"


# ------------------------------------------------------------
# Usage
# ------------------------------------------------------------

usage() {
    cat <<EOF
Usage:
  pacbio_demux2fastq.sh [options]

Options:
  -b FILE    Use a custom barcode FASTA
  -h         Show this help

Default barcode:
  $DEFAULT_BARCODES

Example:
  cd /home/vega_output/<run>/1_A01/hifi_reads
  ~/scripts/pacbio_demux2fastq.sh

Custom barcode example:
  ~/scripts/pacbio_demux2fastq.sh -b /path/to/custom_barcodes.fasta
EOF
}


# ------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------

while getopts ":b:h" opt; do
    case "$opt" in
        b)
            BARCODES="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo "ERROR: Option -$OPTARG requires an argument."
            usage
            exit 1
            ;;
        \?)
            echo "ERROR: Unknown option -$OPTARG"
            usage
            exit 1
            ;;
    esac
done


# ------------------------------------------------------------
# Working directory
# ------------------------------------------------------------

WORKDIR="$(pwd)"

echo "========================================"
echo "PacBio HiFi Demultiplex -> FASTQ"
echo "========================================"
echo
echo "Working directory:"
echo "  $WORKDIR"
echo


# ------------------------------------------------------------
# Check dependencies
# ------------------------------------------------------------

for CMD in lima bam2fastq; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: $CMD not found in PATH."
        echo "Activate the pacbio_demux environment first."
        exit 1
    fi
done


# ------------------------------------------------------------
# Find HiFi BAM
# ------------------------------------------------------------

mapfile -t BAM_FILES < <(
    find . -maxdepth 1 -type f -name "*.hifi_reads.bam" | sort
)

if [[ ${#BAM_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No *.hifi_reads.bam found in:"
    echo "  $WORKDIR"
    exit 1
fi

if [[ ${#BAM_FILES[@]} -gt 1 ]]; then
    echo "ERROR: Multiple *.hifi_reads.bam files found:"
    printf '  %s\n' "${BAM_FILES[@]}"
    exit 1
fi

BAM="${BAM_FILES[0]}"
BAM="${BAM#./}"

PREFIX="${BAM%.hifi_reads.bam}"


# ------------------------------------------------------------
# Check BAM index
# ------------------------------------------------------------

if [[ ! -f "${BAM}.pbi" ]]; then
    echo "ERROR: Missing BAM index:"
    echo "  ${BAM}.pbi"
    exit 1
fi


# ------------------------------------------------------------
# Check barcode FASTA
# ------------------------------------------------------------

if [[ ! -f "$BARCODES" ]]; then
    echo "ERROR: Barcode FASTA not found:"
    echo "  $BARCODES"
    exit 1
fi


# ------------------------------------------------------------
# Show input
# ------------------------------------------------------------

echo "Input BAM:"
echo "  $BAM"

echo
echo "BAM index:"
echo "  ${BAM}.pbi"

echo
echo "Barcode FASTA:"
echo "  $BARCODES"

if [[ "$BARCODES" == "$DEFAULT_BARCODES" ]]; then
    echo "  [default]"
else
    echo "  [custom]"
fi

echo
echo "Output prefix:"
echo "  $PREFIX"
echo


# ------------------------------------------------------------
# Create output directories
# ------------------------------------------------------------

mkdir -p lima fastq

LIMA_BAM="lima/${PREFIX}.demux.bam"
FASTQ_PREFIX="fastq/${PREFIX}"


# ------------------------------------------------------------
# Prevent accidental overwrite
# ------------------------------------------------------------

if [[ -e "$LIMA_BAM" ]]; then
    echo "ERROR: Lima output already exists:"
    echo "  $LIMA_BAM"
    echo
    echo "Existing results will NOT be overwritten."
    exit 1
fi

if compgen -G "${FASTQ_PREFIX}"'*.fastq.gz' > /dev/null; then
    echo "ERROR: FASTQ output already exists:"
    echo "  ${FASTQ_PREFIX}*.fastq.gz"
    echo
    echo "Existing results will NOT be overwritten."
    exit 1
fi


# ------------------------------------------------------------
# Step 1: Lima demultiplex
# ------------------------------------------------------------

echo "========================================"
echo "Step 1/3: Lima demultiplex"
echo "========================================"
echo

lima \
    "$BAM" \
    "$BARCODES" \
    "$LIMA_BAM" \
    --hifi-preset SYMMETRIC

echo
echo "Lima completed."
echo


# ------------------------------------------------------------
# Step 2: Lima QC
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
# Step 3: BAM -> FASTQ
# ------------------------------------------------------------

echo "========================================"
echo "Step 3/3: bam2fastq"
echo "========================================"
echo

bam2fastq \
    --split-barcodes \
    -o "$FASTQ_PREFIX" \
    "$LIMA_BAM"

echo
echo "bam2fastq completed."
echo


# ------------------------------------------------------------
# Validate FASTQ
# ------------------------------------------------------------

mapfile -t FASTQ_FILES < <(
    find fastq -maxdepth 1 -type f \
        -name "${PREFIX}*.fastq.gz" | sort
)

if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No FASTQ.gz files generated."
    exit 1
fi

echo "Validating FASTQ.gz files..."

for FASTQ in "${FASTQ_FILES[@]}"; do
    gzip -t "$FASTQ"
done


# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

echo
echo "========================================"
echo "Pipeline completed successfully"
echo "========================================"
echo

echo "Generated FASTQ:"
printf '  %s\n' "${FASTQ_FILES[@]}"

echo
echo "Lima output:"
echo "  $WORKDIR/lima"

echo
echo "FASTQ output:"
echo "  $WORKDIR/fastq"
