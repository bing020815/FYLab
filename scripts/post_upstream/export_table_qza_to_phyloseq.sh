#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# FYLab - Export QIIME2 outputs to phyloseq
#
# 功能：
#   1. table.qza -> feature-table.biom -> otu_table.tsv
#   2. rep-seqs.qza -> dna-sequences.fasta
#   3. taxonomy.qza / taxonomy.tsv -> taxonomy.tsv
#   4. 從 logs/latest_taxonomy.status 反查 taxonomy 執行方式
#   5. 若為 classify-sklearn：
#        - 找出實際 classifier
#        - 計算 SHA256
#        - 查詢全域 classifier_manifest.tsv
#   6. 建立：
#        phyloseq/taxonomy_source.txt
#        phyloseq/analysis_metadata.txt
#
# 使用：
#   ./shell_tools/export_table_qza_to_phyloseq.sh .
#
# ============================================================


# ============================================================
# Basic settings
# ============================================================

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

TABLE_QZA="${PROJECT_DIR}/table.qza"
REPSEQS_QZA="${PROJECT_DIR}/rep-seqs.qza"

TAXONOMY_QZA="${PROJECT_DIR}/taxonomy.qza"
TAXONOMY_TSV="${PROJECT_DIR}/taxonomy.tsv"

# legacy / upstream taxonomy source record
PROJECT_TAXONOMY_SOURCE="${PROJECT_DIR}/taxonomy_source.txt"

OUTDIR_NAME="${OUTDIR_NAME:-phyloseq}"
OUTDIR="${PROJECT_DIR}/${OUTDIR_NAME}"

LOG_DIR="${PROJECT_DIR}/logs"
LATEST_TAXONOMY_STATUS="${LOG_DIR}/latest_taxonomy.status"

# ------------------------------------------------------------
# Global classifier registry
# ------------------------------------------------------------

CLASSIFIER_MANIFEST="${CLASSIFIER_MANIFEST:-/home/adprc/classifier/classifier_manifest.tsv}"

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

QIIME_ENV_NAME="${QIIME_ENV_NAME:-qiime2-2023.2}"

TIMEZONE="${TIMEZONE:-Asia/Taipei}"
export TZ="${TIMEZONE}"

# ------------------------------------------------------------
# Output metadata
# ------------------------------------------------------------

PHYLOSEQ_TAXONOMY_SOURCE="${OUTDIR}/taxonomy_source.txt"
ANALYSIS_METADATA="${OUTDIR}/analysis_metadata.txt"


# ============================================================
# Helpers
# ============================================================

read_kv_value() {

    local file="$1"
    local key="$2"

    grep "^${key}=" "${file}" 2>/dev/null \
        | head -n 1 \
        | cut -d'=' -f2-
}


check_cmd() {

    local cmd="$1"
    local hint="$2"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[ERROR] 找不到 ${cmd} 指令"
        echo "[ERROR] ${hint}"
        exit 1
    fi
}


check_file() {

    local file="$1"

    if [ ! -f "${file}" ]; then
        echo "[ERROR] 找不到輸入檔案：${file}"
        exit 1
    fi
}


