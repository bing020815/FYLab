#!/usr/bin/env bash
set -euo pipefail


# ============================================================
# Generic tmux job runner
#
# Features:
#   - Run commands in tmux or foreground
#   - Per-job stdout / stderr logs
#   - Per-job status file
#   - Optional stage tracking
#   - Job-specific final stage snapshot
#   - Atomic status updates
#   - latest_<JOB_TYPE> symlinks
#
# Usage example:
#
#   JOB_TYPE=picrust_functional \
#   PROJECT_DIR=. \
#   JOB_NAME=dehost_picrust2sc_functional \
#   STAGE_FILE=/path/to/live_stage.txt \
#   CMD='echo hello' \
#   ./shell_tools/run_in_tmux.sh
#
# Optional:
#
#   PRE_CMD='...'
#   CMD_FILE=/path/to/script.sh
#   RUN_IN_TMUX=true|false
#   TIMEZONE=Asia/Taipei
#   LOG_DIR=/path/to/logs
#   SHOW_INFO=true|false
#   TMUX_TERM=xterm-256color
# ============================================================


# ============================================================
# Configuration
# ============================================================

JOB_TYPE="${JOB_TYPE:-job}"

PROJECT_DIR="${PROJECT_DIR:-.}"

JOB_NAME="${JOB_NAME:-${JOB_TYPE}}"

PRE_CMD="${PRE_CMD:-}"

CMD="${CMD:-}"

CMD_FILE="${CMD_FILE:-}"

RUN_IN_TMUX="${RUN_IN_TMUX:-true}"

TIMEZONE="${TIMEZONE:-Asia/Taipei}"

SHOW_INFO="${SHOW_INFO:-true}"

TMUX_TERM="${TMUX_TERM:-xterm-256color}"

STAGE_FILE="${STAGE_FILE:-}"


# ============================================================
# Normalize project directory
# ============================================================

PROJECT_DIR="$(
    cd "${PROJECT_DIR}" &&
    pwd
)"


# ============================================================
# Log directory
# ============================================================

LOG_DIR="${LOG_DIR:-${PROJECT_DIR}/logs}"

mkdir -p "${LOG_DIR}"

LOG_DIR="$(
    cd "${LOG_DIR}" &&
    pwd
)"


export TZ="${TIMEZONE}"


# ============================================================
# Validate booleans
# ============================================================

case "${RUN_IN_TMUX}" in
    true|false)
        ;;
    *)
        echo "[ERROR] RUN_IN_TMUX must be true or false"
        exit 1
        ;;
esac


case "${SHOW_INFO}" in
    true|false)
        ;;
    *)
        echo "[ERROR] SHOW_INFO must be true or false"
        exit 1
        ;;
esac


# ============================================================
# Validate command source
# ============================================================

if [[ -n "${CMD_FILE}" && -n "${CMD}" ]]; then
    echo "[ERROR] CMD_FILE and CMD cannot both be supplied"
    exit 1
fi


if [[ -z "${CMD_FILE}" && -z "${CMD}" ]]; then
    echo "[ERROR] Either CMD or CMD_FILE is required"
    exit 1
fi


if [[ -n "${CMD_FILE}" ]]; then

    if [[ ! -f "${CMD_FILE}" ]]; then
        echo "[ERROR] CMD_FILE not found:"
        echo "  ${CMD_FILE}"
        exit 1
    fi

    CMD_FILE="$(
        cd "$(dirname "${CMD_FILE}")" &&
        pwd
    )/$(basename "${CMD_FILE}")"

fi


# ============================================================
# Job identifiers
# ============================================================

JOB_ID="${JOB_TYPE}_$(date +%Y%m%d_%H%M%S)"

SESSION_NAME="${JOB_ID}"


# ============================================================
# Job files
# ============================================================

STDOUT_LOG="${LOG_DIR}/${JOB_ID}.stdout.log"

