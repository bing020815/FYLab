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
# Supported:
#   picrust2
#   picrust2sc
#
# Usage:
#   ./shell_tools/run_picrust_functional.sh
#   ./shell_tools/run_picrust_functional.sh --cores 4
# ============================================================


PROJECT_DIR="."
CORES=2


usage() {

    cat <<'EOF'
Usage:
  ./shell_tools/run_picrust_functional.sh [options]

Options:
  --cores N
      CPU cores used by KEGG pathway prediction
      Default: 2

  --project-dir DIR
      Project root
      Default: .

Examples:
  ./shell_tools/run_picrust_functional.sh

  ./shell_tools/run_picrust_functional.sh --cores 4
EOF
}


while [[ $# -gt 0 ]]; do

    case "$1" in

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


if ! [[ "${CORES}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --cores must be a positive integer"
    exit 1
fi


# ============================================================
# Environment
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
# Paths
# ============================================================

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

RUN_IN_TMUX="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"

PICRUST_OUT="${PROJECT_DIR}/picrust/${METHOD}"

KO_DIR="${PICRUST_OUT}/KO_metagenome_out"
EC_DIR="${PICRUST_OUT}/EC_metagenome_out"
KEGG_DIR="${PICRUST_OUT}/KEGG_pathways_out"

TEMP_DIR="${PICRUST_OUT}/intermediate/functional"

STAGE_FILE="${PICRUST_OUT}/functional_status.txt"


KO_UNSTRAT="${KO_DIR}/pred_metagenome_unstrat.tsv.gz"
KO_CONTRIB="${KO_DIR}/pred_metagenome_contrib.tsv.gz"

EC_UNSTRAT="${EC_DIR}/pred_metagenome_unstrat.tsv.gz"


KO_DESC_OUT="${KO_DIR}/pred_metagenome_unstrat_descrip.tsv.gz"
EC_DESC_OUT="${EC_DIR}/pred_metagenome_unstrat_descrip.tsv.gz"


mkdir -p \
    "${PICRUST_OUT}" \
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
# Validate
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
    pathway_pipeline.py
do

    if ! command -v "${cmd}" >/dev/null 2>&1; then

        echo "[ERROR] ${cmd} not found in current environment"
        echo "[INFO] Environment = ${CURRENT_ENV}"

        exit 1
    fi

done


# ============================================================
# Description adapters
# ============================================================

KO_DESC_INPUT="${KO_UNSTRAT}"
EC_DESC_INPUT="${EC_UNSTRAT}"


if [[ "${METHOD}" == "picrust2sc" ]]; then

    # --------------------------------------------------------
    # SC KO description map:
    #
    # prediction:
    #   K00001
    #
    # built-in description map:
    #   ko:K00001
    #
    # Prefix is added only to temporary annotation input.
    # --------------------------------------------------------

    KO_DESC_INPUT="${TEMP_DIR}/KO_for_description.tsv.gz"

    zcat "${KO_UNSTRAT}" |
        awk '
        BEGIN {
            FS = OFS = "\t"
        }

        NR == 1 {
            print
            next
        }

        {
            if ($1 !~ /^ko:/) {
                $1 = "ko:" $1
            }

            print
        }
        ' |
        gzip > "${KO_DESC_INPUT}"


    # --------------------------------------------------------
    # SC EC:
    #
    # prediction can use:
    #   EC:1.1.1.1
    #
    # description map uses:
    #   1.1.1.1
    #
    # Prefix is removed only from temporary annotation input.
    # --------------------------------------------------------

    EC_DESC_INPUT="${TEMP_DIR}/EC_for_description.tsv.gz"

    zcat "${EC_UNSTRAT}" |
        awk '
        BEGIN {
            FS = OFS = "\t"
        }

        NR == 1 {
            print
            next
        }

        {
            sub(/^EC:/, "", $1)
            print
        }
        ' |
        gzip > "${EC_DESC_INPUT}"

fi


KO_DESC_TMP="${TEMP_DIR}/KO_description_raw.tsv.gz"
EC_DESC_TMP="${TEMP_DIR}/EC_description_raw.tsv.gz"


# ============================================================
# Initialize stage
# ============================================================

echo "QUEUED" > "${STAGE_FILE}"


# ============================================================
# Sequential workflow
# ============================================================

CMD="
set -euo pipefail


update_stage() {

    STAGE_TEXT=\"\$1\"

    printf '%s\n' \"\${STAGE_TEXT}\" > '${STAGE_FILE}'

    echo
    echo '============================================================'
    echo \"\${STAGE_TEXT}\"
    echo '============================================================'
    echo
}


update_stage '1/5 KO descriptions'


add_descriptions.py \
  -i '${KO_DESC_INPUT}' \
  -m KO \
  -o '${KO_DESC_TMP}'


zcat '${KO_DESC_TMP}' | \
awk '
BEGIN {
    FS = OFS = \"\t\"
}

NR == 1 {
    print
    next
}

{
    sub(/^ko:/, \"\", \$1)
    print
}
' | \
gzip > '${KO_DESC_OUT}'



update_stage '2/5 EC descriptions'


add_descriptions.py \
  -i '${EC_DESC_INPUT}' \
  -m EC \
  -o '${EC_DESC_TMP}'


zcat '${EC_DESC_TMP}' | \
awk '
BEGIN {
    FS = OFS = \"\t\"
}

NR == 1 {
    print
    next
}

{
    sub(/^EC:/, \"\", \$1)
    print
}
' | \
gzip > '${EC_DESC_OUT}'



update_stage '3/5 KEGG pathway abundance'


pathway_pipeline.py \
  --input '${KO_UNSTRAT}' \
  --out_dir '${KEGG_DIR}' \
  --no_regroup \
  --map '${KEGG_MAP}' \
  --processes ${CORES}



update_stage '4/5 KEGG pathway descriptions'


add_descriptions.py \
  -i '${KEGG_DIR}/path_abun_unstrat.tsv.gz' \
  --custom_map_table '${KEGG_DESC}' \
  -o '${KEGG_DIR}/path_abun_unstrat_descrip.tsv.gz'



update_stage '5/5 KEGG pathway contribution'


pathway_pipeline.py \
  --input '${KO_CONTRIB}' \
  --out_dir '${KEGG_DIR}' \
  --no_regroup \
  --map '${KEGG_MAP}' \
  --processes ${CORES}



update_stage 'COMPLETED'
"


# ============================================================
# Summary
# ============================================================

echo "============================================================"
echo " PICRUSt functional post-processing"
echo "============================================================"
echo "[INFO] Environment : ${CURRENT_ENV}"
echo "[INFO] Method      : ${METHOD}"
echo "[INFO] PICRUSt dir : ${PICRUST_OUT}"
echo "[INFO] KO input    : ${KO_UNSTRAT}"
echo "[INFO] EC input    : ${EC_UNSTRAT}"
echo "[INFO] KEGG map    : ${KEGG_MAP}"
echo "[INFO] KEGG output : ${KEGG_DIR}"
echo "[INFO] Stage file  : ${STAGE_FILE}"
echo "[INFO] Cores       : ${CORES}"
echo
echo "[INFO] Sequential stages:"
echo "  1/5 KO descriptions"
echo "  2/5 EC descriptions"
echo "  3/5 KEGG pathway abundance"
echo "  4/5 KEGG pathway descriptions"
echo "  5/5 KEGG pathway contribution"
echo "============================================================"


# ============================================================
# Submit
# ============================================================

JOB_TYPE=picrust_functional \
PROJECT_DIR="${PROJECT_DIR}" \
JOB_NAME="${METHOD}_functional" \
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
echo "  MODE=latest JOB_TYPE=picrust_functional ./shell_tools/check_tmux_jobs.sh"
echo