resolve_path() {

    local path="$1"

    if [[ "${path}" = /* ]]; then
        printf '%s\n' "${path}"
    else
        printf '%s\n' "${PROJECT_DIR}/${path}"
    fi
}


sha256_file() {

    local file="$1"

    if [ ! -f "${file}" ]; then
        echo "unavailable"
        return
    fi

    if command -v sha256sum >/dev/null 2>&1; then

        sha256sum "${file}" \
            | awk '{print $1}'

    elif command -v shasum >/dev/null 2>&1; then

        shasum -a 256 "${file}" \
            | awk '{print $1}'

    else

        echo "unavailable"
    fi
}


extract_cmd_argument() {

    local cmd="$1"
    local arg="$2"

    printf '%s\n' "${cmd}" \
        | awk -v target="${arg}" '

        {
            for (i = 1; i <= NF; i++) {

                if ($i == target && i < NF) {

                    value = $(i + 1)

                    gsub(/^["'\''"]/, "", value)
                    gsub(/["'\''"]$/, "", value)

                    print value
                    exit
                }
            }
        }
        '
}


# ============================================================
# Determine taxonomy input
# ============================================================

prepare_taxonomy_source() {

    TAXONOMY_MODE="auto"
    TAXONOMY_SOURCE_TYPE=""
    TAXONOMY_SOURCE_FILE=""
    TAXONOMY_INPUT=""


    # --------------------------------------------------------
    # 若專案已有 taxonomy_source.txt，優先讀取
    # --------------------------------------------------------

    if [ -f "${PROJECT_TAXONOMY_SOURCE}" ]; then

        TAXONOMY_MODE="$(
            read_kv_value \
                "${PROJECT_TAXONOMY_SOURCE}" \
                "taxonomy_mode"
        )"

        TAXONOMY_SOURCE_TYPE="$(
            read_kv_value \
                "${PROJECT_TAXONOMY_SOURCE}" \
                "taxonomy_source_type"
        )"

        TAXONOMY_SOURCE_FILE="$(
            read_kv_value \
                "${PROJECT_TAXONOMY_SOURCE}" \
                "taxonomy_source_file"
        )"


        if [ -n "${TAXONOMY_SOURCE_FILE}" ]; then

            TAXONOMY_INPUT="$(
                resolve_path "${TAXONOMY_SOURCE_FILE}"
            )"
        fi
    fi


    # --------------------------------------------------------
    # fallback
    # --------------------------------------------------------

    if [ -z "${TAXONOMY_INPUT}" ]; then

        if [ -f "${TAXONOMY_QZA}" ]; then

            TAXONOMY_MODE="auto"
            TAXONOMY_SOURCE_TYPE="local_qza"
            TAXONOMY_SOURCE_FILE="taxonomy.qza"
            TAXONOMY_INPUT="${TAXONOMY_QZA}"

        elif [ -f "${TAXONOMY_TSV}" ]; then

            TAXONOMY_MODE="auto"
            TAXONOMY_SOURCE_TYPE="local_tsv"
            TAXONOMY_SOURCE_FILE="taxonomy.tsv"
            TAXONOMY_INPUT="${TAXONOMY_TSV}"

        else

            echo "[ERROR] 找不到 taxonomy 來源"
            echo "[ERROR] 請確認專案根目錄至少存在："
            echo "  taxonomy.qza"
            echo "  或 taxonomy.tsv"

            exit 1
        fi
    fi


    if [ ! -f "${TAXONOMY_INPUT}" ]; then

        echo "[ERROR] 找不到 taxonomy 來源檔案："
        echo "${TAXONOMY_INPUT}"

        exit 1
    fi
}


# ============================================================
# Export table.qza
# ============================================================

export_table_and_biom() {

    echo "[INFO] 匯出 table.qza"

    qiime tools export \
        --input-path "${TABLE_QZA}" \
        --output-path "${OUTDIR}"


    check_file "${OUTDIR}/feature-table.biom"


    echo "[INFO] feature-table.biom -> otu_table.tsv"

    biom convert \
        -i "${OUTDIR}/feature-table.biom" \
        -o "${OUTDIR}/otu_table.tsv" \
        --to-tsv


    check_file "${OUTDIR}/otu_table.tsv"
}


# ============================================================
# Export representative sequences
# ============================================================

export_repseqs() {

    echo "[INFO] 匯出 rep-seqs.qza"

    qiime tools export \
        --input-path "${REPSEQS_QZA}" \
        --output-path "${OUTDIR}"


    check_file "${OUTDIR}/dna-sequences.fasta"
}


# ============================================================
# Prepare taxonomy.tsv
# ============================================================

prepare_taxonomy_tsv() {

    case "${TAXONOMY_INPUT}" in

        *.qza)

            echo "[INFO] taxonomy 來源為 QZA"

            local tmp_dir="${OUTDIR}/taxonomy_export_tmp"

            rm -rf "${tmp_dir}"
            mkdir -p "${tmp_dir}"


            qiime tools export \
                --input-path "${TAXONOMY_INPUT}" \
                --output-path "${tmp_dir}"


            check_file "${tmp_dir}/taxonomy.tsv"


            cp \
                "${tmp_dir}/taxonomy.tsv" \
                "${OUTDIR}/taxonomy.tsv"


            rm -rf "${tmp_dir}"
            ;;


        *.tsv)

            echo "[INFO] taxonomy 來源為 TSV"

            cp \
                "${TAXONOMY_INPUT}" \
                "${OUTDIR}/taxonomy.tsv"
            ;;


        *)

            echo "[ERROR] 不支援 taxonomy 格式："
            echo "${TAXONOMY_INPUT}"

            exit 1
            ;;
    esac


    check_file "${OUTDIR}/taxonomy.tsv"
}


# ============================================================
# classifier_manifest lookup
# ============================================================

lookup_classifier_manifest() {

    local classifier_path="$1"
    local classifier_file

    classifier_file="$(basename "${classifier_path}")"

    CLASSIFIER_MANIFEST_ROW=""


    # --------------------------------------------------------
    # manifest 不存在時，不中止 export
    # --------------------------------------------------------

    if [ ! -f "${CLASSIFIER_MANIFEST}" ]; then

        echo "[WARN] 找不到 classifier manifest："
        echo "[WARN] ${CLASSIFIER_MANIFEST}"
        echo "[WARN] classifier path / filename / SHA256 仍會保留"
        echo "[WARN] 但 reference DB Metadata 將不完整"

        return 1
    fi


    # --------------------------------------------------------
    # lookup
    #
    # 優先：
    # classifier_path 完全一致
    #
    # fallback：
    # classifier_file + qiime env
    # --------------------------------------------------------

    CLASSIFIER_MANIFEST_ROW="$(
        awk -F '\t' \
            -v path="${classifier_path}" \
            -v file="${classifier_file}" \
            -v env="${CONDA_DEFAULT_ENV:-}" '

        NR == 1 {

            for (i = 1; i <= NF; i++) {

                gsub(/\r/, "", $i)

                idx[$i] = i
            }

            next
        }


        {

            for (i = 1; i <= NF; i++) {

                gsub(/\r/, "", $i)
            }


            # ------------------------------------------------
            # 第一優先：完整 classifier_path
            # ------------------------------------------------

            if (
                idx["classifier_path"] &&
                $idx["classifier_path"] == path
            ) {

                print

                found = 1

                exit
            }


            # ------------------------------------------------
            # 第二優先：
            # classifier_file + qiime_env_name
            # ------------------------------------------------

            if (
                idx["classifier_file"] &&
                idx["qiime_env_name"] &&
                $idx["classifier_file"] == file &&
                $idx["qiime_env_name"] == env
            ) {

                fallback = $0
            }
        }


        END {

            if (!found && fallback != "") {

                print fallback
            }
        }

        ' "${CLASSIFIER_MANIFEST}"
    )"


    [ -n "${CLASSIFIER_MANIFEST_ROW}" ]
}


get_manifest_value() {

    local key="$1"
    local header


    if [ -z "${CLASSIFIER_MANIFEST_ROW:-}" ]; then
        return
    fi


    header="$(
        head -n 1 "${CLASSIFIER_MANIFEST}" \
            | tr -d '\r'
    )"


    awk -F '\t' \
        -v header="${header}" \
        -v row="${CLASSIFIER_MANIFEST_ROW}" \
        -v key="${key}" '

    BEGIN {

        n = split(header, h, "\t")

        split(row, r, "\t")


        for (i = 1; i <= n; i++) {

            if (h[i] == key) {

                print r[i]

                exit
            }
        }
    }
    '
}


# ============================================================
# Infer taxonomy provenance
# ============================================================

infer_taxonomy_provenance() {

    # --------------------------------------------------------
    # defaults
    # --------------------------------------------------------

    TAXONOMY_JOB_STATUS="unknown"
    TAXONOMY_JOB_NAME=""
    TAXONOMY_JOB_ID=""
    TAXONOMY_JOB_START=""
    TAXONOMY_JOB_END=""

    TAXONOMY_METHOD="unknown"
    TAXONOMY_CMD=""

    CLASSIFIER_PATH=""
    CLASSIFIER_FILE=""
    CLASSIFIER_SHA256=""

    REFERENCE_READS=""
    REFERENCE_TAXONOMY=""

    DB_KEY=""
    DB_FAMILY=""
    DB_VARIANT=""
    DB_VERSION=""
    REGION=""

    QIIME_RELEASE=""
    QIIME_VERSION=""
    QIIME_ENV=""
    SKLEARN_VERSION=""
    TRAINING_TYPE=""


    # --------------------------------------------------------
    # taxonomy tmux status
    # --------------------------------------------------------

    if [ ! -f "${LATEST_TAXONOMY_STATUS}" ]; then

        echo "[WARN] 找不到："
        echo "[WARN] ${LATEST_TAXONOMY_STATUS}"
        echo "[WARN] taxonomy provenance 將不完整"

        return
    fi


    TAXONOMY_JOB_STATUS="$(
        read_kv_value \
            "${LATEST_TAXONOMY_STATUS}" \
            "status"
    )"


    TAXONOMY_JOB_NAME="$(
        read_kv_value \
            "${LATEST_TAXONOMY_STATUS}" \
            "job_name"
    )"


    TAXONOMY_JOB_ID="$(
        read_kv_value \
            "${LATEST_TAXONOMY_STATUS}" \
            "job_id"
    )"


    TAXONOMY_JOB_START="$(
        read_kv_value \
            "${LATEST_TAXONOMY_STATUS}" \
            "start_time"
    )"


    TAXONOMY_JOB_END="$(
        read_kv_value \
            "${LATEST_TAXONOMY_STATUS}" \
            "end_time"
    )"


    TAXONOMY_CMD="$(
        read_kv_value \
            "${LATEST_TAXONOMY_STATUS}" \
            "cmd_full"
    )"


    if [ "${TAXONOMY_JOB_STATUS}" != "completed" ]; then

        echo "[WARN] latest taxonomy job status："
        echo "[WARN] ${TAXONOMY_JOB_STATUS}"
    fi


    # ========================================================
    # classify-sklearn
    # ========================================================

    if [[ "${TAXONOMY_CMD}" == *"classify-sklearn"* ]]; then

        TAXONOMY_METHOD="classify-sklearn"


        CLASSIFIER_PATH="$(
            extract_cmd_argument \
                "${TAXONOMY_CMD}" \
                "--i-classifier"
        )"


        if [ -n "${CLASSIFIER_PATH}" ]; then

            CLASSIFIER_FILE="$(
                basename "${CLASSIFIER_PATH}"
            )"


            CLASSIFIER_SHA256="$(
                sha256_file "${CLASSIFIER_PATH}"
            )"


            # ------------------------------------------------
            # lookup global manifest
            # ------------------------------------------------

            if lookup_classifier_manifest "${CLASSIFIER_PATH}"; then

                DB_KEY="$(
                    get_manifest_value db_key
                )"

                DB_FAMILY="$(
                    get_manifest_value db_family
                )"

                DB_VARIANT="$(
                    get_manifest_value db_variant
                )"

                DB_VERSION="$(
                    get_manifest_value db_version
                )"

                REGION="$(
                    get_manifest_value region
                )"

                QIIME_RELEASE="$(
                    get_manifest_value qiime_release
                )"

                QIIME_VERSION="$(
                    get_manifest_value qiime_version
                )"

                QIIME_ENV="$(
                    get_manifest_value qiime_env_name
                )"

                SKLEARN_VERSION="$(
                    get_manifest_value sklearn_version
                )"

                TRAINING_TYPE="$(
                    get_manifest_value training_type
                )"


            else

                echo "[WARN] classifier manifest 找不到對應 model："
                echo "[WARN] ${CLASSIFIER_PATH}"
            fi
        fi


    # ========================================================
    # classify-consensus-vsearch
    # ========================================================

    elif [[ "${TAXONOMY_CMD}" == *"classify-consensus-vsearch"* ]]; then

        TAXONOMY_METHOD="classify-consensus-vsearch"


        REFERENCE_READS="$(
            extract_cmd_argument \
                "${TAXONOMY_CMD}" \
                "--i-reference-reads"
        )"


        REFERENCE_TAXONOMY="$(
            extract_cmd_argument \
                "${TAXONOMY_CMD}" \
                "--i-reference-taxonomy"
        )"


    else

        echo "[WARN] 無法辨識 taxonomy command 類型"
    fi
}


# ============================================================
# taxonomy_source.txt
# ============================================================

write_taxonomy_source() {

    cat > "${PHYLOSEQ_TAXONOMY_SOURCE}" <<EOF
taxonomy_mode=${TAXONOMY_MODE}
taxonomy_source_type=${TAXONOMY_SOURCE_TYPE}
taxonomy_source_file=${TAXONOMY_SOURCE_FILE}

taxonomy_method=${TAXONOMY_METHOD}

taxonomy_job_status=${TAXONOMY_JOB_STATUS}
taxonomy_job_name=${TAXONOMY_JOB_NAME}
taxonomy_job_id=${TAXONOMY_JOB_ID}
taxonomy_job_start=${TAXONOMY_JOB_START}
taxonomy_job_end=${TAXONOMY_JOB_END}

reference_db=${DB_FAMILY}
reference_db_key=${DB_KEY}
reference_db_variant=${DB_VARIANT}
reference_db_version=${DB_VERSION}

classifier_region=${REGION}
classifier_file=${CLASSIFIER_FILE}
classifier_path=${CLASSIFIER_PATH}
classifier_sha256=${CLASSIFIER_SHA256}
classifier_training_type=${TRAINING_TYPE}

reference_reads=${REFERENCE_READS}
reference_taxonomy=${REFERENCE_TAXONOMY}

qiime_release=${QIIME_RELEASE}
qiime_version=${QIIME_VERSION}
qiime_env_name=${QIIME_ENV}
sklearn_version=${SKLEARN_VERSION}
EOF
}


# ============================================================
# analysis_metadata.txt
# ============================================================

write_analysis_metadata() {

    cat > "${ANALYSIS_METADATA}" <<EOF
metadata_version=1

phyloseq_exported_at=$(date --iso-8601=seconds)
phyloseq_export_env=${CONDA_DEFAULT_ENV:-unknown}

taxonomy_method=${TAXONOMY_METHOD}
taxonomy_job_status=${TAXONOMY_JOB_STATUS}

reference_db=${DB_FAMILY}
reference_db_key=${DB_KEY}
reference_db_variant=${DB_VARIANT}
reference_db_version=${DB_VERSION}

classifier_region=${REGION}
classifier_file=${CLASSIFIER_FILE}
classifier_path=${CLASSIFIER_PATH}
classifier_sha256=${CLASSIFIER_SHA256}
classifier_training_type=${TRAINING_TYPE}

taxonomy_qiime_release=${QIIME_RELEASE}
taxonomy_qiime_version=${QIIME_VERSION}
taxonomy_qiime_env=${QIIME_ENV}
taxonomy_sklearn_version=${SKLEARN_VERSION}

reference_reads=${REFERENCE_READS}
reference_taxonomy=${REFERENCE_TAXONOMY}

dehost_performed=false
EOF
}


# ============================================================
# Show provenance
# ============================================================

show_provenance() {

    echo
    echo "============================================================"
    echo " Taxonomy provenance"
    echo "============================================================"

    echo "[INFO] method              = ${TAXONOMY_METHOD}"
    echo "[INFO] taxonomy job        = ${TAXONOMY_JOB_NAME:-unknown}"
    echo "[INFO] taxonomy status     = ${TAXONOMY_JOB_STATUS}"


    if [ "${TAXONOMY_METHOD}" = "classify-sklearn" ]; then

        echo "[INFO] classifier          = ${CLASSIFIER_FILE:-unknown}"
        echo "[INFO] classifier path     = ${CLASSIFIER_PATH:-unknown}"

        echo
        echo "[INFO] classifier manifest = ${CLASSIFIER_MANIFEST}"

        echo "[INFO] reference DB        = ${DB_FAMILY:-unknown}"
        echo "[INFO] reference DB key    = ${DB_KEY:-unknown}"
        echo "[INFO] DB variant          = ${DB_VARIANT:-unknown}"
        echo "[INFO] DB version          = ${DB_VERSION:-unknown}"
        echo "[INFO] region              = ${REGION:-unknown}"

        echo "[INFO] QIIME env           = ${QIIME_ENV:-unknown}"
        echo "[INFO] QIIME version       = ${QIIME_VERSION:-unknown}"
        echo "[INFO] sklearn version     = ${SKLEARN_VERSION:-unknown}"


    elif [ "${TAXONOMY_METHOD}" = "classify-consensus-vsearch" ]; then

        echo "[INFO] reference reads     = ${REFERENCE_READS:-unknown}"
        echo "[INFO] reference taxonomy  = ${REFERENCE_TAXONOMY:-unknown}"
    fi


    echo "============================================================"
}


# ============================================================
# Main
# ============================================================

main() {

    check_cmd \
        "qiime" \
        "請先啟用 QIIME2 環境，例如：conda activate ${QIIME_ENV_NAME}"


    check_cmd \
        "biom" \
        "請確認目前 QIIME2 環境包含 biom"


    check_file "${TABLE_QZA}"
    check_file "${REPSEQS_QZA}"


    prepare_taxonomy_source


    mkdir -p "${OUTDIR}"


    echo
    echo "[INFO] PROJECT_DIR          = ${PROJECT_DIR}"
    echo "[INFO] OUTPUT_DIR           = ${OUTDIR}"
    echo "[INFO] CURRENT_ENV          = ${CONDA_DEFAULT_ENV:-unknown}"
    echo "[INFO] TIMEZONE             = ${TIMEZONE}"
    echo "[INFO] TAXONOMY_SOURCE      = ${TAXONOMY_INPUT}"
    echo "[INFO] CLASSIFIER_MANIFEST  = ${CLASSIFIER_MANIFEST}"


    infer_taxonomy_provenance

    show_provenance


    export_table_and_biom

    export_repseqs

    prepare_taxonomy_tsv


    write_taxonomy_source

    write_analysis_metadata


    echo
    echo "============================================================"
    echo " Export completed"
    echo "============================================================"

    echo "[INFO] biom               = ${OUTDIR}/feature-table.biom"
    echo "[INFO] otu_table.tsv      = ${OUTDIR}/otu_table.tsv"
    echo "[INFO] dna-sequences      = ${OUTDIR}/dna-sequences.fasta"
    echo "[INFO] taxonomy.tsv       = ${OUTDIR}/taxonomy.tsv"

    echo
    echo "[INFO] taxonomy metadata  = ${PHYLOSEQ_TAXONOMY_SOURCE}"
    echo "[INFO] analysis metadata  = ${ANALYSIS_METADATA}"
}


main "$@"
