#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
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
taxonomy_source=PacBio HiFi-16S-workflow bundled DB
taxonomy_table=taxonomy.tsv
note=This taxonomy result was generated from the Nextflow official workflow database, not FYLab custom classifier.
EOF
    elif [ "$mode" = "fylab" ]; then
        cat > "$outfile" <<EOF
taxonomy_mode=fylab
taxonomy_source=FYLab custom classifier expected
taxonomy_table=not_assigned_by_collect_script
note=Official workflow taxonomy files are kept in pacbio_results and copied as reference only.
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

echo "[INFO] 開始從 pacbio_results 整理 FYLab 共用檔案"
echo "[INFO] MODE = ${MODE}"

# 核心中間產物，兩種模式都整理
copy_if_exists "${PACBIO_RESULTS_DIR}/dada2/dada2-ccs_table_filtered.qza" "${PROJECT_DIR}/table.qza"
copy_if_exists "${PACBIO_RESULTS_DIR}/dada2/dada2-ccs_rep_filtered.qza" "${PROJECT_DIR}/rep-seqs.qza"
copy_if_exists "${PACBIO_RESULTS_DIR}/results/feature-table-tax.biom" "${PROJECT_DIR}/feature-table-tax.biom"

# 先保留官方 taxonomy 參考檔
copy_if_exists "${PACBIO_RESULTS_DIR}/results/best_taxonomy_withDB.tsv" "${PROJECT_DIR}/taxonomy_nextflow_reference.tsv"
copy_if_exists "${PACBIO_RESULTS_DIR}/results/best_tax_merged_freq_tax.tsv" "${PROJECT_DIR}/taxonomy_nextflow_merged_reference.tsv"

if [ "${MODE}" = "official" ]; then
    copy_if_exists "${PACBIO_RESULTS_DIR}/results/best_taxonomy_withDB.tsv" "${PROJECT_DIR}/taxonomy.tsv"
    write_taxonomy_source "official"

elif [ "${MODE}" = "fylab" ]; then
    # 不覆蓋 taxonomy.tsv，讓後續由 FYLab 自訂分類器產生
    write_taxonomy_source "fylab"

else
    echo "[ERROR] MODE 只能是 official 或 fylab"
    exit 1
fi

echo "[INFO] 整理完成"
echo "[INFO] 專案根目錄已更新 FYLab 共用檔案"
