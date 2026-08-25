#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# PacBio Vega HiFi BAM -> Demultiplexed FASTQ
#
# Default:
#   cd <run>/1_A01/hifi_reads
#   ~/scripts/pacbio_demux2fastq.sh
#
# Optional:
#   -b FILE   custom barcode FASTA
#   -m FILE   custom sample sheet (.xlsx)
#   -h        help
#
# Sample sheet:
#   ./list.xlsx
#
# Expected columns:
#   ID | forward_name | f_sequencce | reverse_name | r_sequencce
#
# Output naming:
#
#   list.xlsx exists:
#       <SampleID>.hifi_reads.fastq.gz
#
#   list.xlsx absent:
#       <movie>.<forward>--<reverse>.hifi_reads.fastq.gz
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

DEFAULT_BARCODES="$HOME/pacbio_reference/Sequel_16S_barcodes_for_192-Plex.fasta"
DEFAULT_SAMPLE_SHEET="./list.xlsx"

BARCODES="$DEFAULT_BARCODES"
SAMPLE_SHEET="$DEFAULT_SAMPLE_SHEET"
SAMPLE_SHEET_EXPLICIT=false


# ------------------------------------------------------------
# Usage
# ------------------------------------------------------------

usage() {
    cat <<EOF
Usage:
  pacbio_demux2fastq.sh [options]

Options:
  -b FILE    Custom barcode FASTA
  -m FILE    Custom sample sheet (.xlsx)
  -h         Show help

Default barcode:
  $DEFAULT_BARCODES

Default sample sheet:
  ./list.xlsx

If list.xlsx exists:
  FASTQ files are named by Sample ID.

If list.xlsx does not exist:
  FASTQ files are named by barcode pair.

Examples:

  pacbio_demux2fastq.sh

  pacbio_demux2fastq.sh \
      -b /path/to/barcodes.fasta

  pacbio_demux2fastq.sh \
      -m /path/to/list.xlsx

EOF
}


# ------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------

while getopts ":b:m:h" opt; do
    case "$opt" in
        b)
            BARCODES="$OPTARG"
            ;;
        m)
            SAMPLE_SHEET="$OPTARG"
            SAMPLE_SHEET_EXPLICIT=true
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo "ERROR: Option -$OPTARG requires an argument."
            exit 1
            ;;
        \?)
            echo "ERROR: Unknown option -$OPTARG"
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

for CMD in lima bam2fastq python; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: $CMD not found in PATH."
        echo "Activate the pacbio_demux environment."
        exit 1
    fi
done

if ! python -c "import openpyxl" >/dev/null 2>&1; then
    echo "ERROR: Python package 'openpyxl' is not installed."
    echo
    echo "Install once with:"
    echo "  conda install -c conda-forge openpyxl"
    exit 1
fi


# ------------------------------------------------------------
# Find HiFi BAM
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
    exit 1
fi

BAM="${BAM_FILES[0]#./}"
PREFIX="${BAM%.hifi_reads.bam}"


# ------------------------------------------------------------
# Check PBI
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
# Detect sample sheet
# ------------------------------------------------------------

USE_SAMPLE_SHEET=false

if [[ -f "$SAMPLE_SHEET" ]]; then
    USE_SAMPLE_SHEET=true
elif [[ "$SAMPLE_SHEET_EXPLICIT" == true ]]; then
    echo "ERROR: Sample sheet not found:"
    echo "  $SAMPLE_SHEET"
    exit 1
fi


# ------------------------------------------------------------
# Input summary
# ------------------------------------------------------------

echo "Input BAM:"
echo "  $BAM"

echo
echo "Barcode FASTA:"
echo "  $BARCODES"

echo
echo "Lima mode:"
echo "  ASYMMETRIC"

echo

if [[ "$USE_SAMPLE_SHEET" == true ]]; then
    echo "Sample sheet:"
    echo "  $SAMPLE_SHEET"
    echo
    echo "FASTQ naming:"
    echo "  Sample ID"
