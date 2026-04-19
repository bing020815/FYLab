#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PHYLOSEQ_DIR="${PROJECT_DIR}/phyloseq"
HOST_FILTER_DIR="${PHYLOSEQ_DIR}/host_filter"

HOST_DB="${HOST_DB:-all}"
THREADS="${THREADS:-2}"

QIIME_ENV_NAME="${QIIME_ENV_NAME:-host-tools}"

if ! command -v bowtie2 >/dev/null 2>&1; then
    echo "[ERROR] 找不到 bowtie2 指令"
    echo "[ERROR] 請先啟用對應環境，例如：conda activate ${QIIME_ENV_NAME}"
    exit 1
fi

if ! command -v samtools >/dev/null 2>&1; then
    echo "[ERROR] 找不到 samtools 指令"
    echo "[ERROR] 請先啟用對應環境，例如：conda activate ${QIIME_ENV_NAME}"
    exit 1
fi

if ! command -v seqkit >/dev/null 2>&1; then
    echo "[ERROR] 找不到 seqkit 指令"
    echo "[ERROR] 請先啟用對應環境，例如：conda activate ${QIIME_ENV_NAME}"
    exit 1
fi

mkdir -p "${HOST_FILTER_DIR}"

echo "[INFO] Step 1. 判斷 dehost 輸入 fasta"

FILTERED_FASTA="${HOST_FILTER_DIR}/filtered_dna-sequences.fasta"
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
        echo "[ERROR] 目前支援：all / dog / cat / mouse / cattle / duck / goat / horse / pig "
        exit 1
        ;;
esac

if ! ls "${HOST_INDEX}"*.bt2* >/dev/null 2>&1; then
    echo "[ERROR] 找不到 bowtie2 index：${HOST_INDEX}"
    exit 1
fi

echo "[INFO] HOST_DB     = ${HOST_DB}"
echo "[INFO] HOST_INDEX  = ${HOST_INDEX}"
echo "[INFO] INPUT_FASTA = ${INPUT_FASTA}"
echo "[INFO] THREADS     = ${THREADS}"

echo "[INFO] Step 3. 使用 bowtie2 比對 host genome"
bowtie2 \
  -x "${HOST_INDEX}" \
  -f \
  -U "${INPUT_FASTA}" \
  -p "${THREADS}" \
  -S "${HOST_FILTER_DIR}/mapping_host_genome.sam" \
  2> "${HOST_FILTER_DIR}/mapping_host_genome.txt"

echo "[INFO] Step 4. 將 SAM 轉成 BAM"
samtools view -h -b "${HOST_FILTER_DIR}/mapping_host_genome.sam" \
  -o "${HOST_FILTER_DIR}/mapping_host_genome.bam"

echo "[INFO] Step 5. 篩出已比對到 host 的序列"
samtools view -h -b -F 4 "${HOST_FILTER_DIR}/mapping_host_genome.bam" \
  > "${HOST_FILTER_DIR}/mapped_host_genome.bam"

echo "[INFO] Step 6. 排序 host BAM"
samtools sort -n "${HOST_FILTER_DIR}/mapped_host_genome.bam" \
  -o "${HOST_FILTER_DIR}/sorted_host.bam"

echo "[INFO] Step 7. 匯出 host_reads.fasta"
samtools fasta -@ "${THREADS}" "${HOST_FILTER_DIR}/sorted_host.bam" \
  -F 4 \
  -0 "${HOST_FILTER_DIR}/host_reads.fasta"

echo "[INFO] Step 8. 篩出未比對到 host 的序列"
samtools view -h -b -f 4 "${HOST_FILTER_DIR}/mapping_host_genome.bam" \
  > "${HOST_FILTER_DIR}/nonhost.bam"

echo "[INFO] Step 9. 排序 nonhost BAM"
samtools sort -n "${HOST_FILTER_DIR}/nonhost.bam" \
  -o "${HOST_FILTER_DIR}/nonhost_sorted.bam"

echo "[INFO] Step 10. 匯出 nonhost.fasta"
samtools fasta -@ "${THREADS}" "${HOST_FILTER_DIR}/nonhost_sorted.bam" \
  -f 4 \
  -0 "${HOST_FILTER_DIR}/nonhost.fasta"

echo "[INFO] Step 11. 顯示 fasta 統計"
seqkit stats "${INPUT_FASTA}" "${HOST_FILTER_DIR}/host_reads.fasta" "${HOST_FILTER_DIR}/nonhost.fasta"

echo
echo "[INFO] dehost 完成"
echo "[INFO] host log       = ${HOST_FILTER_DIR}/mapping_host_genome.txt"
echo "[INFO] host fasta     = ${HOST_FILTER_DIR}/host_reads.fasta"
echo "[INFO] nonhost fasta  = ${HOST_FILTER_DIR}/nonhost.fasta"
