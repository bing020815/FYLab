#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# PacBio Vega HiFi BAM -> demultiplexed FASTQ
#
# Run from:
#
#   <run>/1_A01/hifi_reads
#
# Default:
#
#   Barcode FASTA:
#     ~/pacbio_reference/
#     Sequel_16S_barcodes_for_192-Plex.fasta
#
#   Sample sheet:
#     ./list.xlsx
#
#
# Sample sheet columns:
#
#   ID
#   forward_name
#   f_sequence
#   reverse_name
#   r_sequence
#
#
# Behavior
# --------
#
# If list.xlsx exists:
#
#   sample sheet = whitelist
#
#   Only mapped barcode pairs are retained:
#
#     <SampleID>.hifi_reads.fastq.gz
#
#
# If list.xlsx does not exist:
#
#   all Lima-demultiplexed barcode pairs are retained:
#
#     <movie>.<forward>--<reverse>.hifi_reads.fastq.gz
#
#
# Output:
#
#   lima/
#   fastq/
#   fastq/fastq_manifest.tsv
#   pacbio_demux_runtime.txt
#
# ============================================================


# ============================================================
# Runtime
# ============================================================

PIPELINE_START=$(date +%s)

PIPELINE_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')


format_duration() {
    local seconds="$1"

    printf '%02d:%02d:%02d' \
        $((seconds / 3600)) \
        $(((seconds % 3600) / 60)) \
        $((seconds % 60))
}


# ============================================================
# Configuration
# ============================================================

DEFAULT_BARCODES="$HOME/pacbio_reference/Sequel_16S_barcodes_for_192-Plex.fasta"

DEFAULT_SAMPLE_SHEET="./list.xlsx"

BARCODES="$DEFAULT_BARCODES"

SAMPLE_SHEET="$DEFAULT_SAMPLE_SHEET"

SAMPLE_SHEET_EXPLICIT=false


# ============================================================
# Usage
# ============================================================

usage() {
    cat <<EOF

Usage:

  pacbio_demux2fastq.sh [options]

Options:

  -b FILE
      Custom barcode FASTA.

  -m FILE
      Custom sample sheet (.xlsx).

  -h
      Show help.

Default barcode:

  $DEFAULT_BARCODES

Default sample sheet:

  ./list.xlsx

EOF
}


# ============================================================
# Arguments
# ============================================================

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


# ============================================================
# Working directory
# ============================================================

WORKDIR="$(pwd)"


echo
echo "========================================"
echo "PacBio HiFi Demultiplex -> FASTQ"
echo "========================================"
echo

echo "Working directory:"
echo "  $WORKDIR"
echo


if [[ "$(basename "$WORKDIR")" != "hifi_reads" ]]; then
    echo "ERROR:"
    echo "This script must be run from a hifi_reads directory."
    exit 1
fi


# ============================================================
# Dependencies
# ============================================================

for CMD in lima bam2fastq python gzip; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR:"
        echo "$CMD not found in PATH."
        echo
        echo "Activate the pacbio_demux Conda environment."
        exit 1
    fi
done


if ! python -c "import openpyxl" >/dev/null 2>&1; then
    echo "ERROR:"
    echo "Python package openpyxl is not installed."
    echo
    echo "Install with:"
    echo "  conda install -c conda-forge openpyxl"
    exit 1
fi


# ============================================================
# Find BAM
# ============================================================

mapfile -t BAM_FILES < <(
    find . \
        -maxdepth 1 \
        -type f \
        -name "*.hifi_reads.bam" \
        | sort
)


