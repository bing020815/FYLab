#!/usr/bin/env bash
set -euo pipefail


# ============================================================
# PICRUSt functional post-processing
#
# Sequential:
#   1. KO descriptions
#   2. EC descriptions
#   3. KEGG pathway abundance
#   4. KEGG pathway descriptions
#   5. KEGG pathway contribution
#
# Supported environments:
#   picrust2
#   picrust2sc
#
# Output:
#   picrust/<method>/<input_mode>/
#
# Usage:
#   ./shell_tools/run_picrust_functional.sh \
#       --input dehost \
#       --cores 4
# ============================================================


PROJECT_DIR="."
INPUT_MODE=""
CORES=2


# ============================================================
# Usage
# ============================================================

usage() {
    cat <<'EOF'
Usage:
  ./shell_tools/run_picrust_functional.sh \
      --input raw|dehost \
      [options]

Required:
  --input raw|dehost
      Select PICRUSt analysis branch.

Options:
  --cores N
      CPU cores used by pathway_pipeline.py.
      Default: 2

  --project-dir DIR
      Project root.
      Default: .

Examples:
  ./shell_tools/run_picrust_functional.sh \
      --input dehost \
      --cores 4

  ./shell_tools/run_picrust_functional.sh \
      --input raw \
      --cores 2
EOF
}


# ============================================================
# Parse arguments
# ============================================================

while [[ $# -gt 0 ]]; do

    case "$1" in

        --input)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --input requires a value"
                exit 1
            fi

            INPUT_MODE="$2"
            shift 2
            ;;

        --cores)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --cores requires a value"
                exit 1
            fi

            CORES="$2"
            shift 2
            ;;

        --project-dir)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --project-dir requires a value"
                exit 1
            fi

            PROJECT_DIR="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "[ERROR] Unknown option: $1"
            echo
            usage
            exit 1
            ;;
    esac

done


# ============================================================
# Validate arguments
# ============================================================

case "${INPUT_MODE}" in
    raw|dehost)
        ;;
    *)
        echo "[ERROR] --input raw|dehost is required"
        exit 1
        ;;
esac


if ! [[ "${CORES}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --cores must be a positive integer"
    exit 1
fi


# ============================================================
# Detect Conda environment
# ============================================================

CURRENT_ENV="${CONDA_DEFAULT_ENV:-}"


case "${CURRENT_ENV}" in

    picrust2)
        METHOD="picrust2"
        ;;

    picrust2sc)
        METHOD="picrust2sc"
        ;;

    *)
        echo "[ERROR] Unsupported Conda environment"
        echo "[INFO] Current environment: ${CURRENT_ENV:-<none>}"
        echo
        echo "Activate:"
        echo "  conda activate picrust2"
        echo "or"
        echo "  conda activate picrust2sc"
        exit 1
        ;;
esac


# ============================================================
# Project paths
# ============================================================

PROJECT_DIR="$(
    cd "${PROJECT_DIR}" &&
    pwd
)"


RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"

PICRUST_OUT="${PROJECT_DIR}/picrust/${METHOD}/${INPUT_MODE}"

PROVENANCE="${PICRUST_OUT}/provenance.txt"

KO_DIR="${PICRUST_OUT}/KO_metagenome_out"
EC_DIR="${PICRUST_OUT}/EC_metagenome_out"
KEGG_DIR="${PICRUST_OUT}/KEGG_pathways_out"

TEMP_DIR="${PICRUST_OUT}/intermediate/functional"

STAGE_FILE="${PICRUST_OUT}/functional_status.txt"


# ============================================================
# Main input files
# ============================================================

KO_UNSTRAT="${KO_DIR}/pred_metagenome_unstrat.tsv.gz"
KO_CONTRIB="${KO_DIR}/pred_metagenome_contrib.tsv.gz"

EC_UNSTRAT="${EC_DIR}/pred_metagenome_unstrat.tsv.gz"


# ============================================================
# Final description outputs
# ============================================================

KO_DESC_OUT="${KO_DIR}/pred_metagenome_unstrat_descrip.tsv.gz"

EC_DESC_OUT="${EC_DIR}/pred_metagenome_unstrat_descrip.tsv.gz"