else
    echo "Sample sheet:"
    echo "  not found"
    echo
    echo "FASTQ naming:"
    echo "  barcode pair"
fi

echo


# ------------------------------------------------------------
# Create output directories
# ------------------------------------------------------------

mkdir -p lima fastq

LIMA_BAM="lima/${PREFIX}.demux.bam"
FASTQ_TMP_PREFIX="fastq/${PREFIX}"

COUNTS_FILE="lima/${PREFIX}.demux.lima.counts"

MANIFEST="fastq/fastq_manifest.tsv"


# ------------------------------------------------------------
# Prevent accidental overwrite
# ------------------------------------------------------------

if [[ -e "$LIMA_BAM" ]]; then
    echo "ERROR: Lima output already exists:"
    echo "  $LIMA_BAM"
    echo
    echo "Existing output will not be overwritten."
    exit 1
fi

if find fastq -maxdepth 1 -type f -name "*.fastq.gz" | grep -q .; then
    echo "ERROR: FASTQ directory already contains FASTQ.gz files."
    echo
    echo "Existing output will not be overwritten."
    exit 1
fi


# ------------------------------------------------------------
# Step 1: Lima
# ------------------------------------------------------------

echo "========================================"
echo "Step 1/4: Lima asymmetric demultiplex"
echo "========================================"
echo

lima \
    "$BAM" \
    "$BARCODES" \
    "$LIMA_BAM" \
    --hifi-preset ASYMMETRIC

echo
echo "Lima completed."
echo


# ------------------------------------------------------------
# Find Lima counts
# ------------------------------------------------------------

mapfile -t COUNTS_FILES < <(
    find lima -maxdepth 1 -type f -name "*.lima.counts"
)