STDERR_LOG="${LOG_DIR}/${JOB_ID}.stderr.log"

STATUS_FILE="${LOG_DIR}/${JOB_ID}.status"

RUNNER_SCRIPT="${LOG_DIR}/${JOB_ID}.runner.sh"

JOB_STAGE_FILE="${LOG_DIR}/${JOB_ID}.stage"


# ============================================================
# Latest links
# ============================================================

LATEST_STDOUT_LINK="${LOG_DIR}/latest_${JOB_TYPE}.stdout.log"

LATEST_STDERR_LINK="${LOG_DIR}/latest_${JOB_TYPE}.stderr.log"

LATEST_STATUS_LINK="${LOG_DIR}/latest_${JOB_TYPE}.status"


# ============================================================
# Timing
# ============================================================

START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

START_EPOCH="$(date +%s)"


# ============================================================
# Command source
# ============================================================

if [[ -n "${CMD_FILE}" ]]; then

    CMD_SOURCE="cmd_file"

    CMD_FULL="bash \"${CMD_FILE}\""

    CMD_PREVIEW="${CMD_FILE}"

else

    CMD_SOURCE="inline_cmd"

    CMD_FULL="${CMD}"

    CMD_PREVIEW="$(
        printf '%s' "${CMD}" |
        tr '\n' ' ' |
        sed 's/[[:space:]]\+/ /g' |
        cut -c1-300
    )"

fi


PRE_CMD_PREVIEW="$(
    printf '%s' "${PRE_CMD}" |
    tr '\n' ' ' |
    sed 's/[[:space:]]\+/ /g' |
    cut -c1-300
)"


# ============================================================
# Write running status
#
# Important:
#   - Do not store CMD_FULL here.
#   - Full command is already preserved in RUNNER_SCRIPT.
#   - Use temporary file + mv for atomic update.
# ============================================================

write_status_running() {

    local tmp_status

    tmp_status="${STATUS_FILE}.tmp.$$"


    {
        printf 'status=running\n'

        printf 'start_time=%s\n' "${START_TIME}"
        printf 'start_epoch=%s\n' "${START_EPOCH}"

        printf 'end_time=\n'
        printf 'end_epoch=\n'

        printf 'duration_seconds=\n'
        printf 'exit_code=\n'

        printf 'session_name=%s\n' "${SESSION_NAME}"

        printf 'job_id=%s\n' "${JOB_ID}"
        printf 'job_type=%s\n' "${JOB_TYPE}"
        printf 'job_name=%s\n' "${JOB_NAME}"

        printf 'project_dir=%s\n' "${PROJECT_DIR}"

        printf 'stdout_log=%s\n' "${STDOUT_LOG}"
        printf 'stderr_log=%s\n' "${STDERR_LOG}"

        # stage_file is the file currently used by checker.
        # While running, this points to the live stage file.
        printf 'stage_file=%s\n' "${STAGE_FILE}"

        # Keep original live stage path for provenance.
        printf 'stage_live_file=%s\n' "${STAGE_FILE}"

        printf 'runner_script=%s\n' "${RUNNER_SCRIPT}"

        printf 'cmd_source=%s\n' "${CMD_SOURCE}"

        printf 'pre_cmd_preview=%s\n' "${PRE_CMD_PREVIEW}"
        printf 'cmd_preview=%s\n' "${CMD_PREVIEW}"

        printf 'timezone=%s\n' "${TIMEZONE}"

        printf 'run_in_tmux=%s\n' "${RUN_IN_TMUX}"
        printf 'show_info=%s\n' "${SHOW_INFO}"

    } > "${tmp_status}"


    mv -f \
        "${tmp_status}" \
        "${STATUS_FILE}"
}


write_status_running


# ============================================================
# Initialize logs
# ============================================================

: > "${STDOUT_LOG}"

: > "${STDERR_LOG}"


# ============================================================
# Latest links
# ============================================================