# ============================================================
# Temporary files
# ============================================================

KO_DESC_TMP="${TEMP_DIR}/KO_description_raw.tsv.gz"
EC_DESC_TMP="${TEMP_DIR}/EC_description_raw.tsv.gz"

EC_DESC_INPUT="${EC_UNSTRAT}"

KO_KEGG_INPUT="${KO_UNSTRAT}"
KO_KEGG_CONTRIB_INPUT="${KO_CONTRIB}"


# PICRUSt2-SC temporary adapters
SC_EC_DESC_INPUT="${TEMP_DIR}/EC_for_description.tsv.gz"
SC_KO_KEGG_INPUT="${TEMP_DIR}/KO_for_KEGG.tsv.gz"
SC_KO_KEGG_CONTRIB_INPUT="${TEMP_DIR}/KO_contrib_for_KEGG.tsv.gz"


if [[ "${METHOD}" == "picrust2sc" ]]; then
    EC_DESC_INPUT="${SC_EC_DESC_INPUT}"
    KO_KEGG_INPUT="${SC_KO_KEGG_INPUT}"
    KO_KEGG_CONTRIB_INPUT="${SC_KO_KEGG_CONTRIB_INPUT}"
fi


# ============================================================
# Validate provenance
# ============================================================

validate_provenance() {

    if [[ ! -f "${PROVENANCE}" ]]; then
        echo "[ERROR] provenance.txt not found:"
        echo "  ${PROVENANCE}"
        echo
        echo "[INFO] Run placement first:"
        echo "  ./shell_tools/run_picrust_place.sh --input ${INPUT_MODE}"
        exit 1
    fi


    local provenance_method
    local provenance_input


    provenance_method="$(
        grep '^method=' "${PROVENANCE}" |
        head -n 1 |
        cut -d= -f2- ||
        true
    )"


    provenance_input="$(
        grep '^input_mode=' "${PROVENANCE}" |
        head -n 1 |
        cut -d= -f2- ||
        true
    )"


    if [[ "${provenance_method}" != "${METHOD}" ]]; then
        echo "[ERROR] Provenance method mismatch"
        echo "[INFO] Expected : ${METHOD}"
        echo "[INFO] Found    : ${provenance_method:-NA}"
        exit 1
    fi


    if [[ "${provenance_input}" != "${INPUT_MODE}" ]]; then
        echo "[ERROR] Provenance input_mode mismatch"
        echo "[INFO] Expected : ${INPUT_MODE}"
        echo "[INFO] Found    : ${provenance_input:-NA}"
        exit 1
    fi
}


validate_provenance


# ============================================================
# Prepare directories
# ============================================================

mkdir -p \
    "${TEMP_DIR}" \
    "${KEGG_DIR}"


# ============================================================
# PICRUSt package resources
# ============================================================

PICRUST_PKG_DIR="$(
    python -c \
        'import picrust2, os; print(os.path.dirname(picrust2.__file__))'
)"


KEGG_MAP="${PICRUST_PKG_DIR}/default_files/pathway_mapfiles/KEGG_pathways_to_KO.tsv"

KEGG_DESC="${PICRUST_PKG_DIR}/default_files/description_mapfiles/KEGG_pathways_info.tsv.gz"


# ============================================================
# Validate required files
# ============================================================

if [[ ! -x "${RUN_IN_TMUX}" ]]; then
    echo "[ERROR] run_in_tmux.sh not found or not executable:"
    echo "  ${RUN_IN_TMUX}"
    exit 1
fi


for f in \
    "${KO_UNSTRAT}" \
    "${KO_CONTRIB}" \
    "${EC_UNSTRAT}" \
    "${KEGG_MAP}" \
    "${KEGG_DESC}"
do

    if [[ ! -f "${f}" ]]; then
        echo "[ERROR] Required file not found:"
        echo "  ${f}"
        exit 1
    fi

done


for cmd in \
    add_descriptions.py \
    pathway_pipeline.py \
    zcat \
    gzip \
    awk
do

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[ERROR] Required command not found: ${cmd}"
        echo "[INFO] Environment = ${CURRENT_ENV}"
        exit 1
    fi

done


