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

extract_active_cmd() {
    local project_dir="$1"

    local cmds
    cmds="$(
        ps -eo pid,comm,args --no-headers 2>/dev/null \
        | grep "${project_dir}" \
        | grep -v grep \
        | awk '{print $2}' \
        | grep -E 'seqkit|csvtk|cutadapt|qiime|vsearch|Rscript|R|python|perl|awk|sed|bash' \
        | sort -u \
        | paste -sd ',' - \
        | sed 's/,/, /g'
    )"

    if [ -n "${cmds}" ]; then
        echo "${cmds}"
    else
        echo "NA"
    fi
}

extract_latest_executor_block() {
    local stdout_log="$1"

    if [ ! -f "${stdout_log}" ]; then
        return 0
    fi

    awk '
        /^executor[[:space:]]*>/ {start=NR}
        {lines[NR]=$0}
        END {
            if (start > 0) {
                for (i=start; i<=NR; i++) print lines[i]
            }
        }
    ' "${stdout_log}"
}

extract_executor_name() {
    local block="$1"

    local executor_line
    executor_line="$(printf '%s\n' "${block}" | grep '^executor[[:space:]]*>' | tail -n 1 || true)"

    if [ -n "${executor_line}" ]; then
        echo "${executor_line}"
    else
        echo "NA"
    fi
}

extract_current_task() {
    local block="$1"

    if [ -z "${block}" ]; then
        echo "NA"
        return
    fi

    local current_line
    current_line="$(
        printf '%s\n' "${block}" \
        | grep 'pb16S:' \
        | grep -v '✔' \
        | grep -v '^\[-' \
        | head -n 1 || true
    )"

    if [ -n "${current_line}" ]; then
        local task_name progress
        task_name="$(printf '%s\n' "${current_line}" | grep -Eo 'pb16S:[[:alnum:]_]+' | head -n 1 || true)"
        progress="$(printf '%s\n' "${current_line}" | grep -Eo '\|[[:space:]]*[0-9]+ of [0-9]+' | sed 's/^|[[:space:]]*//' || true)"

        if [ -n "${task_name}" ] && [ -n "${progress}" ]; then
            echo "${task_name} | ${progress}"
            return
        elif [ -n "${task_name}" ]; then
            echo "${task_name}"
            return
        fi
    fi

    echo "NA"
}

extract_pending_tasks() {
    local block="$1"

    if [ -z "${block}" ]; then
        echo "NA"
        return
    fi

    local pending
    pending="$(
        printf '%s\n' "${block}" \
        | grep '^\[-' \
        | grep -Eo 'pb16S:[[:alnum:]_]+' \
        | head -n 6 \
        | paste -sd ',' - \
        | sed 's/,/, /g'
    )"

    if [ -n "${pending}" ]; then
        echo "${pending}"
    else
        echo "NA"
    fi
}

extract_env_building() {
    local stdout_log="$1"

    if [ ! -f "${stdout_log}" ]; then
        return 0
    fi

    local env_line
    env_line="$(grep 'Creating env using conda:' "${stdout_log}" | tail -n 1 || true)"

    if [ -n "${env_line}" ]; then
        echo "${env_line}"
    fi
}

print_session_report_full() {
    local session_name="$1"
    local project_dir="$2"

    local stdout_log="${project_dir}/logs/nextflow.stdout.log"
    local stderr_log="${project_dir}/logs/nextflow.stderr.log"
    local status_file="${project_dir}/logs/run_pacbio.status"

    local run_status start_time elapsed_time active_cmd
    local executor_block executor_name current_task pending_tasks env_building

    run_status="$(read_status_value "${status_file}" "status")"
    start_time="$(read_status_value "${status_file}" "start_time")"
    elapsed_time="$(get_elapsed_time "${status_file}")"
    active_cmd="$(extract_active_cmd "${project_dir}")"

    executor_block="$(extract_latest_executor_block "${stdout_log}")"
    executor_name="$(extract_executor_name "${executor_block}")"
    current_task="$(extract_current_task "${executor_block}")"
    pending_tasks="$(extract_pending_tasks "${executor_block}")"
    env_building="$(extract_env_building "${stdout_log}")"

    if [ -z "${run_status}" ]; then
        run_status="UNKNOWN"
    fi

    if [ -z "${start_time}" ]; then
        start_time="NA"
    fi

    echo "=================================================="
    echo "[INFO] SESSION       : ${session_name}"
    echo "[INFO] PROJECT       : ${project_dir}"
    echo "[INFO] STATUS        : ${run_status}"
    echo "[INFO] START_TIME    : ${start_time}"
    echo "[INFO] ELAPSED       : ${elapsed_time}"
    echo "[INFO] EXECUTOR      : ${executor_name}"
    echo "[INFO] CURRENT_TASK  : ${current_task}"
    echo "[INFO] ACTIVE_CMD    : ${active_cmd}"
    echo "[INFO] PENDING_TASKS : ${pending_tasks}"
    if [ "${current_task}" = "NA" ] && [ -n "${env_building}" ]; then
        echo "[INFO] ENV_BUILD     : ${env_building}"
    fi
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

    local run_status start_time elapsed_time active_cmd
    local executor_block executor_name current_task

    run_status="$(read_status_value "${status_file}" "status")"
    start_time="$(read_status_value "${status_file}" "start_time")"
    elapsed_time="$(get_elapsed_time "${status_file}")"
    active_cmd="$(extract_active_cmd "${project_dir}")"

    executor_block="$(extract_latest_executor_block "${stdout_log}")"
    executor_name="$(extract_executor_name "${executor_block}")"
    current_task="$(extract_current_task "${executor_block}")"

    if [ -z "${run_status}" ]; then
        run_status="UNKNOWN"
    fi

    if [ -z "${start_time}" ]; then
        start_time="NA"
    fi

    echo "${session_name} | ${run_status} | ${start_time} | ${elapsed_time} | ${executor_name} | ${current_task} | ${active_cmd}"
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
