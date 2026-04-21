#!/usr/bin/env bash
set -euo pipefail

SOURCE_ENV_PATH="${1:-}"
TARGET_ENV_NAME="${2:-}"

if [ -z "${SOURCE_ENV_PATH}" ] || [ -z "${TARGET_ENV_NAME}" ]; then
    echo "[ERROR] 用法："
    echo "        ./shell_tools/bootstrap_qiime_named_env.sh <source_env_path> <target_env_name>"
    echo "[ERROR] 範例："
    echo "        ./shell_tools/bootstrap_qiime_named_env.sh /home/adprc/nf_conda/env-d28c726ab5a9eeae20233dd184e3564f qiime2-2024.10"
    exit 1
fi

if [ ! -d "${SOURCE_ENV_PATH}" ]; then
    echo "[ERROR] 找不到來源環境：${SOURCE_ENV_PATH}"
    exit 1
fi

if [ ! -f "${SOURCE_ENV_PATH}/bin/qiime" ]; then
    echo "[ERROR] 來源環境內找不到 qiime：${SOURCE_ENV_PATH}/bin/qiime"
    exit 1
fi

if [ -f "/home/adprc/miniconda3/etc/profile.d/conda.sh" ]; then
    # shellcheck disable=SC1091
    source /home/adprc/miniconda3/etc/profile.d/conda.sh
else
    echo "[ERROR] 找不到 conda 初始化腳本：/home/adprc/miniconda3/etc/profile.d/conda.sh"
    exit 1
fi

TARGET_ENV_PATH="/home/adprc/miniconda3/envs/${TARGET_ENV_NAME}"

if [ -d "${TARGET_ENV_PATH}" ]; then
    echo "[ERROR] 目標環境已存在：${TARGET_ENV_PATH}"
    exit 1
fi

echo "[INFO] SOURCE_ENV_PATH = ${SOURCE_ENV_PATH}"
echo "[INFO] TARGET_ENV_NAME = ${TARGET_ENV_NAME}"
echo "[INFO] TARGET_ENV_PATH = ${TARGET_ENV_PATH}"

echo "[INFO] 來源 QIIME 版本："
"${SOURCE_ENV_PATH}/bin/qiime" info | grep -E '^QIIME 2 release:|^QIIME 2 version:' || true

echo "[INFO] 開始 clone conda 環境..."
conda create -y --name "${TARGET_ENV_NAME}" --clone "${SOURCE_ENV_PATH}"

echo "[INFO] 已建立正式命名環境：${TARGET_ENV_NAME}"
echo "[INFO] 建議驗證："
echo "       conda activate ${TARGET_ENV_NAME}"
echo "       qiime info"