if [[ ${#BAM_FILES[@]} -eq 0 ]]; then
    echo "ERROR:"
    echo "No *.hifi_reads.bam found."
    exit 1
fi


if [[ ${#BAM_FILES[@]} -gt 1 ]]; then
    echo "ERROR:"
    echo "Multiple *.hifi_reads.bam files found:"
    printf '  %s\n' "${BAM_FILES[@]}"
    exit 1
fi


BAM="${BAM_FILES[0]#./}"

PREFIX="${BAM%.hifi_reads.bam}"


# ============================================================
# PBI
# ============================================================

if [[ ! -f "${BAM}.pbi" ]]; then
    echo "ERROR:"
    echo "Missing BAM index:"
    echo "  ${BAM}.pbi"
    exit 1
fi


# ============================================================
# Barcode FASTA
# ============================================================

if [[ ! -f "$BARCODES" ]]; then
    echo "ERROR:"
    echo "Barcode FASTA not found:"
    echo "  $BARCODES"
    exit 1
fi


BARCODE_COUNT=$(grep -c '^>' "$BARCODES" || true)


if [[ "$BARCODE_COUNT" -eq 0 ]]; then
    echo "ERROR:"
    echo "No barcode entries found in:"
    echo "  $BARCODES"
    exit 1
fi


# ============================================================
# Sample sheet
# ============================================================

USE_SAMPLE_SHEET=false


if [[ -f "$SAMPLE_SHEET" ]]; then

    USE_SAMPLE_SHEET=true

elif [[ "$SAMPLE_SHEET_EXPLICIT" == true ]]; then

    echo "ERROR:"
    echo "Specified sample sheet not found:"
    echo "  $SAMPLE_SHEET"

    exit 1
fi


# ============================================================
# Summary
# ============================================================

echo "Input BAM:"
echo "  $BAM"
echo

echo "BAM index:"
echo "  ${BAM}.pbi"
echo

echo "Barcode FASTA:"
echo "  $BARCODES"
echo

echo "Barcode entries:"
echo "  $BARCODE_COUNT"
echo

echo "Lima preset:"
echo "  ASYMMETRIC"
echo


if [[ "$USE_SAMPLE_SHEET" == true ]]; then

    echo "Sample sheet:"
    echo "  $SAMPLE_SHEET"
    echo

    echo "FASTQ mode:"
    echo "  Sample sheet whitelist"
    echo

    echo "FASTQ naming:"
    echo "  <SampleID>.hifi_reads.fastq.gz"

else

    echo "Sample sheet:"
    echo "  none"
    echo

    echo "FASTQ mode:"
    echo "  Export all demultiplexed barcode pairs"
    echo

    echo "FASTQ naming:"
    echo "  <movie>.<forward>--<reverse>.hifi_reads.fastq.gz"

fi


# ============================================================
# Paths
# ============================================================

mkdir -p lima
mkdir -p fastq


LIMA_BAM="lima/${PREFIX}.demux.bam"

FASTQ_TMP_DIR="fastq/.tmp_${PREFIX}"

FASTQ_TMP_PREFIX="${FASTQ_TMP_DIR}/${PREFIX}"

MANIFEST="fastq/fastq_manifest.tsv"

RUNTIME_REPORT="pacbio_demux_runtime.txt"


# ============================================================
# Overwrite protection
# ============================================================

if [[ -e "$LIMA_BAM" ]]; then
    echo "ERROR:"
    echo "Lima output already exists:"
    echo "  $LIMA_BAM"
    echo
    echo "Existing results will NOT be overwritten."
    exit 1
fi


if find fastq \
    -maxdepth 1 \
    -type f \
    -name "*.fastq.gz" \
    | grep -q .; then

    echo "ERROR:"
    echo "fastq/ already contains FASTQ.gz files."
    echo
    echo "Existing results will NOT be overwritten."
    exit 1
fi


if [[ -e "$FASTQ_TMP_DIR" ]]; then
    echo "ERROR:"
    echo "Temporary directory already exists:"
    echo "  $FASTQ_TMP_DIR"
    exit 1
fi


mkdir -p "$FASTQ_TMP_DIR"


# ============================================================
# Step 1: Lima
# ============================================================

echo
echo "========================================"
echo "Step 1/4: Lima demultiplex"
echo "========================================"
echo


LIMA_START=$(date +%s)


lima \
    "$BAM" \
    "$BARCODES" \
    "$LIMA_BAM" \
    --hifi-preset ASYMMETRIC


LIMA_END=$(date +%s)

LIMA_SECONDS=$((LIMA_END - LIMA_START))


echo
echo "Lima completed."
echo "Lima runtime:"
echo "  $(format_duration "$LIMA_SECONDS")"
echo


# ============================================================
# Lima counts
# ============================================================

mapfile -t COUNTS_FILES < <(
    find lima \
        -maxdepth 1 \
        -type f \
        -name "*.lima.counts" \
        | sort
)


if [[ ${#COUNTS_FILES[@]} -ne 1 ]]; then
    echo "ERROR:"
    echo "Expected exactly one *.lima.counts file."
    printf '  %s\n' "${COUNTS_FILES[@]}"
    exit 1
fi


COUNTS_FILE="${COUNTS_FILES[0]}"


# ============================================================
# Step 2: Lima QC
# ============================================================

echo
echo "========================================"
echo "Step 2/4: Lima QC"
echo "========================================"
echo


if compgen -G "lima/*.lima.summary" > /dev/null; then
    echo "----- Lima summary -----"
    echo
    cat lima/*.lima.summary
    echo
fi


echo "----- Barcode counts -----"
echo

cat "$COUNTS_FILE"

echo


# ============================================================
# Step 3: bam2fastq
# ============================================================

echo
echo "========================================"
echo "Step 3/4: bam2fastq"
echo "========================================"
echo


BAM2FASTQ_START=$(date +%s)


bam2fastq \
    --split-barcodes \
    -o "$FASTQ_TMP_PREFIX" \
    "$LIMA_BAM"


BAM2FASTQ_END=$(date +%s)

BAM2FASTQ_SECONDS=$((BAM2FASTQ_END - BAM2FASTQ_START))


echo
echo "bam2fastq completed."
echo "bam2fastq runtime:"
echo "  $(format_duration "$BAM2FASTQ_SECONDS")"
echo


# ============================================================
# Step 4: FASTQ naming/filtering
# ============================================================

echo
echo "========================================"
echo "Step 4/4: FASTQ naming"
echo "========================================"
echo


NAMING_START=$(date +%s)


export PREFIX
export COUNTS_FILE
export SAMPLE_SHEET
export USE_SAMPLE_SHEET
export MANIFEST
export FASTQ_TMP_DIR


python <<'PY'
import csv
import os
import re
import sys
from pathlib import Path

from openpyxl import load_workbook


prefix = os.environ["PREFIX"]
counts_file = Path(os.environ["COUNTS_FILE"])
sample_sheet = Path(os.environ["SAMPLE_SHEET"])

use_sample_sheet = (
    os.environ["USE_SAMPLE_SHEET"].lower() == "true"
)

manifest_file = Path(os.environ["MANIFEST"])

fastq_dir = Path("fastq")
fastq_tmp_dir = Path(os.environ["FASTQ_TMP_DIR"])


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

def normalize_barcode(name):
    if name is None:
        return None

    name = str(name).strip()

    match = re.search(
        r"(bc[0-9]+)$",
        name,
        flags=re.IGNORECASE,
    )

    if match:
        return match.group(1).lower()

    return name.lower()


def safe_filename(value):
    value = str(value).strip()

    value = re.sub(
        r'[\\/:"*?<>|]+',
        "_",
        value,
    )

    value = value.replace(" ", "_")

    return value


# ------------------------------------------------------------
# Lima index -> barcode
# ------------------------------------------------------------

index_to_barcode = {}


with counts_file.open("r", newline="") as fh:

    reader = csv.DictReader(
        fh,
        delimiter="\t",
    )

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

        index_to_barcode[(idx1, idx2)] = (
            name1,
            name2,
        )


if not index_to_barcode:
    sys.exit(
        "ERROR: No barcode pairs found in Lima counts."
    )


# ------------------------------------------------------------
# Sample sheet
# ------------------------------------------------------------

sample_mapping = {}


if use_sample_sheet:

    wb = load_workbook(
        sample_sheet,
        read_only=True,
        data_only=True,
    )

    ws = wb.active

    rows = ws.iter_rows(values_only=True)

    try:
        headers = next(rows)
    except StopIteration:
        sys.exit(
            "ERROR: Sample sheet is empty."
        )


    headers = [
        str(x).strip()
        if x is not None
        else ""
        for x in headers
    ]


    required = [
        "ID",
        "forward_name",
        "reverse_name",
    ]


    missing = [
        x for x in required
        if x not in headers
    ]


    if missing:
        sys.exit(
            "ERROR: Required sample-sheet column(s) missing: "
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


        if (
            sample_id is None
            and forward is None
            and reverse is None
        ):
            continue


        if (
            sample_id is None
            or forward is None
            or reverse is None
        ):
            sys.exit(
                "ERROR: Incomplete sample information "
                f"at Excel row {excel_row}."
            )


        sample_id = str(sample_id).strip()

        forward_norm = normalize_barcode(forward)
        reverse_norm = normalize_barcode(reverse)

        key = (
            forward_norm,
            reverse_norm,
        )


        if sample_id in sample_ids:
            sys.exit(
                "ERROR: Duplicate Sample ID: "
                f"{sample_id}"
            )


        if key in sample_mapping:
            sys.exit(
                "ERROR: Duplicate barcode pair in sample sheet: "
                f"{forward} + {reverse}"
            )


        sample_ids.add(sample_id)

        sample_mapping[key] = sample_id


    print(
        f"Loaded {len(sample_mapping)} sample mappings."
    )


# ------------------------------------------------------------
# Temporary FASTQ
# ------------------------------------------------------------

fastq_files = sorted(
    fastq_tmp_dir.glob("*.fastq.gz")
)


if not fastq_files:
    sys.exit(
        "ERROR: bam2fastq generated no FASTQ.gz files."
    )


index_pattern = re.compile(
    r"\.([0-9]+)_([0-9]+)\.fastq\.gz$"
)


manifest_rows = []
used_output_names = set()
observed_samples = set()
skipped_pairs = []


# ------------------------------------------------------------
# Process FASTQ
# ------------------------------------------------------------

for source in fastq_files:

    match = index_pattern.search(source.name)

    if not match:
        sys.exit(
            "ERROR: Cannot determine barcode indices:\n"
            f"  {source.name}"
        )


    idx1, idx2 = match.groups()

    index_key = (
        idx1,
        idx2,
    )


    if index_key not in index_to_barcode:
        sys.exit(
            "ERROR: Barcode index pair not found "
            "in Lima counts:\n"
            f"  {idx1}_{idx2}"
        )


    forward_name, reverse_name = (
        index_to_barcode[index_key]
    )


    forward_norm = normalize_barcode(
        forward_name
    )

    reverse_norm = normalize_barcode(
        reverse_name
    )


    sample_id = ""


    # --------------------------------------------------------
    # Sample-sheet whitelist mode
    # --------------------------------------------------------

    if use_sample_sheet:

        barcode_key = (
            forward_norm,
            reverse_norm,
        )

        sample_id = sample_mapping.get(
            barcode_key,
            "",
        )


        if not sample_id:

            print(
                "SKIP: Barcode pair not present "
                "in sample sheet: "
                f"{forward_name} + {reverse_name}"
            )

            skipped_pairs.append(
                (
                    forward_name,
                    reverse_name,
                )
            )

            source.unlink()

            continue


        destination_name = (
            f"{safe_filename(sample_id)}"
            ".hifi_reads.fastq.gz"
        )

        observed_samples.add(
            sample_id
        )


    # --------------------------------------------------------
    # No sample sheet
    # --------------------------------------------------------

    else:

        destination_name = (
            f"{prefix}."
            f"{safe_filename(forward_name)}"
            "--"
            f"{safe_filename(reverse_name)}"
            ".hifi_reads.fastq.gz"
        )


    # --------------------------------------------------------
    # Collision protection
    # --------------------------------------------------------

    if destination_name in used_output_names:
        sys.exit(
            "ERROR: Duplicate output filename:\n"
            f"  {destination_name}"
        )


    used_output_names.add(
        destination_name
    )


    destination = (
        fastq_dir / destination_name
    )


    if destination.exists():
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
# Missing expected samples
# ------------------------------------------------------------

if use_sample_sheet:

    expected_samples = set(
        sample_mapping.values()
    )

    missing_samples = sorted(
        expected_samples - observed_samples
    )


    if missing_samples:

        print()
        print(
            "WARNING: Samples in sample sheet "
            "without FASTQ:"
        )

        for sample in missing_samples:
            print(f"  {sample}")

        print()


# ------------------------------------------------------------
# Manifest
# ------------------------------------------------------------

with manifest_file.open(
    "w",
    newline="",
) as fh:

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


# ------------------------------------------------------------
# Remove temporary directory
# ------------------------------------------------------------

remaining = list(
    fastq_tmp_dir.iterdir()
)


if remaining:

    print(
        "WARNING: Temporary FASTQ directory "
        "is not empty:"
    )

    print(
        f"  {fastq_tmp_dir}"
    )

else:

    fastq_tmp_dir.rmdir()


# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

print()
print(
    f"Final FASTQ files: {len(manifest_rows)}"
)

if use_sample_sheet:
    print(
        f"Skipped barcode pairs: {len(skipped_pairs)}"
    )

print(
    f"Manifest: {manifest_file}"
)

PY


NAMING_END=$(date +%s)

NAMING_SECONDS=$((NAMING_END - NAMING_START))


echo
echo "FASTQ naming completed."
echo "FASTQ naming runtime:"
echo "  $(format_duration "$NAMING_SECONDS")"
echo


# ============================================================
# FASTQ validation
# ============================================================

echo
echo "========================================"
echo "FASTQ validation"
echo "========================================"
echo


VALIDATION_START=$(date +%s)


mapfile -t FINAL_FASTQ < <(
    find fastq \
        -maxdepth 1 \
        -type f \
        -name "*.hifi_reads.fastq.gz" \
        | sort
)


if [[ ${#FINAL_FASTQ[@]} -eq 0 ]]; then
    echo "ERROR:"
    echo "No final FASTQ files found."
    exit 1
fi


for FASTQ in "${FINAL_FASTQ[@]}"; do
    gzip -t "$FASTQ"
done


VALIDATION_END=$(date +%s)

VALIDATION_SECONDS=$((VALIDATION_END - VALIDATION_START))


echo "FASTQ validation completed."
echo "Validation runtime:"
echo "  $(format_duration "$VALIDATION_SECONDS")"
echo


# ============================================================
# Runtime report
# ============================================================

PIPELINE_END=$(date +%s)

PIPELINE_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')

TOTAL_SECONDS=$((PIPELINE_END - PIPELINE_START))


cat > "$RUNTIME_REPORT" <<EOF
PacBio Demultiplex Runtime Report
=================================

Working directory:
$WORKDIR

Input BAM:
$BAM

Barcode FASTA:
$BARCODES

Barcode entries:
$BARCODE_COUNT

Sample sheet:
$([[ "$USE_SAMPLE_SHEET" == true ]] && echo "$SAMPLE_SHEET" || echo "none")

Start:
$PIPELINE_START_TIME

End:
$PIPELINE_END_TIME

Runtime
-------

Lima:
$(format_duration "$LIMA_SECONDS")

bam2fastq:
$(format_duration "$BAM2FASTQ_SECONDS")

FASTQ naming:
$(format_duration "$NAMING_SECONDS")

FASTQ validation:
$(format_duration "$VALIDATION_SECONDS")

Total:
$(format_duration "$TOTAL_SECONDS")

Final FASTQ count:
${#FINAL_FASTQ[@]}

Manifest:
$WORKDIR/$MANIFEST
EOF


# ============================================================
# Complete
# ============================================================

echo
echo "========================================"
echo "Pipeline completed successfully"
echo "========================================"
echo

echo "Final FASTQ count:"
echo "  ${#FINAL_FASTQ[@]}"
echo

echo "FASTQ directory:"
echo "  $WORKDIR/fastq"
echo

echo "Manifest:"
echo "  $WORKDIR/$MANIFEST"
echo

echo "Runtime:"
echo "  Lima:             $(format_duration "$LIMA_SECONDS")"
echo "  bam2fastq:        $(format_duration "$BAM2FASTQ_SECONDS")"
echo "  FASTQ naming:     $(format_duration "$NAMING_SECONDS")"
echo "  FASTQ validation: $(format_duration "$VALIDATION_SECONDS")"
echo "  --------------------------------"
echo "  Total:            $(format_duration "$TOTAL_SECONDS")"
echo

echo "Runtime report:"
echo "  $WORKDIR/$RUNTIME_REPORT"
echo
