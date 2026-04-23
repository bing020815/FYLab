cat > /home/adprc/classifier/SILVA/train_silva_nb_classifiers.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

DB_KEY="${1:-}"
MODELS="${MODELS:-full-length,V3V4,V3_len200,V4_len250}"

BASE_DIR="/home/adprc/classifier/SILVA"
SOURCE_DIR="${BASE_DIR}/source"

CURRENT_ENV="${CONDA_DEFAULT_ENV:-}"
if [ -z "${CURRENT_ENV}" ]; then
    echo "[ERROR] 目前偵測不到 CONDA_DEFAULT_ENV，請先啟用 QIIME2 環境"
    exit 1
fi

TRAINED_DIR="${BASE_DIR}/trained/${CURRENT_ENV}"
LOG_DIR="${BASE_DIR}/logs"
mkdir -p "${TRAINED_DIR}" "${LOG_DIR}"

if [ -z "${DB_KEY}" ]; then
    echo "[ERROR] 請提供 DB_KEY：138_99 或 dada2_138.2"
    echo "[ERROR] 範例：bash train_silva_nb_classifiers.sh 138_99"
    exit 1
fi

case "${DB_KEY}" in
    138_99)
        PREFIX="silva_138_99"
        ;;
    dada2_138.2)
        PREFIX="silva_dada2_zenodo_138.2"
        ;;
    *)
        echo "[ERROR] 不支援的 DB_KEY：${DB_KEY}"
        echo "[ERROR] 目前支援：138_99 / dada2_138.2"
        exit 1
        ;;
esac

REFSEQ_QZA="${SOURCE_DIR}/${PREFIX}_RefSeq.qza"
TAXONOMY_QZA="${SOURCE_DIR}/${PREFIX}_Taxonomy.qza"

if ! command -v qiime >/dev/null 2>&1; then
    echo "[ERROR] 找不到 qiime 指令，請先啟用 QIIME2 環境"
    exit 1
fi

QINFO="$(qiime info 2>/dev/null || true)"
if ! echo "${QINFO}" | grep -q "QIIME 2 release:"; then
    echo "[ERROR] 目前環境不是有效的 QIIME2 環境"
    echo "${QINFO}"
    exit 1
fi

QRELEASE="$(echo "${QINFO}" | awk -F': ' '/QIIME 2 release/ {print $2; exit}')"
QVERSION="$(echo "${QINFO}" | awk -F': ' '/QIIME 2 version/ {print $2; exit}')"

if [ ! -f "${REFSEQ_QZA}" ]; then
    echo "[ERROR] 找不到 RefSeq：${REFSEQ_QZA}"
    exit 1
fi

if [ ! -f "${TAXONOMY_QZA}" ]; then
    echo "[ERROR] 找不到 Taxonomy：${TAXONOMY_QZA}"
    exit 1
fi

echo "[INFO] CURRENT_ENV   = ${CURRENT_ENV}"
echo "[INFO] QIIME_RELEASE = ${QRELEASE}"
echo "[INFO] QIIME_VERSION = ${QVERSION}"
echo "[INFO] DB_KEY        = ${DB_KEY}"
echo "[INFO] PREFIX        = ${PREFIX}"
echo "[INFO] REFSEQ_QZA    = ${REFSEQ_QZA}"
echo "[INFO] TAXONOMY_QZA  = ${TAXONOMY_QZA}"
echo "[INFO] MODELS        = ${MODELS}"
echo "[INFO] TRAINED_DIR   = ${TRAINED_DIR}"
echo

run_and_log() {
    local step_name="$1"
    shift
    local log_file="${LOG_DIR}/train_${PREFIX}_${CURRENT_ENV}_${step_name}_$(date +%Y%m%d_%H%M%S).log"

    echo "[INFO] 開始：${step_name}"
    echo "[INFO] log = ${log_file}"
    {
        echo "[INFO] step_name=${step_name}"
        echo "[INFO] current_env=${CURRENT_ENV}"
        echo "[INFO] qiime_release=${QRELEASE}"
        echo "[INFO] qiime_version=${QVERSION}"
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

if has_model "full-length"; then
    FULL_OUT="${TRAINED_DIR}/${PREFIX}_NB_classifier_full-length.qza"
    if [ -f "${FULL_OUT}" ]; then
        echo "[INFO] 已存在，跳過 full-length：${FULL_OUT}"
        echo
    else
        run_and_log "full-length" \
            qiime feature-classifier fit-classifier-naive-bayes \
            --i-reference-reads "${REFSEQ_QZA}" \
            --i-reference-taxonomy "${TAXONOMY_QZA}" \
            --o-classifier "${FULL_OUT}"
    fi
fi

if has_model "V3V4"; then
    V3V4_READS="${SOURCE_DIR}/${PREFIX}_RefSeq_341-805.qza"
    V3V4_OUT="${TRAINED_DIR}/${PREFIX}_NB_classifier_V3V4.qza"

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

    if [ -f "${V3V4_OUT}" ]; then
        echo "[INFO] 已存在，跳過 train_V3V4：${V3V4_OUT}"
        echo
    else
        run_and_log "train_V3V4" \
            qiime feature-classifier fit-classifier-naive-bayes \
            --i-reference-reads "${V3V4_READS}" \
            --i-reference-taxonomy "${TAXONOMY_QZA}" \
            --o-classifier "${V3V4_OUT}"
    fi
fi

if has_model "V3_len200"; then
    V3_READS="${SOURCE_DIR}/${PREFIX}_RefSeq_341-534_len200.qza"
    V3_OUT="${TRAINED_DIR}/${PREFIX}_NB_classifier_V3_len200.qza"

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

    if [ -f "${V3_OUT}" ]; then
        echo "[INFO] 已存在，跳過 train_V3_len200：${V3_OUT}"
        echo
    else
        run_and_log "train_V3_len200" \
            qiime feature-classifier fit-classifier-naive-bayes \
            --i-reference-reads "${V3_READS}" \
            --i-reference-taxonomy "${TAXONOMY_QZA}" \
            --o-classifier "${V3_OUT}"
    fi
fi

if has_model "V4_len250"; then
    V4_READS="${SOURCE_DIR}/${PREFIX}_RefSeq_515-806_len250.qza"
    V4_OUT="${TRAINED_DIR}/${PREFIX}_NB_classifier_V4_len250.qza"

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

    if [ -f "${V4_OUT}" ]; then
        echo "[INFO] 已存在，跳過 train_V4_len250：${V4_OUT}"
        echo
    else
        run_and_log "train_V4_len250" \
            qiime feature-classifier fit-classifier-naive-bayes \
            --i-reference-reads "${V4_READS}" \
            --i-reference-taxonomy "${TAXONOMY_QZA}" \
            --o-classifier "${V4_OUT}"
    fi
fi

echo "[INFO] 全部完成"
echo "[INFO] 可檢查輸出："
ls -lh "${TRAINED_DIR}" | grep "${PREFIX}" || true
EOF

chmod +x /home/adprc/classifier/SILVA/train_silva_nb_classifiers.sh