# ============================================================
# Initialize stage tracking
# ============================================================

printf '%s\n' "QUEUED" > "${STAGE_FILE}"


# ============================================================
# Build tmux command
# ============================================================

CMD=$(cat <<EOF
set -euo pipefail


update_stage() {

    STAGE_TEXT="\$1"

    printf '%s\n' "\${STAGE_TEXT}" > '${STAGE_FILE}'

    echo
    echo '============================================================'
    echo "\${STAGE_TEXT}"
    echo '============================================================'
    echo
}


# ============================================================
# Prepare PICRUSt2-SC adapters
# ============================================================

if [[ '${METHOD}' == 'picrust2sc' ]]; then

    # --------------------------------------------------------
    # SC EC description adapter
    #
    # SC:
    #   EC:1.1.1.1
    #
    # add_descriptions EC map:
    #   1.1.1.1
    # --------------------------------------------------------

    update_stage 'Preparing SC EC description adapter'

    rm -f '${SC_EC_DESC_INPUT}'

    zcat '${EC_UNSTRAT}' |
        awk '
        BEGIN {
            FS = OFS = "\t"
        }

        NR == 1 {
            print
            next
        }

        {
            sub(/^EC:/, "", \$1)
            print
        }
        ' |
        gzip > '${SC_EC_DESC_INPUT}'


    # --------------------------------------------------------
    # SC KO adapter for KEGG pathway abundance
    #
    # SC metagenome:
    #   ko:K00001
    #
    # KEGG map:
    #   K00001
    # --------------------------------------------------------

    update_stage 'Preparing SC KO adapter for KEGG abundance'

    rm -f '${SC_KO_KEGG_INPUT}'

    zcat '${KO_UNSTRAT}' |
        awk '
        BEGIN {
            FS = OFS = "\t"
        }

        NR == 1 {
            print
            next
        }

        {
            sub(/^ko:/, "", \$1)
            print
        }
        ' |
        gzip > '${SC_KO_KEGG_INPUT}'

fi


# ============================================================
# Stage 1
# KO descriptions
# ============================================================

update_stage '1/5 KO descriptions'


rm -f \
    '${KO_DESC_TMP}' \
    '${KO_DESC_OUT}'


add_descriptions.py \
    -i '${KO_UNSTRAT}' \
    -m KO \
    -o '${KO_DESC_TMP}'


# Normalize final KO identifier:
#
# PICRUSt2:
#   K00001
#
# PICRUSt2-SC:
#   ko:K00001
#
# Canonical final output:
#   K00001

zcat '${KO_DESC_TMP}' |
    awk '
    BEGIN {
        FS = OFS = "\t"
    }

    NR == 1 {
        print
        next
    }

    {
        sub(/^ko:/, "", \$1)
        print
    }
    ' |
    gzip > '${KO_DESC_OUT}'



# ============================================================
# Stage 2
# EC descriptions
# ============================================================

update_stage '2/5 EC descriptions'


rm -f \
    '${EC_DESC_TMP}' \
    '${EC_DESC_OUT}'


add_descriptions.py \
    -i '${EC_DESC_INPUT}' \
    -m EC \
    -o '${EC_DESC_TMP}'


# Canonical final EC identifier:
#
# EC:1.1.1.1
# ->
# 1.1.1.1

zcat '${EC_DESC_TMP}' |
    awk '
    BEGIN {
        FS = OFS = "\t"
    }

    NR == 1 {
        print
        next
    }

    {
        sub(/^EC:/, "", \$1)
        print
    }
    ' |
    gzip > '${EC_DESC_OUT}'



# ============================================================
# Stage 3
# KEGG pathway abundance
# ============================================================

update_stage '3/5 KEGG pathway abundance'


rm -f \
    '${KEGG_DIR}/path_abun_unstrat.tsv.gz' \
    '${KEGG_DIR}/path_abun_unstrat_descrip.tsv.gz'


pathway_pipeline.py \
    --input '${KO_KEGG_INPUT}' \
    --out_dir '${KEGG_DIR}' \
    --no_regroup \
    --map '${KEGG_MAP}' \
    --processes ${CORES}



# ============================================================
# Stage 4
# KEGG pathway descriptions
# ============================================================

update_stage '4/5 KEGG pathway descriptions'


add_descriptions.py \
    -i '${KEGG_DIR}/path_abun_unstrat.tsv.gz' \
    --custom_map_table '${KEGG_DESC}' \
    -o '${KEGG_DIR}/path_abun_unstrat_descrip.tsv.gz'



# ============================================================
# Stage 5
# KEGG pathway contribution
# ============================================================

update_stage '5/5 KEGG pathway contribution'


# ------------------------------------------------------------
# Build the large SC contribution adapter only when required.
#
# contrib columns:
#   1 sample
#   2 function
#   3 taxon
#   ...
#
# SC:
#   function = ko:K00001
#
# KEGG:
#   function = K00001
# ------------------------------------------------------------

if [[ '${METHOD}' == 'picrust2sc' ]]; then

    update_stage '5/5 Preparing SC KO contribution adapter'

    rm -f '${SC_KO_KEGG_CONTRIB_INPUT}'

    zcat '${KO_CONTRIB}' |
        awk '
        BEGIN {
            FS = OFS = "\t"
        }

        NR == 1 {
            print
            next
        }

        {
            sub(/^ko:/, "", \$2)
            print
        }
        ' |
        gzip > '${SC_KO_KEGG_CONTRIB_INPUT}'

fi


update_stage '5/5 KEGG pathway contribution'


rm -f '${KEGG_DIR}/path_abun_contrib.tsv.gz'


pathway_pipeline.py \
    --input '${KO_KEGG_CONTRIB_INPUT}' \
    --out_dir '${KEGG_DIR}' \
    --no_regroup \
    --map '${KEGG_MAP}' \
    --processes ${CORES}



# ============================================================
# Complete
# ============================================================

update_stage 'COMPLETED'

echo
echo '============================================================'
echo ' PICRUSt functional workflow completed'
echo '============================================================'
echo
EOF
)


