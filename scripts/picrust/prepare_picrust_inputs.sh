#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

MODE="${MODE:-raw}"          # raw / dehost
THREADS="${THREADS:-2}"
QIIME_ENV_NAME="${QIIME_ENV_NAME:-qiime2-2023.2}"

PICRUST_DIR="${PROJECT_DIR}/picrust"
mkdir -p "${PICRUST_DIR}"

RUN_IN_TMUX_SH="${PROJECT_DIR}/shell_tools/run_in_tmux.sh"

if ! command -v qiime >/dev/null 2>&1; then
    echo "[ERROR] 找不到 qiime 指令"
    echo "[ERROR] 請先啟用 QIIME2 環境，例如：conda activate ${QIIME_ENV_NAME}"
    exit 1
fi

if [ ! -x "${RUN_IN_TMUX_SH}" ]; then
    echo "[ERROR] 找不到可執行的 ${RUN_IN_TMUX_SH}"
    echo "[ERROR] 請先確認 shell_tools/run_in_tmux.sh 已下載並 chmod +x"
    exit 1
fi

case "${MODE}" in
    raw)
        INPUT_REPSEQ="${PROJECT_DIR}/rep-seqs.qza"
        EXPECT_FASTA="${PROJECT_DIR}/phyloseq/dna-sequences.fasta"

        ALIGN_QZA="${PICRUST_DIR}/aligned-rep-seqs.qza"
        MASKED_ALIGN_QZA="${PICRUST_DIR}/masked-aligned-rep-seqs.qza"
        UNROOTED_TREE_QZA="${PICRUST_DIR}/unrooted-tree.qza"
        ROOTED_TREE_QZA="${PICRUST_DIR}/rooted-tree.qza"

        JOB_NAME="picrust_tree_raw"
        ;;
    dehost)
        INPUT_REPSEQ="${PROJECT_DIR}/phyloseq/filtered_host/dehost_rep_seqs.qza"
        EXPECT_FASTA="${PROJECT_DIR}/phyloseq/filtered_host/dehost_dna-sequences.fasta"

        ALIGN_QZA="${PICRUST_DIR}/dehost_aligned-rep-seqs.qza"
        MASKED_ALIGN_QZA="${PICRUST_DIR}/dehost_masked-aligned-rep-seqs.qza"
        UNROOTED_TREE_QZA="${PICRUST_DIR}/dehost_unrooted-tree.qza"
        ROOTED_TREE_QZA="${PICRUST_DIR}/dehost_rooted-tree.qza"

        JOB_NAME="picrust_tree_dehost"
        ;;
    *)
        echo "[ERROR] MODE 只能是 raw 或 dehost"
        exit 1
        ;;
esac

if [ ! -f "${INPUT_REPSEQ}" ]; then
    echo "[ERROR] 找不到輸入檔案：${INPUT_REPSEQ}"
    exit 1
fi

if [ ! -f "${EXPECT_FASTA}" ]; then
    echo "[ERROR] 找不到對應的 fasta：${EXPECT_FASTA}"
    if [ "${MODE}" = "raw" ]; then
        echo "[ERROR] 請先執行 ./shell_tools/export_table_qza_to_phyloseq.sh ."
    else
        echo "[ERROR] 請先執行 ./shell_tools/prepare_dehost_qiime2_inputs.sh ."
    fi
    exit 1
fi

echo "[INFO] PROJECT_DIR   = ${PROJECT_DIR}"
echo "[INFO] MODE          = ${MODE}"
echo "[INFO] THREADS       = ${THREADS}"
echo "[INFO] INPUT_REPSEQ  = ${INPUT_REPSEQ}"
echo "[INFO] EXPECT_FASTA  = ${EXPECT_FASTA}"
echo "[INFO] PICRUST_DIR   = ${PICRUST_DIR}"

echo "[INFO] Step 1. 確認前處理 fasta 已存在"
echo "[INFO] FASTA = ${EXPECT_FASTA}"

echo "[INFO] Step 2. 送出 phylogeny tree 任務至 tmux"

CMD_STR="qiime phylogeny align-to-tree-mafft-fasttree \
  --i-sequences \"${INPUT_REPSEQ}\" \
  --o-alignment \"${ALIGN_QZA}\" \
  --o-masked-alignment \"${MASKED_ALIGN_QZA}\" \
  --o-tree \"${UNROOTED_TREE_QZA}\" \
  --o-rooted-tree \"${ROOTED_TREE_QZA}\" \
  --p-n-threads \"${THREADS}\""

SESSION_NAME=$(
    JOB_TYPE=picrust_tree \
    PROJECT_DIR="${PROJECT_DIR}" \
    JOB_NAME="${JOB_NAME}" \
    CMD="${CMD_STR}" \
    SHOW_INFO=false \
    "${RUN_IN_TMUX_SH}"
)

echo
echo "[INFO] 已完成 PICRUSt2 tree 任務送出"
echo "[INFO] SESSION_NAME          = ${SESSION_NAME}"
echo "[INFO] tree job name         = ${JOB_NAME}"
echo "[INFO] alignment qza         = ${ALIGN_QZA}"
echo "[INFO] masked alignment qza  = ${MASKED_ALIGN_QZA}"
echo "[INFO] unrooted tree qza     = ${UNROOTED_TREE_QZA}"
echo "[INFO] rooted tree qza       = ${ROOTED_TREE_QZA}"
echo "[INFO] 參考 fasta            = ${EXPECT_FASTA}"
echo "[INFO] 可用以下指令查詢任務："
echo "MODE=latest JOB_TYPE=picrust_tree ./shell_tools/check_tmux_jobs.sh"
echo "MODE=session SESSION_NAME=${SESSION_NAME} ./shell_tools/check_tmux_jobs.sh"
