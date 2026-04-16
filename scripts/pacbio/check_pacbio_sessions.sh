#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-full}"              # full / brief
TAIL_STDOUT_LINES="${TAIL_STDOUT_LINES:-8}"
TAIL_STDERR_LINES="${TAIL_STDERR_LINES:-5}"

show_last_lines() {
    local file_path="$1"
    local n_lines="$2"

    if [ -f "${file_path}" ]; then
        tail -n "${n_lines}" "${file_path}"
    else
        echo "[WARN] 找不到檔案：${file_path}"
    fi
}

extract_status_line() {
    local stdout_log="$1"

    if [ ! -f "${stdout_log}" ]; then
        echo "NO_STDOUT_LOG"
        return
    fi

    local status_line
    status_line="$(tail -n 20 "${stdout_log}" | sed '/^[[:space:]]*$/d' | tail -n 1)"

    if [ -z "${status_line}" ]; then
        echo "EMPTY_LOG"
    else
        echo "${status_line}"
    fi
}

print_session_report_full() {
    local session_name="$1"
    local project_dir="$2"

    local stdout_log="${project_dir}/logs/nextflow.stdout.log"
    local stderr_log="${project_dir}/logs/nextflow.stderr.log"
    local status_line

    status_line="$(extract_status_line "${stdout_log}")"

    echo "=================================================="
    echo "[INFO] SESSION : ${session_name}"
    echo "[INFO] PROJECT : ${project_dir}"
    echo "[INFO] STATUS  : ${status_line}"
    echo

    echo "[INFO] stdout 最後 ${TAIL_STDOUT_LINES} 行"
    show_last_lines "${stdout_log}" "${TAIL_STDOUT_LINES}"
    echo

    echo "[INFO] stderr 最後 ${TAIL_STDERR_LINES} 行"
    if [ -f "${stderr_log}" ] && [ -s "${stderr_log}" ]; then
        tail -n "${TAIL_STDERR_LINES}" "${stderr_log}"
    else
        echo "[INFO] 目前無錯誤輸出或檔案為空"
    fi
    echo
}

print_session_report_brief() {
    local session_name="$1"
    local project_dir="$2"

    local stdout_log="${project_dir}/logs/nextflow.stdout.log"
    local status_line

    status_line="$(extract_status_line "${stdout_log}")"

    echo "${session_name} | ${project_dir} | ${status_line}"
}

main() {
    if [ "${MODE}" != "full" ] && [ "${MODE}" != "brief" ]; then
        echo "[ERROR] MODE 只能是 full 或 brief"
        exit 1
    fi

    if [ "${MODE}" = "full" ]; then
        echo
        echo "[INFO] PacBio tmux session 狀態總覽"
        echo
    else
        echo "[INFO] PacBio tmux session 狀態摘要"
    fi

    local found_any="false"

    while IFS='|' read -r session_name project_dir; do
        found_any="true"

        if [ "${MODE}" = "full" ]; then
            print_session_report_full "${session_name}" "${project_dir}"
        else
            print_session_report_brief "${session_name}" "${project_dir}"
        fi
    done < <(tmux list-panes -a -F '#S|#{pane_current_path}' 2>/dev/null | grep '^pacbio_' || true)

    if [ "${found_any}" = "false" ]; then
        echo "[INFO] 目前沒有 pacbio_* 的 tmux session"
    fi
}

main "$@"
