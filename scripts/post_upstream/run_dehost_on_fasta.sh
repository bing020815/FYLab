#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PHYLOSEQ_DIR="${PROJECT_DIR}/phyloseq"
DEHOST_WORK_DIR="${PHYLOSEQ_DIR}/dehost_work"

ANALYSIS_METADATA="${PHYLOSEQ_DIR}/analysis_metadata.txt"

HOST_DB="${HOST_DB:-}"
THREADS="${THREADS:-2}"

TOOLS_ENV_NAME="${TOOLS_ENV_NAME:-host-tools}"

HOST_GENOME_DIR="${HOST_GENOME_DIR:-/home/adprc/host_genome}"
HOST_INDEX_DIR="${HOST_INDEX_DIR:-${HOST_GENOME_DIR}/genome_index}"


# ============================================================
# Helpers
# ============================================================

check_cmd() {

    local cmd="$1"
    local hint="$2"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[ERROR] 找不到 ${cmd} 指令"
        echo "[ERROR] ${hint}"
        exit 1
    fi
}


count_fasta_sequences() {

    local file="$1"

    if [ ! -f "${file}" ]; then
        echo "0"
        return
    fi

    grep -c '^>' "${file}" || true
}


upsert_metadata() {

    local file="$1"
    local key="$2"
    local value="$3"

    mkdir -p "$(dirname "${file}")"

    if [ ! -f "${file}" ]; then
        touch "${file}"
    fi


    if grep -q "^${key}=" "${file}" 2>/dev/null; then

        local tmp_file
        tmp_file="$(mktemp)"

        awk \
            -v key="${key}" \
            -v value="${value}" '
        BEGIN {
            FS="="
        }

        $1 == key {
            print key "=" value
            next
        }

        {
            print
        }

        ' "${file}" > "${tmp_file}"

        mv "${tmp_file}" "${file}"

    else

        printf '%s=%s\n' \
            "${key}" \
            "${value}" \
            >> "${file}"
    fi
}


# ============================================================
# Resolve host index
# ============================================================

resolve_host_index() {

    case "${HOST_DB}" in

        dog)
            HOST_INDEX="${HOST_INDEX_DIR}/dog_genome/host_genome_index"
            ;;

        cat)
            HOST_INDEX="${HOST_INDEX_DIR}/cat_genome/host_genome_index"
            ;;

        human)
            HOST_INDEX="${HOST_INDEX_DIR}/human_genome/host_genome_index"
            ;;

        mouse)
            HOST_INDEX="${HOST_INDEX_DIR}/mouse_genome/host_genome_index"
            ;;

        cattle)
            HOST_INDEX="${HOST_INDEX_DIR}/cattle_genome/host_genome_index"
            ;;

        duck)
            HOST_INDEX="${HOST_INDEX_DIR}/duck_genome/host_genome_index"
            ;;

        goat)
            HOST_INDEX="${HOST_INDEX_DIR}/goat_genome/host_genome_index"
            ;;

        horse)
            HOST_INDEX="${HOST_INDEX_DIR}/horse_genome/host_genome_index"
            ;;

        pig)
            HOST_INDEX="${HOST_INDEX_DIR}/pig_genome/host_genome_index"
            ;;

        chicken)
            HOST_INDEX="${HOST_INDEX_DIR}/chicken_genome/host_genome_index"
            ;;

        rabbit)
            HOST_INDEX="${HOST_INDEX_DIR}/rabbit_genome/host_genome_index"
            ;;

        sheep)
            HOST_INDEX="${HOST_INDEX_DIR}/sheep_genome/host_genome_index"
            ;;

        turkey)
            HOST_INDEX="${HOST_INDEX_DIR}/turkey_genome/host_genome_index"
            ;;

        *)

            echo "[ERROR] 不支援的 HOST_DB：${HOST_DB}"
            echo "[ERROR] 目前支援："
            echo "dog / cat / human / mouse / cattle / duck / goat / horse / pig / chicken / rabbit / sheep / turkey"
            exit 1
            ;;
    esac
}


# ============================================================
# Write dehost metadata
# ============================================================

