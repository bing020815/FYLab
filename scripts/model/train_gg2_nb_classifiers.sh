#!/usr/bin/env bash
set -euo pipefail

# 用法範例：
#   bash train_gg2_nb_classifiers.sh 2024.09
#   bash train_gg2_nb_classifiers.sh 2022.10
#   MODELS="full-length,V3V4" bash train_gg2_nb_classifiers.sh 2024.09
#
# 說明：
#   1. 需先 conda activate qiime2-2024.10
#   2. 依序排隊訓練，不並行
#   3. 預設訓練四種模型：full-length,V3V4,V3_len200,V4_len250

DB_VERSION="${1:-}"
MODELS="${MODELS:-full-length,V3V4,V3_len200,V4_len250}"

BASE_DIR="/home/adprc/classifier/gg2"
SOURCE_DIR="${BASE_DIR}/source"
TRAINED_DIR="${BASE_DIR}/trained/qiime2-2024.10"
LOG_DIR="${BASE_DIR}/logs"
mkdir -p "${TRAINED_DIR}" "${LOG_DIR}"

if [ -z "${DB_VERSION}" ]; then
    echo "[ERROR] 請提供 DB_VERSION：2022.10 或 2024.09"
    echo "[ERROR] 範例：bash train_gg2_nb_classifiers.sh 2024.09"
    exit 1
fi

if ! command -v qiime >/dev/null 2>&1; then
    echo "[ERROR] 找不到 qiime 指令，請先啟用 qiime2-2024.10"
    exit 1
fi

QINFO="$(qiime info 2>/dev/null || true)"
if ! echo "${QINFO}" | grep -q "QIIME 2 release: 2024.10"; then
    echo "[ERROR] 目前不是 qiime2-2024.10 環境"
    echo "${QINFO}"
    exit 1
fi

case "${DB_VERSION}" in
    2022.10)
        PREFIX="gg2_2022_10"
        NB_PREFIX="gg2_2022_10_backbone"
        DOT_PREFIX="gg2.2022.10.backbone"
        ;;
    2024.09)
        PREFIX="gg2_2024_09"
        NB_PREFIX="gg2_2024_09_backbone"
        DOT_PREFIX="gg2.2024.09.backbone"
        ;;
    *)
        echo "[ERROR] 不支援的 DB_VERSION：${DB_VERSION}"
        echo "[ERROR] 目前支援：2022.10 / 2024.09"
        exit 1
        ;;
esac

REFSEQ_QZA="${SOURCE_DIR}/${PREFIX}_RefSeq.qza"
TAXONOMY_QZA="${SOURCE_DIR}/${PREFIX}_Taxonomy.qza"

if [ ! -f "${REFSEQ_QZA}" ]; then
    echo "[ERROR] 找不到 RefSeq：${REFSEQ_QZA}"
    exit 1
fi

if [ ! -f "${TAXONOMY_QZA}" ]; then
    echo "[ERROR] 找不到 Taxonomy：${TAXONOMY_QZA}"
    exit 1
fi

echo "[INFO] DB_VERSION   = ${DB_VERSION}"
echo "[INFO] REFSEQ_QZA   = ${REFSEQ_QZA}"
echo "[INFO] TAXONOMY_QZA = ${TAXONOMY_QZA}"
echo "[INFO] MODELS       = ${MODELS}"
echo "[INFO] TRAINED_DIR  = ${TRAINED_DIR}"
echo

run_and_log() {
    local step_name="$1"
    shift
    local log_file="${LOG_DIR}/train_${PREFIX}_${step_name}_$(date +%Y%m%d_%H%M%S).log"

    echo "[INFO] 開始：${step_name}"
    echo "[INFO] log = ${log_file}"
    {
        echo "[INFO] step_name=${step_name}"
        echo "[INFO] start_time=$(date '+%F %T')"
        echo "[INFO] command=$*"
        "$@"
        echo "[INFO] end_time=$(date '+%F %T')"
    } 2>&1 | tee "${log_file}"
    echo "[INFO] 完成：${step_name}"
    echo
}