ln -sfn \
    "${STDOUT_LOG}" \
    "${LATEST_STDOUT_LINK}"


ln -sfn \
    "${STDERR_LOG}" \
    "${LATEST_STDERR_LINK}"


ln -sfn \
    "${STATUS_FILE}" \
    "${LATEST_STATUS_LINK}"


# ============================================================
# Build runner script
#
# Important:
#
# The final status is NOT built using a heredoc containing
# CMD_FULL.
#
# This avoids shell re-expansion of things such as:
#
#   $1
#   $2
#   ${VAR}
#
# inside user commands when the EXIT trap runs.
# ============================================================

build_runner_script() {

    cat <<EOF
#!/usr/bin/env bash
set -euo pipefail

export TZ="${TIMEZONE}"

cd "${PROJECT_DIR}"


END_TIME=""
END_EPOCH=""
DURATION_SECONDS=""
EXIT_CODE=""
FINAL_STATUS=""


# ============================================================
# Final bookkeeping
# ============================================================

finish() {

    EXIT_CODE="\$1"


    # --------------------------------------------------------
    # Bookkeeping must never replace the real job exit status.
    #
    # Disable errexit and nounset inside the EXIT handler.
    # --------------------------------------------------------

    set +e
    set +u


    END_TIME="\$(date '+%Y-%m-%d %H:%M:%S')"

    END_EPOCH="\$(date +%s)"

    DURATION_SECONDS=\$((END_EPOCH - ${START_EPOCH}))


    if [[ "\${EXIT_CODE}" == "0" ]]; then
        FINAL_STATUS="completed"
    else
        FINAL_STATUS="failed"
    fi


    # --------------------------------------------------------
    # Snapshot final stage
    #
    # During execution STAGE_FILE may be a branch-level live
    # file, for example:
    #
    #   picrust/picrust2sc/dehost/functional_status.txt
    #
    # At completion its current value is copied to a
    # job-specific .stage file.
    #
    # This prevents future jobs from changing historical stage
    # information.
    # --------------------------------------------------------

    FINAL_STAGE_FILE=""


    if [[ -n "${STAGE_FILE}" ]]; then

        if [[ -f "${STAGE_FILE}" ]]; then

            cp -f \
                "${STAGE_FILE}" \
                "${JOB_STAGE_FILE}" \
                2>/dev/null

            if [[ -f "${JOB_STAGE_FILE}" ]]; then
                FINAL_STAGE_FILE="${JOB_STAGE_FILE}"
            fi

        fi

    fi


    # --------------------------------------------------------
    # Atomic final status update
    #
    # Start with the existing running status and replace only
    # fields that change when the job finishes.
    #
    # This means command text never needs to be re-expanded by
    # the shell inside finish().
    # --------------------------------------------------------

    FINAL_STATUS_TMP="${STATUS_FILE}.tmp.\$\$"


    awk \
        -v final_status="\${FINAL_STATUS}" \
        -v end_time="\${END_TIME}" \
        -v end_epoch="\${END_EPOCH}" \
        -v duration_seconds="\${DURATION_SECONDS}" \
        -v exit_code="\${EXIT_CODE}" \
        -v final_stage_file="\${FINAL_STAGE_FILE}" \
        '
        BEGIN {
            FS = OFS = "="
        }

        \$1 == "status" {
            print "status", final_status
            next
        }

        \$1 == "end_time" {
            print "end_time", end_time
            next
        }

        \$1 == "end_epoch" {
            print "end_epoch", end_epoch
            next
        }

        \$1 == "duration_seconds" {
            print "duration_seconds", duration_seconds
            next
        }

        \$1 == "exit_code" {
            print "exit_code", exit_code
            next
        }

        \$1 == "stage_file" {

            if (final_stage_file != "") {
                print "stage_file", final_stage_file
            } else {
                print
            }

            next
        }

        {
            print
        }
        ' \
        "${STATUS_FILE}" \
        > "\${FINAL_STATUS_TMP}"


    # --------------------------------------------------------
    # Replace status only if a non-empty temporary status was
    # successfully created.
    # --------------------------------------------------------

    if [[ -s "\${FINAL_STATUS_TMP}" ]]; then

        mv -f \
            "\${FINAL_STATUS_TMP}" \
            "${STATUS_FILE}"

    else

        rm -f \
            "\${FINAL_STATUS_TMP}"

    fi


    return 0
}


trap 'finish \$?' EXIT


# ============================================================
# Actual job
# ============================================================

{
EOF


    # --------------------------------------------------------
    # Optional pre-command
    # --------------------------------------------------------

    if [[ -n "${PRE_CMD}" ]]; then

        cat <<EOF
${PRE_CMD}

EOF

    fi


    # --------------------------------------------------------
    # Main command
    # --------------------------------------------------------

    cat <<EOF
${CMD_FULL}

} > "${STDOUT_LOG}" 2> "${STDERR_LOG}"
EOF
}