write_dehost_metadata() {

    local bowtie2_version
    local samtools_version
    local seqkit_version

    local input_count
    local host_count
    local nonhost_count

    local alignment_rate


    bowtie2_version="$(
        bowtie2 --version 2>/dev/null \
        | head -n 1 \
        | sed 's/^[[:space:]]*//'
    )"

    samtools_version="$(
        samtools --version 2>/dev/null \
        | head -n 1 \
        | sed 's/^[[:space:]]*//'
    )"

    seqkit_version="$(
        seqkit version 2>/dev/null \
        | head -n 1 \
        | sed 's/^[[:space:]]*//'
    )"


    input_count="$(
        count_fasta_sequences "${INPUT_FASTA}"
    )"

    host_count="$(
        count_fasta_sequences \
            "${DEHOST_WORK_DIR}/host_reads.fasta"
    )"

    nonhost_count="$(
        count_fasta_sequences \
            "${DEHOST_WORK_DIR}/nonhost.fasta"
    )"


    alignment_rate=""

    if [ -f "${DEHOST_WORK_DIR}/mapping_host_genome.txt" ]; then

        alignment_rate="$(
            grep "overall alignment rate" \
                "${DEHOST_WORK_DIR}/mapping_host_genome.txt" \
                2>/dev/null \
            | tail -n 1 \
            | awk '{print $1}'
        )"
    fi


    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_performed" \
        "true"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_host_db" \
        "${HOST_DB}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_host_index" \
        "${HOST_INDEX}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_input_fasta" \
        "${INPUT_FASTA}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_threads" \
        "${THREADS}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_environment" \
        "${CONDA_DEFAULT_ENV:-unknown}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_bowtie2_version" \
        "${bowtie2_version}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_samtools_version" \
        "${samtools_version}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_seqkit_version" \
        "${seqkit_version}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_input_features" \
        "${input_count}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_host_features" \
        "${host_count}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_nonhost_features" \
        "${nonhost_count}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_alignment_rate" \
        "${alignment_rate}"

    upsert_metadata \
        "${ANALYSIS_METADATA}" \
        "dehost_completed_at" \
        "$(date --iso-8601=seconds)"
}


# ============================================================
# Main
# ============================================================

