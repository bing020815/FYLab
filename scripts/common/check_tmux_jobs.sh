#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-summary}"          # summary / all / latest / session
JOB_TYPE="${JOB_TYPE:-}"
SESSION_NAME="${SESSION_NAME:-}"
SHOW_CMD="${SHOW_CMD:-false}"
TAIL_STDOUT_LINES="${TAIL_STDOUT_LINES:-5}"
TAIL_STDERR_LINES="${TAIL_STDERR_LINES:-5}"
SEARCH_ROOT="${SEARCH_ROOT:-.}"

read_status_value() {
    local status_file="$1"
    local key="$2"
    grep "^${key}=" "${status_file}" 2>/dev/null | head -n 1 | cut -d'=' -f2-
}

format_elapsed() {
    local seconds="$1"
    if ! [[ "${seconds}" =~ ^[0-9]+$ ]]; then
        echo "NA"
        return
    fi
    local h=$((seconds / 3600))
    local m=$(((seconds % 3600) / 60))
    local s=$((seconds % 60))
    printf "%02d:%02d:%02d" "${h}" "${m}" "${s}"
}

get_elapsed_from_status() {
    local status_file="$1"
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
        format_elapsed "${duration_seconds}"
    fi
}

get_cpu_total() {
    nproc 2>/dev/null || echo "NA"
}

get_cpu_used_and_total() {
    local total_cpus
    total_cpus="$(get_cpu_total)"

    if ! [[ "${total_cpus}" =~ ^[0-9]+$ ]]; then
        echo "NA/NA"
        return 0
    fi

    read -r _ u1 n1 s1 i1 w1 irq1 sirq1 st1 _ < /proc/stat
    local idle1 total1
    idle1=$((i1 + w1))
    total1=$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1 + st1))

    sleep 0.2

    read -r _ u2 n2 s2 i2 w2 irq2 sirq2 st2 _ < /proc/stat
    local idle2 total2
    idle2=$((i2 + w2))
    total2=$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2 + st2))

    local totald idled used_percent used_cpus
    totald=$((total2 - total1))
    idled=$((idle2 - idle1))

    if [ "${totald}" -le 0 ]; then
        echo "NA/${total_cpus}"
        return 0
    fi

    used_percent=$(( (100 * (totald - idled)) / totald ))
    used_cpus=$(( (used_percent * total_cpus + 50) / 100 ))

    echo "${used_cpus}/${total_cpus}"
}

tmux_alive() {
    local session_name="$1"
    if [ -z "${session_name}" ]; then
        echo "no"
        return
    fi
    if tmux has-session -t "${session_name}" 2>/dev/null; then
        echo "yes"
    else
        echo "no"
    fi
}

collect_status_files() {
    find "${SEARCH_ROOT}" -type f -name '*.status' ! -name 'latest_*' 2>/dev/null | sort
}

filter_status_files() {
    local files=("$@")
    local f jt sn
    for f in "${files[@]}"; do
        jt="$(read_status_value "${f}" "job_type")"
        sn="$(read_status_value "${f}" "session_name")"

        if [ -n "${JOB_TYPE}" ] && [ "${jt}" != "${JOB_TYPE}" ]; then
            continue
        fi

        if [ -n "${SESSION_NAME}" ] && [ "${sn}" != "${SESSION_NAME}" ]; then
            continue
        fi

        echo "${f}"
    done
}

print_summary_line() {
    local status_file="$1"
    local session_name job_type job_name status start_time elapsed
    session_name="$(read_status_value "${status_file}" "session_name")"
    job_type="$(read_status_value "${status_file}" "job_type")"
    job_name="$(read_status_value "${status_file}" "job_name")"
    status="$(read_status_value "${status_file}" "status")"
    start_time="$(read_status_value "${status_file}" "start_time")"
    elapsed="$(get_elapsed_from_status "${status_file}")"

    printf "%-28s | %-10s | %-16s | %-10s | %-19s | %s\n" \
        "${session_name}" "${job_type}" "${job_name}" "${status}" "${start_time}" "${elapsed}"
}

