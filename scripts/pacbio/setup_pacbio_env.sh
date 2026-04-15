#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="pacbio16s"

if ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] 找不到 conda，請先安裝或先載入 conda。"
    exit 1
fi

if conda env list | awk '{print $1}' | grep -qx "${ENV_NAME}"; then
    echo "[INFO] conda 環境 ${ENV_NAME} 已存在，略過建立。"
else
    echo "[INFO] 建立 conda 環境: ${ENV_NAME}"
    conda create -n "${ENV_NAME}" -c conda-forge -c bioconda nextflow openjdk=17 git wget curl -y
fi

echo "[INFO] 完成。請使用以下指令啟動環境："
echo "conda activate ${ENV_NAME}"