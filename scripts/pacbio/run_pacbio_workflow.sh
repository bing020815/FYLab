#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
ENV_NAME="pacbio16s"
WORKFLOW_DIR="${HOME}/tools/HiFi-16S-workflow"

SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"
OUTDIR="${PROJECT_DIR}/pacbio_results"
LOGS_DIR="${PROJECT_DIR}/logs"
WORK_DIR="${PROJECT_DIR}/work"

CPU="${CPU:-8}"
RESUME="${RESUME:-false}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
RUN_IN_TMUX="${RUN_IN_TMUX:-true}"

DEFAULT_SESSION_NAME="pacbio_$(date +%Y%m%d_%H%M%S)"
TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-${DEFAULT_SESSION_NAME}}"

STDOUT_LOG="${LOGS_DIR}/nextflow.stdout.log"
STDERR_LOG="${LOGS_DIR}/nextflow.stderr.log"
STATUS_FILE="${LOGS_DIR}/run_pacbio.status"
INNER_SCRIPT="${LOGS_DIR}/run_pacbio_inner.sh"

mkdir -p "${OUTDIR}" "${LOGS_DIR}" "${WORK_DIR}"

if [ ! -f "${SAMPLES_TSV}" ]; then
    echo "[ERROR] 找不到 ${SAMPLES_TSV}"
    exit 1
fi

if [ ! -f "${METADATA_TSV}" ]; then
    echo "[ERROR] 找不到 ${METADATA_TSV}"
    exit 1
fi

if [ ! -d "${WORKFLOW_DIR}" ]; then
    echo "[ERROR] 找不到 workflow：${WORKFLOW_DIR}"
    echo "[ERROR] 請先完成共用層安裝"
    exit 1
fi

if ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] 找不到 conda"
    exit 1
fi

write_inner_script() {
    cat > "${INNER_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

START_TIME="\$(date '+%Y-%m-%d %H:%M:%S')"
START_EPOCH="\$(date +%s)"

cat > "${STATUS_FILE}" <<EOSTATUS
status=running
start_time=\${START_TIME}
end_time=
duration_seconds=
exit_code=
session_name=${TMUX_SESSION_NAME}
project_dir=${PROJECT_DIR}
stdout_log=${STDOUT_LOG}
stderr_log=${STDERR_LOG}
EOSTATUS

source "\$(conda info --base)/etc/profile.d/conda.sh"
conda activate "${ENV_NAME}"

set +e
nextflow run "${WORKFLOW_DIR}/main.nf" \
  --input "${SAMPLES_TSV}" \
  --metadata "${METADATA_TSV}" \
  --dada2_cpu "${CPU}" \
  --vsearch_cpu "${CPU}" \
  --outdir "${OUTDIR}" \
  --publish_dir_mode copy \
  -work-dir "${WORK_DIR}" \
  $( [ "${RESUME}" = "true" ] && printf '%s' "-resume" ) \
  ${EXTRA_ARGS} \
  > "${STDOUT_LOG}" 2> "${STDERR_LOG}"
EXIT_CODE=\$?
set -e

END_TIME="\$(date '+%Y-%m-%d %H:%M:%S')"
END_EPOCH="\$(date +%s)"
DURATION_SECONDS=\$((END_EPOCH - START_EPOCH))

if [ "\${EXIT_CODE}" -eq 0 ]; then
    FINAL_STATUS="completed"
else
    FINAL_STATUS="failed"
fi

cat > "${STATUS_FILE}" <<EOSTATUS
status=\${FINAL_STATUS}
start_time=\${START_TIME}
end_time=\${END_TIME}
duration_seconds=\${DURATION_SECONDS}
exit_code=\${EXIT_CODE}
session_name=${TMUX_SESSION_NAME}
project_dir=${PROJECT_DIR}
stdout_log=${STDOUT_LOG}
stderr_log=${STDERR_LOG}
EOSTATUS

exit "\${EXIT_CODE}"
EOF

    chmod +x "${INNER_SCRIPT}"
}

echo "[INFO] PROJECT_DIR = ${PROJECT_DIR}"
echo "[INFO] OUTDIR      = ${OUTDIR}"
echo "[INFO] CPU         = ${CPU}"
echo "[INFO] RESUME      = ${RESUME}"
echo "[INFO] RUN_IN_TMUX = ${RUN_IN_TMUX}"
echo "[INFO] EXTRA_ARGS  = ${EXTRA_ARGS}"
echo "[INFO] STATUS_FILE = ${STATUS_FILE}"

write_inner_script

if [ "${RUN_IN_TMUX}" = "true" ]; then
    if ! command -v tmux >/dev/null 2>&1; then
        echo "[ERROR] 找不到 tmux，但 RUN_IN_TMUX=true"
        echo "[ERROR] 可改用 RUN_IN_TMUX=false 前景執行"
        exit 1
    fi

    if tmux has-session -t "${TMUX_SESSION_NAME}" 2>/dev/null; then
        echo "[ERROR] tmux session 已存在：${TMUX_SESSION_NAME}"
        echo "[ERROR] 請改用其他名稱，例如："
        echo "TMUX_SESSION_NAME=${TMUX_SESSION_NAME}_v2 ./run_pacbio_workflow.sh ${PROJECT_DIR}"
        exit 1
    fi

    tmux new-session -d -s "${TMUX_SESSION_NAME}" "bash '${INNER_SCRIPT}'"

    echo "[INFO] 已建立 tmux session: ${TMUX_SESSION_NAME}"
    echo "[INFO] 此 session 主要用途為避免遠端斷線導致任務中止"
    echo "[INFO] 請以以下檔案監看進度："
    echo "[INFO]   tail -f ${STDOUT_LOG}"
    echo "[INFO]   tail -f ${STDERR_LOG}"
    echo "[INFO]   cat ${STATUS_FILE}"
    echo "[INFO] 若需檢查 session 是否仍存在：tmux ls"
    echo "[INFO] 若需手動接回 session：tmux attach -t ${TMUX_SESSION_NAME}"
    echo "[INFO] 注意：attach 後畫面可能為空白，屬正常現象，請以 log 檔為主"
    echo "[INFO] 若需關閉 session：tmux kill-session -t ${TMUX_SESSION_NAME}"

else
    echo "[INFO] 前景執行 workflow"
    bash "${INNER_SCRIPT}"

    echo "[INFO] 執行完成"
    echo "[INFO] stdout log: ${STDOUT_LOG}"
    echo "[INFO] stderr log: ${STDERR_LOG}"
    echo "[INFO] status file: ${STATUS_FILE}"
fi