print_detail() {
    local status_file="$1"
    local session_name job_type job_name status start_time end_time elapsed project_dir stdout_log stderr_log cmd_preview cmd_full exit_code pre_cmd_preview pre_cmd
    session_name="$(read_status_value "${status_file}" "session_name")"
    job_type="$(read_status_value "${status_file}" "job_type")"
    job_name="$(read_status_value "${status_file}" "job_name")"
    status="$(read_status_value "${status_file}" "status")"
    start_time="$(read_status_value "${status_file}" "start_time")"
    end_time="$(read_status_value "${status_file}" "end_time")"
    elapsed="$(get_elapsed_from_status "${status_file}")"
    project_dir="$(read_status_value "${status_file}" "project_dir")"
    stdout_log="$(read_status_value "${status_file}" "stdout_log")"
    stderr_log="$(read_status_value "${status_file}" "stderr_log")"
    cmd_preview="$(read_status_value "${status_file}" "cmd_preview")"
    cmd_full="$(read_status_value "${status_file}" "cmd_full")"
    pre_cmd_preview="$(read_status_value "${status_file}" "pre_cmd_preview")"
    pre_cmd="$(read_status_value "${status_file}" "pre_cmd")"
    exit_code="$(read_status_value "${status_file}" "exit_code")"

    echo "=================================================="
    echo "[INFO] SESSION      : ${session_name}"
    echo "[INFO] JOB_TYPE     : ${job_type}"
    echo "[INFO] JOB_NAME     : ${job_name}"
    echo "[INFO] STATUS       : ${status}"
    echo "[INFO] TMUX_ALIVE   : $(tmux_alive "${session_name}")"
    echo "[INFO] START_TIME   : ${start_time}"
    echo "[INFO] END_TIME     : ${end_time:-NA}"
    echo "[INFO] ELAPSED      : ${elapsed}"
    echo "[INFO] EXIT_CODE    : ${exit_code:-NA}"
    echo "[INFO] PROJECT_DIR  : ${project_dir}"
    echo "[INFO] STATUS_FILE  : ${status_file}"
    echo "[INFO] STDOUT_LOG   : ${stdout_log}"
    echo "[INFO] STDERR_LOG   : ${stderr_log}"
    if [ -n "${pre_cmd_preview}" ]; then
        echo "[INFO] PRE_CMD      : ${pre_cmd_preview}"
    fi
    echo "[INFO] CMD_PREVIEW  : ${cmd_preview}"

    if [ "${SHOW_CMD}" = "true" ]; then
        if [ -n "${pre_cmd}" ]; then
            echo "[INFO] PRE_CMD_FULL : ${pre_cmd}"
        fi
        echo "[INFO] CMD_FULL     : ${cmd_full}"
    fi
    echo

    if [ -n "${stdout_log}" ] && [ -f "${stdout_log}" ]; then
        echo "[INFO] stdout 最後 ${TAIL_STDOUT_LINES} 行"
        tail -n "${TAIL_STDOUT_LINES}" "${stdout_log}"
        echo
    fi

    if [ -n "${stderr_log}" ] && [ -f "${stderr_log}" ]; then
        echo "[INFO] stderr 最後 ${TAIL_STDERR_LINES} 行"
        if [ -s "${stderr_log}" ]; then
            tail -n "${TAIL_STDERR_LINES}" "${stderr_log}"
        else
            echo "[INFO] 目前無錯誤輸出或檔案為空"
        fi
        echo
    fi
}

main() {
    mapfile -t all_status_files < <(collect_status_files)
    if [ "${#all_status_files[@]}" -eq 0 ]; then
        echo "[INFO] CPU_USAGE     : $(get_cpu_used_and_total)"
        echo "[INFO] 找不到任何 status 檔"
        exit 0
    fi

    mapfile -t filtered_status_files < <(filter_status_files "${all_status_files[@]}")
    if [ "${#filtered_status_files[@]}" -eq 0 ]; then
        echo "[INFO] CPU_USAGE     : $(get_cpu_used_and_total)"
        echo "[INFO] 找不到符合條件的任務"
        exit 0
    fi

    case "${MODE}" in
        summary)
            echo "[INFO] CPU_USAGE     : $(get_cpu_used_and_total)"
            echo
            printf "%-28s | %-10s | %-16s | %-10s | %-19s | %s\n" \
                "SESSION" "JOB_TYPE" "JOB_NAME" "STATUS" "START_TIME" "ELAPSED"
            printf '%s\n' "---------------------------------------------------------------------------------------------------------------"
            for f in "${filtered_status_files[@]}"; do
                print_summary_line "${f}"
            done
            ;;
        all)
            echo "[INFO] CPU_USAGE     : $(get_cpu_used_and_total)"
            echo
            for f in "${filtered_status_files[@]}"; do
                print_detail "${f}"
            done
            ;;
        latest)
            echo "[INFO] CPU_USAGE     : $(get_cpu_used_and_total)"
            echo
            latest_file=""
            latest_epoch=0
            for f in "${filtered_status_files[@]}"; do
                start_epoch="$(read_status_value "${f}" "start_epoch")"
                if [[ "${start_epoch}" =~ ^[0-9]+$ ]] && [ "${start_epoch}" -ge "${latest_epoch}" ]; then
                    latest_epoch="${start_epoch}"
                    latest_file="${f}"
                fi
            done
            if [ -z "${latest_file}" ]; then
                echo "[INFO] 找不到最新任務"
                exit 0
            fi
            print_detail "${latest_file}"
            ;;
        session)
            echo "[INFO] CPU_USAGE     : $(get_cpu_used_and_total)"
            echo
            if [ -z "${SESSION_NAME}" ]; then
                echo "[ERROR] MODE=session 時必須提供 SESSION_NAME"
                exit 1
            fi
            for f in "${filtered_status_files[@]}"; do
                print_detail "${f}"
            done
            ;;
        *)
            echo "[ERROR] MODE 僅支援 summary / all / latest / session"
            exit 1
            ;;
    esac
}

main "$@"