if [[ ${#COUNTS_FILES[@]} -ne 1 ]]; then
    echo "ERROR: Expected exactly one Lima counts file."
    printf '  %s\n' "${COUNTS_FILES[@]}"
    exit 1
fi

COUNTS_FILE="${COUNTS_FILES[0]}"


# ------------------------------------------------------------
# Step 2: Lima QC
# ------------------------------------------------------------

echo "========================================"
echo "Step 2/4: Lima QC"
echo "========================================"
echo

if compgen -G "lima/*.lima.summary" > /dev/null; then
    cat lima/*.lima.summary
fi

echo
echo "Barcode counts:"
echo

cat "$COUNTS_FILE"

echo


# ------------------------------------------------------------
# Step 3: BAM -> temporary FASTQ
# ------------------------------------------------------------

echo "========================================"
echo "Step 3/4: bam2fastq"
echo "========================================"
echo

bam2fastq \
    --split-barcodes \
    -o "$FASTQ_TMP_PREFIX" \
    "$LIMA_BAM"

echo
echo "bam2fastq completed."
echo


# ------------------------------------------------------------
# Step 4: Rename FASTQ
# ------------------------------------------------------------

echo "========================================"
echo "Step 4/4: FASTQ naming"
echo "========================================"
echo

export PREFIX
export COUNTS_FILE
export SAMPLE_SHEET
export USE_SAMPLE_SHEET
export MANIFEST

python <<'PY'
import csv
import gzip
import os
import re
import sys
from pathlib import Path

from openpyxl import load_workbook


prefix = os.environ["PREFIX"]
counts_file = Path(os.environ["COUNTS_FILE"])
sample_sheet = Path(os.environ["SAMPLE_SHEET"])
use_sample_sheet = os.environ["USE_SAMPLE_SHEET"].lower() == "true"
manifest_file = Path(os.environ["MANIFEST"])

fastq_dir = Path("fastq")


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

def normalize_barcode(name):
    """
    Convert sample-sheet barcode names such as:

        16S_For_bc1005
        16S_Rev_bc1033

    into:

        bc1005
        bc1033

    If no bcXXXX suffix exists, retain the original name.
    """

    if name is None:
        return None

    name = str(name).strip()

    m = re.search(r"(bc[0-9]+)$", name, flags=re.IGNORECASE)

    if m:
        return m.group(1)

    return name


def safe_filename(value):
    value = str(value).strip()

    # Replace characters unsuitable for filenames.
    value = re.sub(r'[\\/:"*?<>|]+', "_", value)
    value = value.replace(" ", "_")

    return value


# ------------------------------------------------------------
# Read Lima barcode index mapping
# ------------------------------------------------------------

index_to_barcode = {}

with counts_file.open("r", newline="") as fh:
    reader = csv.DictReader(fh, delimiter="\t")

    required = {
        "IdxFirst",
        "IdxCombined",
        "IdxFirstNamed",
        "IdxCombinedNamed",
    }

    if not required.issubset(reader.fieldnames or []):
        sys.exit(
            "ERROR: Unexpected Lima counts format.\n"
            f"Columns: {reader.fieldnames}"
        )

    for row in reader:
        idx1 = str(row["IdxFirst"]).strip()
        idx2 = str(row["IdxCombined"]).strip()

        name1 = str(row["IdxFirstNamed"]).strip()
        name2 = str(row["IdxCombinedNamed"]).strip()

        index_to_barcode[(idx1, idx2)] = (name1, name2)


if not index_to_barcode:
    sys.exit("ERROR: No barcode pairs found in Lima counts.")


# ------------------------------------------------------------
# Read list.xlsx
# ------------------------------------------------------------

sample_mapping = {}

if use_sample_sheet:

    wb = load_workbook(sample_sheet, read_only=True, data_only=True)
    ws = wb.active

    rows = ws.iter_rows(values_only=True)

    try:
        headers = next(rows)
    except StopIteration:
        sys.exit("ERROR: Sample sheet is empty.")

    headers = [
        str(x).strip() if x is not None else ""
        for x in headers
    ]

    required = [
        "ID",
        "forward_name",
        "reverse_name",
    ]

    missing = [x for x in required if x not in headers]

    if missing:
        sys.exit(
            "ERROR: Required column(s) missing from sample sheet: "
            + ", ".join(missing)
        )

    idx_id = headers.index("ID")
    idx_forward = headers.index("forward_name")
    idx_reverse = headers.index("reverse_name")

    sample_ids = set()

    for excel_row, row in enumerate(rows, start=2):

        sample_id = row[idx_id]
        forward = row[idx_forward]
        reverse = row[idx_reverse]

        if sample_id is None and forward is None and reverse is None:
            continue

        if sample_id is None or forward is None or reverse is None:
            sys.exit(
                f"ERROR: Incomplete sample information at Excel row "
                f"{excel_row}."
            )

        sample_id = str(sample_id).strip()

        forward_norm = normalize_barcode(forward)
        reverse_norm = normalize_barcode(reverse)

        key = (forward_norm, reverse_norm)

        if sample_id in sample_ids:
            sys.exit(
                f"ERROR: Duplicate Sample ID in list.xlsx: "
                f"{sample_id}"
            )

        if key in sample_mapping:
            sys.exit(
                "ERROR: Duplicate barcode pair in list.xlsx: "
                f"{forward} + {reverse}"
            )

        sample_ids.add(sample_id)
        sample_mapping[key] = sample_id


    print(
        f"Loaded {len(sample_mapping)} sample mappings "
        f"from {sample_sheet}"
    )


# ------------------------------------------------------------
# Find bam2fastq output
# ------------------------------------------------------------

fastq_files = sorted(
    fastq_dir.glob("*.fastq.gz")
)

if not fastq_files:
    sys.exit("ERROR: No FASTQ.gz files found.")


# bam2fastq filenames end in:
#
#   .0_1.fastq.gz
#   .15_20.fastq.gz
#
index_pattern = re.compile(
    r"\.([0-9]+)_([0-9]+)\.fastq\.gz$"
)


manifest_rows = []
used_output_names = set()
observed_samples = set()


for source in fastq_files:

    m = index_pattern.search(source.name)

    if not m:
        sys.exit(
            "ERROR: Cannot determine barcode indices from FASTQ:\n"
            f"  {source.name}"
        )

    idx1, idx2 = m.groups()

    key_idx = (idx1, idx2)

    if key_idx not in index_to_barcode:
        sys.exit(
            "ERROR: Barcode index pair not found in Lima counts:\n"
            f"  {idx1}_{idx2}"
        )

    forward_name, reverse_name = index_to_barcode[key_idx]

    forward_norm = normalize_barcode(forward_name)
    reverse_norm = normalize_barcode(reverse_name)

    sample_id = ""

    if use_sample_sheet:

        barcode_key = (
            forward_norm,
            reverse_norm,
        )

        sample_id = sample_mapping.get(barcode_key, "")

        if sample_id:
            destination_name = (
                f"{safe_filename(sample_id)}"
                ".hifi_reads.fastq.gz"
            )

            observed_samples.add(sample_id)

        else:
            print(
                "WARNING: No Sample ID mapping for "
                f"{forward_name} + {reverse_name}"
            )

            destination_name = (
                f"{prefix}."
                f"{safe_filename(forward_name)}--"
                f"{safe_filename(reverse_name)}."
                "hifi_reads.fastq.gz"
            )

    else:

        destination_name = (
            f"{prefix}."
            f"{safe_filename(forward_name)}--"
            f"{safe_filename(reverse_name)}."
            "hifi_reads.fastq.gz"
        )


    if destination_name in used_output_names:
        sys.exit(
            "ERROR: Duplicate output filename generated:\n"
            f"  {destination_name}"
        )

    used_output_names.add(destination_name)

    destination = fastq_dir / destination_name


    if destination.exists() and destination != source:
        sys.exit(
            "ERROR: Destination already exists:\n"
            f"  {destination}"
        )


    source.rename(destination)


    manifest_rows.append(
        {
            "sample_id": sample_id,
            "forward_barcode": forward_name,
            "reverse_barcode": reverse_name,
            "barcode_index": f"{idx1}_{idx2}",
            "fastq": destination.name,
        }
    )


# ------------------------------------------------------------
# Check samples that had no demultiplexed reads
# ------------------------------------------------------------

if use_sample_sheet:

    expected_samples = set(sample_mapping.values())
    missing_samples = sorted(
        expected_samples - observed_samples
    )

    if missing_samples:

        print()
        print(
            "WARNING: The following samples from list.xlsx "
            "did not produce a FASTQ:"
        )

        for sample in missing_samples:
            print(f"  {sample}")

        print()


# ------------------------------------------------------------
# Manifest
# ------------------------------------------------------------

with manifest_file.open("w", newline="") as fh:

    writer = csv.DictWriter(
        fh,
        fieldnames=[
            "sample_id",
            "forward_barcode",
            "reverse_barcode",
            "barcode_index",
            "fastq",
        ],
        delimiter="\t",
    )

    writer.writeheader()
    writer.writerows(manifest_rows)


print()
print(f"FASTQ files renamed: {len(manifest_rows)}")
print(f"Manifest: {manifest_file}")

PY


# ------------------------------------------------------------
# Validate FASTQ
# ------------------------------------------------------------

echo
echo "Validating FASTQ.gz files..."
echo

mapfile -t FINAL_FASTQ < <(
    find fastq \
        -maxdepth 1 \
        -type f \
        -name "*.hifi_reads.fastq.gz" \
        | sort
)

if [[ ${#FINAL_FASTQ[@]} -eq 0 ]]; then
    echo "ERROR: No final FASTQ files found."
    exit 1
fi

for FASTQ in "${FINAL_FASTQ[@]}"; do
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

echo "FASTQ count:"
echo "  ${#FINAL_FASTQ[@]}"

echo
echo "FASTQ directory:"
echo "  $WORKDIR/fastq"

echo
echo "Manifest:"
echo "  $WORKDIR/$MANIFEST"

echo
