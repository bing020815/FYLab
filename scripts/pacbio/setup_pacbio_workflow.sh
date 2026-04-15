#!/usr/bin/env bash
set -euo pipefail

TOOLS_DIR="${HOME}/tools"
WORKFLOW_DIR="${TOOLS_DIR}/HiFi-16S-workflow"

mkdir -p "${TOOLS_DIR}"

if [ -d "${WORKFLOW_DIR}/.git" ]; then
    echo "[INFO] 官方 workflow 已存在：${WORKFLOW_DIR}"
    echo "[INFO] 如需更新，請手動執行："
    echo "cd ${WORKFLOW_DIR} && git pull"
else
    echo "[INFO] 下載 PacBio 官方 workflow 到 ${WORKFLOW_DIR}"
    git clone https://github.com/PacificBiosciences/HiFi-16S-workflow.git "${WORKFLOW_DIR}"
fi

echo "[INFO] 完成。workflow 位置：${WORKFLOW_DIR}"