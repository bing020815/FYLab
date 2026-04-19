#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
PACBIO_RESULTS_DIR="${PROJECT_DIR}/pacbio_results"
MODE="${MODE:-official}"   # official / fylab

copy_if_exists () {
    local src="$1"
    local dst="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "[INFO] 已複製: $src -> $dst"
    else
        echo "[WARN] 找不到: $src"
    fi
}

write_taxonomy_source () {
    local mode="$1"
    local outfile="${PROJECT_DIR}/taxonomy_source.txt"

    if [ "$mode" = "official" ]; then
        cat > "$outfile" <<EOF
taxonomy_mode=official
taxonomy_source_type=nextflow_reference
taxonomy_source_file=taxonomy_nextflow_reference.tsv
taxonomy_source_merged_file=taxonomy_nextflow_merged_reference.tsv
note=Use Nextflow official taxonomy as final taxonomy.
EOF
    elif [ "$mode" = "fylab" ]; then
        cat > "$outfile" <<EOF
taxonomy_mode=fylab
taxonomy_source_type=fylab_classifier
taxonomy_source_file=taxonomy.qza
taxonomy_source_merged_file=taxonomy_nextflow_merged_reference.tsv
note=Use FYLab custom-classified taxonomy.tsv as final taxonomy. Nextflow taxonomy is reference only.
EOF
    else
        echo "[ERROR] 不支援的 MODE: $mode"
        exit 1
    fi

    echo "[INFO] 已建立: $outfile"
}

if [ ! -d "${PACBIO_RESULTS_DIR}" ]; then
    echo "[ERROR] 找不到 pacbio_results：${PACBIO_RESULTS_DIR}"
    exit 1
fi

echo "[INFO] 開始從 pacbio_results 整理 FYLab 共用核心檔案"
echo "[INFO] MODE = ${MODE}"

# DADA2 核心產物
copy_if_exists "${PACBIO_RESULTS_DIR}/dada2/dada2-ccs_table_filtered.qza" "${PROJECT_DIR}/table.qza"
copy_if_exists "${PACBIO_RESULTS_DIR}/dada2/dada2-ccs_rep_filtered.qza" "${PROJECT_DIR}/rep-seqs.qza"

# 官方 taxonomy 參考檔，一律保留
copy_if_exists "${PACBIO_RESULTS_DIR}/results/best_taxonomy_withDB.tsv" "${PROJECT_DIR}/taxonomy_nextflow_reference.tsv"
copy_if_exists "${PACBIO_RESULTS_DIR}/results/best_tax_merged_freq_tax.tsv" "${PROJECT_DIR}/taxonomy_nextflow_merged_reference.tsv"

write_taxonomy_source "${MODE}"

echo "[INFO] 整理完成"
echo "[INFO] 已準備: table.qza, rep-seqs.qza, taxonomy_nextflow_reference.tsv, taxonomy_nextflow_merged_reference.tsv, taxonomy_source.txt"