# ============================================================
# Create runner
# ============================================================

build_runner_script > "${RUNNER_SCRIPT}"

chmod +x "${RUNNER_SCRIPT}"


# ============================================================
# Display job information
# ============================================================

if [[ "${SHOW_INFO}" == "true" ]]; then

    echo "[INFO] JOB_TYPE      = ${JOB_TYPE}"
    echo "[INFO] JOB_NAME      = ${JOB_NAME}"

    echo "[INFO] PROJECT_DIR   = ${PROJECT_DIR}"

    echo "[INFO] JOB_ID        = ${JOB_ID}"

    echo "[INFO] SESSION_NAME  = ${SESSION_NAME}"

    echo "[INFO] LOG_DIR       = ${LOG_DIR}"

    echo "[INFO] STATUS_FILE   = ${STATUS_FILE}"

    echo "[INFO] STDOUT_LOG    = ${STDOUT_LOG}"

    echo "[INFO] STDERR_LOG    = ${STDERR_LOG}"

    echo "[INFO] RUNNER_SCRIPT = ${RUNNER_SCRIPT}"


    if [[ -n "${STAGE_FILE}" ]]; then
        echo "[INFO] STAGE_FILE    = ${STAGE_FILE}"
    fi


    if [[ -n "${PRE_CMD}" ]]; then
        echo "[INFO] PRE_CMD       = ${PRE_CMD_PREVIEW}"
    fi


    echo "[INFO] CMD_SOURCE    = ${CMD_SOURCE}"

    echo "[INFO] CMD_PREVIEW   = ${CMD_PREVIEW}"

fi


# ============================================================
# Execute
# ============================================================

if [[ "${RUN_IN_TMUX}" == "true" ]]; then


    if ! command -v tmux >/dev/null 2>&1; then

        echo "[ERROR] 找不到 tmux，但 RUN_IN_TMUX=true"

        exit 1
    fi


    if tmux has-session \
        -t "${SESSION_NAME}" \
        2>/dev/null
    then

        echo "[ERROR] tmux session 已存在：${SESSION_NAME}"

        exit 1
    fi


    env TERM="${TMUX_TERM}" \
    tmux new-session \
        -d \
        -s "${SESSION_NAME}" \
        "bash \"${RUNNER_SCRIPT}\""


    if [[ "${SHOW_INFO}" == "true" ]]; then

        echo
        echo "[INFO] 已建立 tmux session: ${SESSION_NAME}"

        echo "[INFO] 查詢任務："
        echo
        echo "  MODE=latest JOB_TYPE=${JOB_TYPE} \\"
        echo "  ./shell_tools/check_tmux_jobs.sh"

    else

        echo "${SESSION_NAME}"

    fi


else


    if [[ "${SHOW_INFO}" == "true" ]]; then
        echo "[INFO] 前景執行"
    fi


    bash "${RUNNER_SCRIPT}"

fi