main() {

    check_cmd \
        "bowtie2" \
        "請先啟用對應環境，例如：conda activate ${TOOLS_ENV_NAME}"

    check_cmd \
        "samtools" \
        "請先啟用對應環境，例如：conda activate ${TOOLS_ENV_NAME}"

    check_cmd \
        "seqkit" \
        "請先啟用對應環境，例如：conda activate ${TOOLS_ENV_NAME}"


    if [ -z "${HOST_DB}" ]; then
        echo "[ERROR] 請指定 HOST_DB，例如：human / mouse / pig / chicken"
        exit 1
    fi


    if [ ! -d "${PHYLOSEQ_DIR}" ]; then
        echo "[ERROR] 找不到 phyloseq 資料夾：${PHYLOSEQ_DIR}"
        exit 1
    fi


    mkdir -p "${DEHOST_WORK_DIR}"


    # --------------------------------------------------------
    # Step 1. Input FASTA
    # --------------------------------------------------------

    echo "[INFO] Step 1. 判斷 dehost 輸入 fasta"

    FILTERED_FASTA="${DEHOST_WORK_DIR}/filtered_dna-sequences.fasta"
    RAW_FASTA="${PHYLOSEQ_DIR}/dna-sequences.fasta"


    if [ -f "${FILTERED_FASTA}" ]; then

        INPUT_FASTA="${FILTERED_FASTA}"

        echo "[INFO] 偵測到長度篩選後序列"
        echo "[INFO] 使用：${INPUT_FASTA}"

    elif [ -f "${RAW_FASTA}" ]; then

        INPUT_FASTA="${RAW_FASTA}"

        echo "[INFO] 未偵測到長度篩選後序列"
        echo "[INFO] 使用：${INPUT_FASTA}"

    else

        echo "[ERROR] 找不到可用 FASTA"
        echo "[ERROR] 請確認至少存在："
        echo "  - ${FILTERED_FASTA}"
        echo "  - ${RAW_FASTA}"

        exit 1
    fi


    # --------------------------------------------------------
    # Step 2. Host index
    # --------------------------------------------------------

    echo "[INFO] Step 2. 判斷 host genome index"

    resolve_host_index


    if ! compgen -G "${HOST_INDEX}"'*.bt2*' > /dev/null; then

        echo "[ERROR] 找不到 bowtie2 index：${HOST_INDEX}"
        echo "[ERROR] HOST_DB        = ${HOST_DB}"
        echo "[ERROR] HOST_INDEX_DIR = ${HOST_INDEX_DIR}"

        exit 1
    fi


    echo
    echo "[INFO] HOST_DB         = ${HOST_DB}"
    echo "[INFO] HOST_INDEX      = ${HOST_INDEX}"
    echo "[INFO] HOST_INDEX_DIR  = ${HOST_INDEX_DIR}"
    echo "[INFO] INPUT_FASTA     = ${INPUT_FASTA}"
    echo "[INFO] THREADS         = ${THREADS}"
    echo "[INFO] DEHOST_WORK_DIR = ${DEHOST_WORK_DIR}"


    # --------------------------------------------------------
    # Step 3. Bowtie2
    # --------------------------------------------------------

    echo "[INFO] Step 3. 使用 bowtie2 比對 host genome"

    bowtie2 \
        -x "${HOST_INDEX}" \
        -f \
        -U "${INPUT_FASTA}" \
        -p "${THREADS}" \
        -S "${DEHOST_WORK_DIR}/mapping_host_genome.sam" \
        2> "${DEHOST_WORK_DIR}/mapping_host_genome.txt"


    # --------------------------------------------------------
    # Step 4. SAM -> BAM
    # --------------------------------------------------------

    echo "[INFO] Step 4. SAM -> BAM"

    samtools view \
        -h \
        -b \
        "${DEHOST_WORK_DIR}/mapping_host_genome.sam" \
        -o "${DEHOST_WORK_DIR}/mapping_host_genome.bam"


    # --------------------------------------------------------
    # Step 5. Host reads
    # --------------------------------------------------------

    echo "[INFO] Step 5. 篩出 host reads"

    samtools view \
        -h \
        -b \
        -F 4 \
        "${DEHOST_WORK_DIR}/mapping_host_genome.bam" \
        > "${DEHOST_WORK_DIR}/mapped_host_genome.bam"


    # --------------------------------------------------------
    # Step 6. Sort host BAM
    # --------------------------------------------------------

    echo "[INFO] Step 6. 排序 host BAM"

    samtools sort \
        -n \
        "${DEHOST_WORK_DIR}/mapped_host_genome.bam" \
        -o "${DEHOST_WORK_DIR}/sorted_host.bam"


    # --------------------------------------------------------
    # Step 7. Host FASTA
    # --------------------------------------------------------

    echo "[INFO] Step 7. 匯出 host_reads.fasta"

    samtools fasta \
        -@ "${THREADS}" \
        "${DEHOST_WORK_DIR}/sorted_host.bam" \
        -F 4 \
        -0 "${DEHOST_WORK_DIR}/host_reads.fasta"


    # --------------------------------------------------------
    # Step 8. Non-host reads
    # --------------------------------------------------------

    echo "[INFO] Step 8. 篩出 non-host reads"

    samtools view \
        -h \
        -b \
        -f 4 \
        "${DEHOST_WORK_DIR}/mapping_host_genome.bam" \
        > "${DEHOST_WORK_DIR}/nonhost.bam"


    # --------------------------------------------------------
    # Step 9. Sort non-host BAM
    # --------------------------------------------------------

    echo "[INFO] Step 9. 排序 non-host BAM"

    samtools sort \
        -n \
        "${DEHOST_WORK_DIR}/nonhost.bam" \
        -o "${DEHOST_WORK_DIR}/nonhost_sorted.bam"


    # --------------------------------------------------------
    # Step 10. Non-host FASTA
    # --------------------------------------------------------

    echo "[INFO] Step 10. 匯出 nonhost.fasta"

    samtools fasta \
        -@ "${THREADS}" \
        "${DEHOST_WORK_DIR}/nonhost_sorted.bam" \
        -f 4 \
        -0 "${DEHOST_WORK_DIR}/nonhost.fasta"


    # --------------------------------------------------------
    # Step 11. Alignment summary
    # --------------------------------------------------------

    echo "[INFO] Step 11. bowtie2 alignment 摘要"

    if [ -f "${DEHOST_WORK_DIR}/mapping_host_genome.txt" ]; then

        if grep -q \
            "overall alignment rate" \
            "${DEHOST_WORK_DIR}/mapping_host_genome.txt"
        then

            grep \
                "overall alignment rate" \
                "${DEHOST_WORK_DIR}/mapping_host_genome.txt"

        else

            echo "[WARN] 找不到 overall alignment rate"
            echo "[WARN] 請檢查："
            echo "${DEHOST_WORK_DIR}/mapping_host_genome.txt"
        fi

    else

        echo "[WARN] 找不到 bowtie2 log"
    fi


    # --------------------------------------------------------
    # Step 12. FASTA statistics
    # --------------------------------------------------------

    echo "[INFO] Step 12. dehost 前後 FASTA 統計"


    if command -v column >/dev/null 2>&1; then

        if [ -f "${FILTERED_FASTA}" ]; then

            seqkit stats -T \
                "${RAW_FASTA}" \
                "${FILTERED_FASTA}" \
                "${DEHOST_WORK_DIR}/host_reads.fasta" \
                "${DEHOST_WORK_DIR}/nonhost.fasta" \
                | column -t

        else

            seqkit stats -T \
                "${RAW_FASTA}" \
                "${DEHOST_WORK_DIR}/host_reads.fasta" \
                "${DEHOST_WORK_DIR}/nonhost.fasta" \
                | column -t
        fi

    else

        if [ -f "${FILTERED_FASTA}" ]; then

            seqkit stats -T \
                "${RAW_FASTA}" \
                "${FILTERED_FASTA}" \
                "${DEHOST_WORK_DIR}/host_reads.fasta" \
                "${DEHOST_WORK_DIR}/nonhost.fasta"

        else

            seqkit stats -T \
                "${RAW_FASTA}" \
                "${DEHOST_WORK_DIR}/host_reads.fasta" \
                "${DEHOST_WORK_DIR}/nonhost.fasta"
        fi
    fi


    # --------------------------------------------------------
    # Step 13. Metadata
    # --------------------------------------------------------

    echo "[INFO] Step 13. 更新 analysis_metadata.txt"

    write_dehost_metadata


    echo
    echo "============================================================"
    echo " Dehost completed"
    echo "============================================================"

    echo "[INFO] host log       = ${DEHOST_WORK_DIR}/mapping_host_genome.txt"
    echo "[INFO] host fasta     = ${DEHOST_WORK_DIR}/host_reads.fasta"
    echo "[INFO] nonhost fasta  = ${DEHOST_WORK_DIR}/nonhost.fasta"
    echo "[INFO] metadata       = ${ANALYSIS_METADATA}"
}


main "$@"
