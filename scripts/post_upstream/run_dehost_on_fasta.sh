#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PHYLOSEQ_DIR="${PROJECT_DIR}/phyloseq"
DEHOST_WORK_DIR="${PHYLOSEQ_DIR}/dehost_work"

HOST_DB="${HOST_DB:-all}"
THREADS="${THREADS:-2}"

TOOLS_ENV_NAME="${TOOLS_ENV_NAME:-host-tools}"

check_cmd() {
    local cmd="$1"
    local hint="$2"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[ERROR] 找不到 ${cmd} 指令"
        echo "[ERROR] ${hint}"
        exit 1
    fi
}

resolve_host_index() {
    case "${HOST_DB}" in
        all)
            HOST_INDEX="/home/adprc/host_genome/all_genome/host_genome_index"
            ;;
        dog)
            HOST_INDEX="/home/adprc/host_genome/dog_genome/host_genome_index"
            ;;
        cat)
            HOST_INDEX="/home/adprc/host_genome/cat_genome/host_genome_index"
            ;;
        mouse)
            HOST_INDEX="/home/adprc/host_genome/mouse_genome/host_genome_index"
            ;;
        cattle)
            HOST_INDEX="/home/adprc/host_genome/cattle_genome/host_genome_index"
            ;;
        duck)
            HOST_INDEX="/home/adprc/host_genome/duck_genome/host_genome_index"
            ;;
        goat)
            HOST_INDEX="/home/adprc/host_genome/goat_genome/host_genome_index"
            ;;
        horse)
            HOST_INDEX="/home/adprc/host_genome/horse_genome/host_genome_index"
            ;;
        pig)
            HOST_INDEX="/home/adprc/host_genome/pig_genome/host_genome_index"
            ;;
        *)
            echo "[ERROR] 不支援的 HOST_DB: ${HOST_DB}"
            echo "[ERROR] 目前支援：all / dog / cat / mouse / cattle / duck / goat / horse / pig"
            exit 1
            ;;
    esac
}

main() {
    check_cmd "bowtie2" "請先啟用對應環境，例如：conda activate ${TOOLS_ENV_NAME}"
    check_cmd "samtools" "請先啟用對應環境，例如：conda activate ${TOOLS_ENV_NAME}"
    check_cmd "seqkit" "請先啟用對應環境，例如：conda activate ${TOOLS_ENV_NAME}"

    mkdir -p "${DEHOST_WORK_DIR}"

    echo "[INFO] Step 1. 判斷 dehost 輸入 fasta"

    FILTERED_FASTA="${DEHOST_WORK_DIR}/filtered_dna-sequences.fasta"
    RAW_FASTA="${PHYLOSEQ_DIR}/dna-sequences.fasta"

    if [ -f "${FILTERED_FASTA}" ]; then
        INPUT_FASTA="${FILTERED_FASTA}"
        echo "[INFO] 偵測到長度篩選後序列，優先使用：${INPUT_FASTA}"
    elif [ -f "${RAW_FASTA}" ]; then
        INPUT_FASTA="${RAW_FASTA}"
        echo "[INFO] 未偵測到長度篩選後序列，使用原始代表性序列：${INPUT_FASTA}"
    else
        echo "[ERROR] 找不到可用的 fasta"
        echo "[ERROR] 請確認以下檔案至少存在一個："
        echo "  - ${FILTERED_FASTA}"
        echo "  - ${RAW_FASTA}"
        exit 1
    fi

    echo "[INFO] Step 2. 判斷 host genome index"
    resolve_host_index

    if ! ls "${HOST_INDEX}"*.bt2* >/dev/null 2>&1; then
        echo "[ERROR] 找不到 bowtie2 index：${HOST_INDEX}"
        exit 1
    fi

    echo "[INFO] HOST_DB         = ${HOST_DB}"
    echo "[INFO] HOST_INDEX      = ${HOST_INDEX}"
    echo "[INFO] INPUT_FASTA     = ${INPUT_FASTA}"
    echo "[INFO] THREADS         = ${THREADS}"
    echo "[INFO] DEHOST_WORK_DIR = ${DEHOST_WORK_DIR}"

    echo "[INFO] Step 3. 使用 bowtie2 比對 host genome"
    bowtie2 \
      -x "${HOST_INDEX}" \
      -f \
      -U "${INPUT_FASTA}" \
      -p "${THREADS}" \
      -S "${DEHOST_WORK_DIR}/mapping_host_genome.sam" \
      2> "${DEHOST_WORK_DIR}/mapping_host_genome.txt"

    echo "[INFO] Step 4. 將 SAM 轉成 BAM"
    samtools view -h -b "${DEHOST_WORK_DIR}/mapping_host_genome.sam" \
      -o "${DEHOST_WORK_DIR}/mapping_host_genome.bam"

    echo "[INFO] Step 5. 篩出已比對到 host 的序列"
    samtools view -h -b -F 4 "${DEHOST_WORK_DIR}/mapping_host_genome.bam" \
      > "${DEHOST_WORK_DIR}/mapped_host_genome.bam"

    echo "[INFO] Step 6. 排序 host BAM"
    samtools sort -n "${DEHOST_WORK_DIR}/mapped_host_genome.bam" \
      -o "${DEHOST_WORK_DIR}/sorted_host.bam"

    echo "[INFO] Step 7. 匯出 host_reads.fasta"
    samtools fasta -@ "${THREADS}" "${DEHOST_WORK_DIR}/sorted_host.bam" \
      -F 4 \
      -0 "${DEHOST_WORK_DIR}/host_reads.fasta"

    echo "[INFO] Step 8. 篩出未比對到 host 的序列"
    samtools view -h -b -f 4 "${DEHOST_WORK_DIR}/mapping_host_genome.bam" \
      > "${DEHOST_WORK_DIR}/nonhost.bam"

    echo "[INFO] Step 9. 排序 nonhost BAM"
    samtools sort -n "${DEHOST_WORK_DIR}/nonhost.bam" \
      -o "${DEHOST_WORK_DIR}/nonhost_sorted.bam"

    echo "[INFO] Step 10. 匯出 nonhost.fasta"
    samtools fasta -@ "${THREADS}" "${DEHOST_WORK_DIR}/nonhost_sorted.bam" \
      -f 4 \
      -0 "${DEHOST_WORK_DIR}/nonhost.fasta"

    echo "[INFO] Step 11. 顯示 bowtie2 alignment 摘要"
    if [ -f "${DEHOST_WORK_DIR}/mapping_host_genome.txt" ]; then
        if grep -q "overall alignment rate" "${DEHOST_WORK_DIR}/mapping_host_genome.txt"; then
            grep "overall alignment rate" "${DEHOST_WORK_DIR}/mapping_host_genome.txt"
        else
            echo "[WARN] 找不到 overall alignment rate，請手動檢查 ${DEHOST_WORK_DIR}/mapping_host_genome.txt"
        fi
    else
        echo "[WARN] 找不到 bowtie2 log：${DEHOST_WORK_DIR}/mapping_host_genome.txt"
    fi

    echo "[INFO] Step 12. 顯示 dehost 前後 fasta 統計摘要"
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

    echo
    echo "[INFO] dehost 完成"
    echo "[INFO] host log       = ${DEHOST_WORK_DIR}/mapping_host_genome.txt"
    echo "[INFO] host fasta     = ${DEHOST_WORK_DIR}/host_reads.fasta"
    echo "[INFO] nonhost fasta  = ${DEHOST_WORK_DIR}/nonhost.fasta"
}

main "$@"
