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

extract_artifact_framework_version() {
    local artifact="$1"

    python3 - "$artifact" <<'PY'
import sys
import zipfile

artifact = sys.argv[1]

with zipfile.ZipFile(artifact) as zf:
    version_files = [n for n in zf.namelist() if n.endswith('/VERSION')]
    if not version_files:
        sys.exit(1)

    content = zf.read(version_files[0]).decode('utf-8', errors='ignore')
    for line in content.splitlines():
        if line.startswith('framework:'):
            print(line.split(':', 1)[1].strip())
            break
PY
}

extract_release_from_framework_version() {
    local framework_version="$1"
    # 例如 2024.10.1 -> 2024.10
    #      2023.2.0   -> 2023.2
    printf '%s\n' "${framework_version}" | awk -F. '{print $1 "." $2}'
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

ARTIFACT_FRAMEWORK_VERSION="$(extract_artifact_framework_version "${TARGET_ARTIFACT}" || true)"
if [ -z "${ARTIFACT_FRAMEWORK_VERSION}" ]; then
    echo "[ERROR] 無法從 artifact 解析 framework 版本：${TARGET_ARTIFACT}"
    return 1
fi

REQUIRED_RELEASE="$(extract_release_from_framework_version "${ARTIFACT_FRAMEWORK_VERSION}")"
if [ -z "${REQUIRED_RELEASE}" ]; then
    echo "[ERROR] 無法解析 artifact 對應的 QIIME release：${ARTIFACT_FRAMEWORK_VERSION}"
    return 1
fi

BEST_QIIME_BIN=""
BEST_ENV_PATH=""
BEST_RELEASE=""
BEST_VERSION=""
BEST_LABEL=""

# 第一輪：優先找正式 conda env，且 release 必須完全相同
while IFS= read -r qiime_bin; do
    [ -z "${qiime_bin}" ] && continue

    env_path="$(cd "$(dirname "${qiime_bin}")/.." && pwd)"
    release="$(extract_qiime_release "${qiime_bin}")"
    version="$(extract_qiime_version "${qiime_bin}")"

    if [ -z "${release}" ]; then
        continue
    fi

    if [ "${release}" != "${REQUIRED_RELEASE}" ]; then
        continue
    fi

    if [[ "${env_path}" == /home/adprc/miniconda3/envs/* ]]; then
        BEST_QIIME_BIN="${qiime_bin}"
        BEST_ENV_PATH="${env_path}"
        BEST_RELEASE="${release}"
        BEST_VERSION="${version}"
        BEST_LABEL="$(determine_label "${BEST_ENV_PATH}" "${BEST_RELEASE}")"
        break
    fi
done < <(find_candidate_qiime_bins)

# 第二輪：若沒有正式 conda env，再找 nextflow cached env，release 也必須完全相同
if [ -z "${BEST_QIIME_BIN}" ]; then
    while IFS= read -r qiime_bin; do
        [ -z "${qiime_bin}" ] && continue

        env_path="$(cd "$(dirname "${qiime_bin}")/.." && pwd)"
        release="$(extract_qiime_release "${qiime_bin}")"
        version="$(extract_qiime_version "${qiime_bin}")"

        if [ -z "${release}" ]; then
            continue
        fi

        if [ "${release}" != "${REQUIRED_RELEASE}" ]; then
            continue
        fi

        if [[ "${env_path}" == /home/adprc/nf_conda/* ]]; then
            BEST_QIIME_BIN="${qiime_bin}"
            BEST_ENV_PATH="${env_path}"
            BEST_RELEASE="${release}"
            BEST_VERSION="${version}"
            BEST_LABEL="$(determine_label "${BEST_ENV_PATH}" "${BEST_RELEASE}")"
            break
        fi
    done < <(find_candidate_qiime_bins)
fi

if [ -z "${BEST_QIIME_BIN}" ]; then
    echo "[ERROR] artifact 建立版本：${ARTIFACT_FRAMEWORK_VERSION}"
    echo "[ERROR] 要求的 QIIME release：${REQUIRED_RELEASE}"
    echo "[ERROR] 找不到相同 release 的 QIIME 環境"
    echo "[ERROR] 不允許跨版本混用，請建立或保留對應版本環境"
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
export QIIME_ARTIFACT_FRAMEWORK_VERSION="${ARTIFACT_FRAMEWORK_VERSION}"
export QIIME_REQUIRED_RELEASE="${REQUIRED_RELEASE}"

export CONDA_PROMPT_MODIFIER="(${QIIME_LABEL}) "

echo "[INFO] 已啟用 QIIME artifact 相容環境"
echo "[INFO] TARGET_ARTIFACT           : ${QIIME_TARGET_ARTIFACT}"
echo "[INFO] ARTIFACT_FRAMEWORK        : ${QIIME_ARTIFACT_FRAMEWORK_VERSION}"
echo "[INFO] REQUIRED_QIIME_RELEASE    : ${QIIME_REQUIRED_RELEASE}"
echo "[INFO] QIIME_LABEL               : ${QIIME_LABEL}"
echo "[INFO] QIIME_RELEASE             : ${QIIME_RELEASE}"
echo "[INFO] QIIME_VERSION             : ${QIIME_VERSION}"
echo "[INFO] QIIME_ENV_PATH            : ${QIIME_ENV_PATH}"
echo "[INFO] QIIME_ENV_NAME            : ${QIIME_ENV_NAME}"
echo "[INFO] QIIME_BIN                 : ${QIIME_BIN}"
echo "[INFO] 目前可直接使用："
echo "       qiime info"
echo "       qiime tools peek ${TARGET_ARTIFACT}"
