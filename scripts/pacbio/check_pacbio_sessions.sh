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

read_status_value() {
    local status_file="$1"
    local key="$2"

    if [ ! -f "${status_file}" ]; then
        return 0
    fi

    grep "^${key}=" "${status_file}" 2>/dev/null | head -n 1 | cut -d'=' -f2-
}

format_elapsed() {
    local total_seconds="$1"

    if ! [[ "${total_seconds}" =~ ^[0-9]+$ ]]; then
        echo "NA"
        return
    fi

    local hours minutes seconds
    hours=$((total_seconds / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    seconds=$((total_seconds % 60))

    printf "%02d:%02d:%02d" "${hours}" "${minutes}" "${seconds}"
}

get_elapsed_time() {
    local status_file="$1"

    if [ ! -f "${status_file}" ]; then
        echo "NA"
        return
    fi

    local status start_epoch duration_seconds now elapsed
    status="$(read_status_value "${status_file}" "status")"
    start_epoch="$(read_status_value "${status_file}" "start_epoch")"
    duration_seconds="$(read_status_value "${status_file}" "duration_seconds")"

    if [ "${status}" = "running" ]; then
        if [[ "${start_epoch}" =~ ^[0-9]+$ ]]; then
            now="$(date +%s)"
            elapsed=$((now - start_epoch))
            format_elapsed "${elapsed}"
        else
            echo "NA"
        fi
    else
        if [[ "${duration_seconds}" =~ ^[0-9]+$ ]]; then
            format_elapsed "${duration_seconds}"
        else
            echo "NA"
        fi
    fi
}

extract_step_line() {
    local stdout_log="$1"

    if [ ! -f "${stdout_log}" ]; then
        echo "NO_STDOUT_LOG"
        return
    fi

    local recent_text
    recent_text="$(tail -n 200 "${stdout_log}" 2>/dev/null || true)"

    if [ -z "${recent_text}" ]; then
        echo "EMPTY_LOG"
        return
    fi

    # 從最新往回找，優先抓最有代表性的狀態
    while IFS= read -r line; do
        # 跳過空白行
        if [ -z "$(printf '%s' "${line}" | tr -d '[:space:]')" ]; then
            continue
        fi

        # 1. 若最近有建立 conda 環境，優先顯示
        if printf '%s\n' "${line}" | grep -q 'Creating env using conda:'; then
            echo "${line}"
            return
        fi

        # 2. 若是 Nextflow workflow 節點狀態列，抓出 pb16S:xxxx
        if printf '%s\n' "${line}" | grep -q 'pb16S:'; then
            printf '%s\n' "${line}" | grep -Eo 'pb16S:[[:alnum:]_]+' | head -n 1
            return
        fi

        # 3. 跳過泛用摘要行，避免誤判成 step
        if printf '%s\n' "${line}" | grep -q '^Plus [0-9]\+ more processes waiting for tasks'; then
            continue
        fi

        # 4. 其他非空白行，作為最後 fallback
        echo "${line}"
        return
    done < <(printf '%s\n' "${recent_text}" | tac)

    echo "EMPTY_LOG"
}

print_session_report_full() {
    local session_name="$1"
    local project_dir="$2"

    local stdout_log="${project_dir}/logs/nextflow.stdout.log"
    local stderr_log="${project_dir}/logs/nextflow.stderr.log"
    local status_file="${project_dir}/logs/run_pacbio.status"

    local step_line run_status start_time elapsed_time
    step_line="$(extract_step_line "${stdout_log}")"
    run_status="$(read_status_value "${status_file}" "status")"
    start_time="$(read_status_value "${status_file}" "start_time")"
    elapsed_time="$(get_elapsed_time "${status_file}")"

    if [ -z "${run_status}" ]; then
        run_status="UNKNOWN"
    fi

    if [ -z "${start_time}" ]; then
        start_time="NA"
    fi

    echo "=================================================="
    echo "[INFO] SESSION    : ${session_name}"
    echo "[INFO] PROJECT    : ${project_dir}"
    echo "[INFO] STATUS     : ${run_status}"
    echo "[INFO] START_TIME : ${start_time}"
    echo "[INFO] ELAPSED    : ${elapsed_time}"
    echo "[INFO] STEP       : ${step_line}"
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
    local status_file="${project_dir}/logs/run_pacbio.status"

    local step_line run_status start_time elapsed_time
    step_line="$(extract_step_line "${stdout_log}")"
    run_status="$(read_status_value "${status_file}" "status")"
    start_time="$(read_status_value "${status_file}" "start_time")"
    elapsed_time="$(get_elapsed_time "${status_file}")"

    if [ -z "${run_status}" ]; then
        run_status="UNKNOWN"
    fi

    if [ -z "${start_time}" ]; then
        start_time="NA"
    fi

    echo "${session_name} | ${run_status} | ${start_time} | ${elapsed_time} | ${step_line}"
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
