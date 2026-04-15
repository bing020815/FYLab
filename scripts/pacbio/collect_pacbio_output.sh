#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PACBIO_RESULTS_DIR="${PROJECT_DIR}/pacbio_results"

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

echo "[INFO] 開始整理 PacBio workflow 輸出"

copy_if_exists "${PACBIO_RESULTS_DIR}/dada2-ccs_table_filtered.qza" "${PROJECT_DIR}/table.qza"
copy_if_exists "${PACBIO_RESULTS_DIR}/dada2-ccs_rep_filtered.qza" "${PROJECT_DIR}/rep-seqs.qza"
copy_if_exists "${PACBIO_RESULTS_DIR}/dada2-ccs_stats.qza" "${PROJECT_DIR}/denoise-stats.qza"
copy_if_exists "${PACBIO_RESULTS_DIR}/best_taxonomy_withDB.tsv" "${PROJECT_DIR}/taxonomy.tsv"
copy_if_exists "${PACBIO_RESULTS_DIR}/feature-table-tax.biom" "${PROJECT_DIR}/feature-table-tax.biom"

echo "[INFO] 整理完成"
echo "[INFO] 已將 FYLab 共用檔案整理到專案根目錄"