# ============================================================
# Summary before tmux submission
# ============================================================

echo
echo "============================================================"
echo " PICRUSt functional post-processing"
echo "============================================================"
echo "[INFO] Environment   : ${CURRENT_ENV}"
echo "[INFO] Method        : ${METHOD}"
echo "[INFO] Input mode    : ${INPUT_MODE}"
echo "[INFO] PICRUSt dir   : ${PICRUST_OUT}"
echo "[INFO] Provenance    : ${PROVENANCE}"
echo "[INFO] KO input      : ${KO_UNSTRAT}"
echo "[INFO] EC input      : ${EC_UNSTRAT}"
echo "[INFO] KO contrib    : ${KO_CONTRIB}"
echo "[INFO] KEGG map      : ${KEGG_MAP}"
echo "[INFO] KEGG output   : ${KEGG_DIR}"
echo "[INFO] Stage file    : ${STAGE_FILE}"
echo "[INFO] Cores         : ${CORES}"
echo
echo "[INFO] Sequential workflow:"
echo "  1/5 KO descriptions"
echo "  2/5 EC descriptions"
echo "  3/5 KEGG pathway abundance"
echo "  4/5 KEGG pathway descriptions"
echo "  5/5 KEGG pathway contribution"

if [[ "${METHOD}" == "picrust2sc" ]]; then
    echo
    echo "[INFO] PICRUSt2-SC adapters:"
    echo "  EC description : EC:1.1.1.1 -> 1.1.1.1"
    echo "  KEGG abundance : ko:K00001  -> K00001"
    echo "  KEGG contrib   : ko:K00001  -> K00001"
    echo
    echo "[INFO] Adapter conversion will run inside tmux."
fi

echo "============================================================"
echo


# ============================================================
# Submit
# ============================================================

JOB_TYPE=picrust_functional \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${INPUT_MODE}_${METHOD}_functional" \
STAGE_FILE="${STAGE_FILE}" \
CMD="${CMD}" \
"${RUN_IN_TMUX}"


echo
echo "============================================================"
echo " Functional job submitted"
echo "============================================================"
echo
echo "Check:"
echo
echo "  MODE=latest JOB_TYPE=picrust_functional \\"
echo "  ./shell_tools/check_tmux_jobs.sh"
echo
