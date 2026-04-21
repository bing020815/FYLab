#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] 請用 source 執行，不要直接執行："
    echo "        source ./shell_tools/use_qiime_for_artifact.sh <artifact.qza>"
    return 1 2>/dev/null || exit 1
fi

TARGET_ARTIFACT="${1:-}"

if [ -z "${TARGET_ARTIFACT}" ]; then
    echo "[ERROR] 請提供 artifact 路徑"
    echo "[ERROR] 範例：source ./shell_tools/use_qiime_for_artifact.sh rep-seqs.qza"
    return 1
fi

if [ ! -f "${TARGET_ARTIFACT}" ]; then
    echo "[ERROR] 找不到 artifact：${TARGET_ARTIFACT}"
    return 1
fi

if [ -f "/home/adprc/miniconda3/etc/profile.d/conda.sh" ]; then
    # shellcheck disable=SC1091
    source /home/adprc/miniconda3/etc/profile.d/conda.sh
else
    echo "[ERROR] 找不到 conda 初始化腳本：/home/adprc/miniconda3/etc/profile.d/conda.sh"
    return 1
fi

find_candidate_qiime_bins() {
    {
        find /home/adprc/miniconda3/envs -type f -path '*/bin/qiime' 2>/dev/null
        find /home/adprc/nf_conda -type f -path '*/bin/qiime' 2>/dev/null
    } | sort -u
}

extract_qiime_release() {
    local qiime_bin="$1"
    "${qiime_bin}" info 2>/dev/null | awk -F': ' '/^QIIME 2 release:/ {print $2; exit}'
}

extract_qiime_version() {
    local qiime_bin="$1"
    "${qiime_bin}" info 2>/dev/null | awk -F': ' '/^QIIME 2 version:/ {print $2; exit}'
}

can_read_artifact() {
    local qiime_bin="$1"
    local artifact="$2"
    "${qiime_bin}" tools peek "${artifact}" >/dev/null 2>&1
}

determine_label() {
    local env_path="$1"
    local qiime_release="$2"

    local env_name
    env_name="$(basename "${env_path}")"

    if [[ "${env_path}" == /home/adprc/miniconda3/envs/* ]]; then
        printf '%s\n' "${env_name}"
    else
        printf 'qiime2-%s-alias\n' "${qiime_release}"
    fi
}

BEST_QIIME_BIN=""
BEST_ENV_PATH=""
BEST_RELEASE=""
BEST_VERSION=""
BEST_LABEL=""

while IFS= read -r qiime_bin; do
    [ -z "${qiime_bin}" ] && continue

    if can_read_artifact "${qiime_bin}" "${TARGET_ARTIFACT}"; then
        BEST_QIIME_BIN="${qiime_bin}"
        BEST_ENV_PATH="$(cd "$(dirname "${qiime_bin}")/.." && pwd)"
        BEST_RELEASE="$(extract_qiime_release "${qiime_bin}")"
        BEST_VERSION="$(extract_qiime_version "${qiime_bin}")"
        BEST_LABEL="$(determine_label "${BEST_ENV_PATH}" "${BEST_RELEASE}")"
        break
    fi
done < <(find_candidate_qiime_bins)

if [ -z "${BEST_QIIME_BIN}" ]; then
    echo "[ERROR] 找不到任何可讀取 artifact 的 qiime 環境"
    echo "[ERROR] TARGET_ARTIFACT=${TARGET_ARTIFACT}"
    return 1
fi

conda activate "${BEST_ENV_PATH}" >/dev/null 2>&1 || {
    echo "[ERROR] conda activate 失敗：${BEST_ENV_PATH}"
    return 1
}

export QIIME_BIN="${BEST_QIIME_BIN}"
export QIIME_ENV_PATH="${BEST_ENV_PATH}"
export QIIME_ENV_NAME="$(basename "${BEST_ENV_PATH}")"
export QIIME_RELEASE="${BEST_RELEASE}"
export QIIME_VERSION="${BEST_VERSION}"
export QIIME_LABEL="${BEST_LABEL}"
export QIIME_TARGET_ARTIFACT="$(realpath "${TARGET_ARTIFACT}")"

if [ -z "${ORIGINAL_CONDA_PROMPT_MODIFIER:-}" ] && [ -n "${CONDA_PROMPT_MODIFIER:-}" ]; then
    export ORIGINAL_CONDA_PROMPT_MODIFIER="${CONDA_PROMPT_MODIFIER}"
fi

export CONDA_PROMPT_MODIFIER="(${QIIME_LABEL}) "

echo "[INFO] 已啟用 QIIME artifact 相容環境"
echo "[INFO] TARGET_ARTIFACT  : ${QIIME_TARGET_ARTIFACT}"
echo "[INFO] QIIME_LABEL      : ${QIIME_LABEL}"
echo "[INFO] QIIME_RELEASE    : ${QIIME_RELEASE}"
echo "[INFO] QIIME_VERSION    : ${QIIME_VERSION}"
echo "[INFO] QIIME_ENV_PATH   : ${QIIME_ENV_PATH}"
echo "[INFO] QIIME_ENV_NAME   : ${QIIME_ENV_NAME}"
echo "[INFO] QIIME_BIN        : ${QIIME_BIN}"
echo "[INFO] 目前可直接使用："
echo "       qiime info"
echo "       qiime tools peek ${TARGET_ARTIFACT}"
