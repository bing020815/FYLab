#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

PHYLOSEQ_DIR="${PROJECT_DIR}/phyloseq"
DEHOST_WORK_DIR="${PHYLOSEQ_DIR}/dehost_work"
DEHOST_OUTPUT_DIR="${PHYLOSEQ_DIR}/dehost_output"

DEHOST_OTU_TSV="${DEHOST_OUTPUT_DIR}/dehost_otu_table.tsv"
DEHOST_OTU_BIOM="${DEHOST_OUTPUT_DIR}/dehost_otu_table.biom"
DEHOST_OTU_QZA="${DEHOST_OUTPUT_DIR}/dehost_otu_table.qza"

DEHOST_TAXONOMY_TSV="${DEHOST_OUTPUT_DIR}/dehost_taxonomy.tsv"
DEHOST_TAXONOMY_QZA="${DEHOST_OUTPUT_DIR}/dehost_taxonomy.qza"

REPSEQS_QZA="${PROJECT_DIR}/rep-seqs.qza"
DEHOST_REPSEQS_QZA="${DEHOST_OUTPUT_DIR}/dehost_rep_seqs.qza"
DEHOST_FASTA="${DEHOST_OUTPUT_DIR}/dehost_dna-sequences.fasta"

NONHOST_FASTA="${DEHOST_WORK_DIR}/nonhost.fasta"

QIIME_ENV_NAME="${QIIME_ENV_NAME:-qiime2-2023.2}"
LINK_DEHOST_FASTA="${LINK_DEHOST_FASTA:-true}"

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
        echo "[ERROR] 找不到 ${file}"
        exit 1
    fi
}

main() {
    check_cmd "qiime" "請先啟用 QIIME2 環境，例如：conda activate ${QIIME_ENV_NAME}"
    check_cmd "biom" "請先確認目前已啟用正確環境，例如：conda activate ${QIIME_ENV_NAME}"

    check_file "${DEHOST_OTU_TSV}"
    check_file "${DEHOST_TAXONOMY_TSV}"
    check_file "${REPSEQS_QZA}"

    mkdir -p "${DEHOST_OUTPUT_DIR}"

    echo "[INFO] PROJECT_DIR           = ${PROJECT_DIR}"
    echo "[INFO] DEHOST_WORK_DIR       = ${DEHOST_WORK_DIR}"
    echo "[INFO] DEHOST_OUTPUT_DIR     = ${DEHOST_OUTPUT_DIR}"
    echo "[INFO] 目前環境              = ${CONDA_DEFAULT_ENV:-unknown}"
    echo "[INFO] LINK_DEHOST_FASTA     = ${LINK_DEHOST_FASTA}"

    echo "[INFO] Step 1. dehost_otu_table.tsv 轉成 biom"
    biom convert \
      -i "${DEHOST_OTU_TSV}" \
      -o "${DEHOST_OTU_BIOM}" \
      --to-hdf5 \
      --table-type="OTU table"

    if [ ! -f "${DEHOST_OTU_BIOM}" ]; then
        echo "[ERROR] 找不到輸出的 biom：${DEHOST_OTU_BIOM}"
        exit 1
    fi

    echo "[INFO] Step 2. biom 匯入為 QIIME2 table"
    qiime tools import \
      --input-path "${DEHOST_OTU_BIOM}" \
      --type 'FeatureTable[Frequency]' \
      --input-format BIOMV210Format \
      --output-path "${DEHOST_OTU_QZA}"

    if [ ! -f "${DEHOST_OTU_QZA}" ]; then
        echo "[ERROR] 找不到輸出的 qza：${DEHOST_OTU_QZA}"
        exit 1
    fi

    echo "[INFO] Step 3. 由 dehost table 過濾 rep-seqs.qza"
    qiime feature-table filter-seqs \
      --i-data "${REPSEQS_QZA}" \
      --i-table "${DEHOST_OTU_QZA}" \
      --o-filtered-data "${DEHOST_REPSEQS_QZA}"

    if [ ! -f "${DEHOST_REPSEQS_QZA}" ]; then
        echo "[ERROR] 找不到輸出的 dehost rep-seqs：${DEHOST_REPSEQS_QZA}"
        exit 1
    fi

    echo "[INFO] Step 4. 將 dehost_taxonomy.tsv 匯入為 QIIME2 taxonomy"
    qiime tools import \
      --input-path "${DEHOST_TAXONOMY_TSV}" \
      --type 'FeatureData[Taxonomy]' \
      --input-format HeaderlessTSVTaxonomyFormat \
      --output-path "${DEHOST_TAXONOMY_QZA}"

    if [ ! -f "${DEHOST_TAXONOMY_QZA}" ]; then
        echo "[ERROR] 找不到輸出的 dehost taxonomy qza：${DEHOST_TAXONOMY_QZA}"
        exit 1
    fi

    echo "[INFO] Step 5. 準備 dehost_dna-sequences.fasta"
    rm -f "${DEHOST_FASTA}"

    if [ "${LINK_DEHOST_FASTA}" = "true" ] && [ -f "${NONHOST_FASTA}" ]; then
        ln -s "../dehost_work/nonhost.fasta" "${DEHOST_FASTA}"
        echo "[INFO] 已建立 symlink：${DEHOST_FASTA} -> ../dehost_work/nonhost.fasta"
    else
        echo "[INFO] 未使用 symlink，改由 dehost_rep_seqs.qza 匯出 fasta"
        TMP_EXPORT_DIR="${DEHOST_OUTPUT_DIR}/repseqs_export_tmp"
        rm -rf "${TMP_EXPORT_DIR}"
        mkdir -p "${TMP_EXPORT_DIR}"

        qiime tools export \
          --input-path "${DEHOST_REPSEQS_QZA}" \
          --output-path "${TMP_EXPORT_DIR}"

        if [ ! -f "${TMP_EXPORT_DIR}/dna-sequences.fasta" ]; then
            echo "[ERROR] 匯出後找不到 dna-sequences.fasta"
            exit 1
        fi

        cp "${TMP_EXPORT_DIR}/dna-sequences.fasta" "${DEHOST_FASTA}"
        rm -rf "${TMP_EXPORT_DIR}"
    fi

    echo
    echo "[INFO] 已完成 dehost pathway 前期準備"
    echo "[INFO] dehost_otu_table.biom      = ${DEHOST_OTU_BIOM}"
    echo "[INFO] dehost_otu_table.qza       = ${DEHOST_OTU_QZA}"
    echo "[INFO] dehost_rep_seqs.qza        = ${DEHOST_REPSEQS_QZA}"
    echo "[INFO] dehost_taxonomy.qza        = ${DEHOST_TAXONOMY_QZA}"
    echo "[INFO] dehost_dna-sequences.fasta = ${DEHOST_FASTA}"
}

main "$@"
