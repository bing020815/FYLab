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

OLD_PROMPT_1="(${BEST_ENV_PATH}) "
OLD_PROMPT_2="($(basename "${BEST_ENV_PATH}")) "
export CONDA_PROMPT_MODIFIER="(${QIIME_LABEL}) "

if [ -n "${PS1:-}" ]; then
    if [[ "${PS1}" == "${OLD_PROMPT_1}"* ]]; then
        PS1="${CONDA_PROMPT_MODIFIER}${PS1#${OLD_PROMPT_1}}"
    elif [[ "${PS1}" == "${OLD_PROMPT_2}"* ]]; then
        PS1="${CONDA_PROMPT_MODIFIER}${PS1#${OLD_PROMPT_2}}"
    fi
fi

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