has_model() {
    local model="$1"
    echo ",${MODELS}," | grep -q ",${model},"
}

# 1. full-length
if has_model "full-length"; then
    FULL_OUT="${TRAINED_DIR}/${DOT_PREFIX}.full-length.nb.qza"
    run_and_log "full-length" \
        qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "${REFSEQ_QZA}" \
        --i-reference-taxonomy "${TAXONOMY_QZA}" \
        --o-classifier "${FULL_OUT}"
fi

# 2. V3V4
if has_model "V3V4"; then
    V3V4_READS="${SOURCE_DIR}/${PREFIX}_RefSeq_341-805.qza"
    V3V4_OUT="${TRAINED_DIR}/${NB_PREFIX}_NB_classifier_V3V4.qza"

    if [ ! -f "${V3V4_READS}" ]; then
        run_and_log "extract_V3V4" \
            qiime feature-classifier extract-reads \
            --i-sequences "${REFSEQ_QZA}" \
            --p-f-primer CCTACGGGNGGCWGCAG \
            --p-r-primer GACTACHVGGGTATCTAATCC \
            --o-reads "${V3V4_READS}"
    else
        echo "[INFO] 已存在，跳過 extract_V3V4：${V3V4_READS}"
        echo
    fi

    run_and_log "train_V3V4" \
        qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "${V3V4_READS}" \
        --i-reference-taxonomy "${TAXONOMY_QZA}" \
        --o-classifier "${V3V4_OUT}"
fi

# 3. V3_len200
if has_model "V3_len200"; then
    V3_READS="${SOURCE_DIR}/${PREFIX}_RefSeq_341-534_len200.qza"
    V3_OUT="${TRAINED_DIR}/${NB_PREFIX}_NB_classifier_V3_len200.qza"

    if [ ! -f "${V3_READS}" ]; then
        run_and_log "extract_V3_len200" \
            qiime feature-classifier extract-reads \
            --i-sequences "${REFSEQ_QZA}" \
            --p-f-primer CCTACGGGNGGCWGCAG \
            --p-r-primer ATTACCGCGGCTGCTGG \
            --p-trunc-len 200 \
            --o-reads "${V3_READS}"
    else
        echo "[INFO] 已存在，跳過 extract_V3_len200：${V3_READS}"
        echo
    fi

    run_and_log "train_V3_len200" \
        qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "${V3_READS}" \
        --i-reference-taxonomy "${TAXONOMY_QZA}" \
        --o-classifier "${V3_OUT}"
fi

# 4. V4_len250
if has_model "V4_len250"; then
    V4_READS="${SOURCE_DIR}/${PREFIX}_RefSeq_515-806_len250.qza"
    V4_OUT="${TRAINED_DIR}/${NB_PREFIX}_NB_classifier_V4_len250.qza"

    if [ ! -f "${V4_READS}" ]; then
        run_and_log "extract_V4_len250" \
            qiime feature-classifier extract-reads \
            --i-sequences "${REFSEQ_QZA}" \
            --p-f-primer GTGCCAGCMGCCGCGGTAA \
            --p-r-primer GGACTACHVGGGTWTCTAAT \
            --p-trunc-len 250 \
            --o-reads "${V4_READS}"
    else
        echo "[INFO] 已存在，跳過 extract_V4_len250：${V4_READS}"
        echo
    fi

    run_and_log "train_V4_len250" \
        qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "${V4_READS}" \
        --i-reference-taxonomy "${TAXONOMY_QZA}" \
        --o-classifier "${V4_OUT}"
fi

echo "[INFO] 全部完成"
echo "[INFO] 可檢查輸出："
ls -lh "${TRAINED_DIR}" | grep "${PREFIX#gg2_}" || true
