#!/usr/bin/env bash
set -euo pipefail

show_last_lines() {
    local file="$1"
    local n="${2:-8}"

    if [ -f "$file" ]; then
        tail -n "$n" "$file"
    else
        echo "[WARN] 找不到檔案: $file"
    fi
}

extract_status() {
    local stdout_log="$1"

    if [ ! -f "$stdout_log" ]; then
        echo "NO_STDOUT_LOG"
        return
    fi

    local last_line
    last_line="$(tail -n 20 "$stdout_log" | sed '/^[[:space:]]*$/d' | tail -n 1)"

    if [ -z "$last_line" ]; then
        echo "EMPTY_LOG"
        return
    fi

    echo "$last_line"
}

printf "\n[INFO] PacBio tmux session 狀態總覽\n\n"

found_any=false

while IFS='|' read -r session_name project_dir; do
    found_any=true

    stdout_log="${project_dir}/logs/nextflow.stdout.log"
    stderr_log="${project_dir}/logs/nextflow.stderr.log"

    status_line="$(extract_status "$stdout_log")"

    echo "=================================================="
    echo "SESSION   : ${session_name}"
    echo "PROJECT   : ${project_dir}"
    echo "STATUS    : ${status_line}"
    echo

    echo "[stdout 最後 8 行]"
    show_last_lines "$stdout_log" 8
    echo

    if [ -f "$stderr_log" ] && [ -s "$stderr_log" ]; then
        echo "[stderr 最後 5 行]"
        tail -n 5 "$stderr_log"
        echo
    else
        echo "[stderr]"
        echo "目前無錯誤輸出或檔案為空"
        echo
    fi

done < <(tmux list-panes -a -F '#S|#{pane_current_path}' 2>/dev/null | grep '^pacbio_' || true)

if [ "$found_any" = false ]; then
    echo "[INFO] 目前沒有 pacbio_* 的 tmux session"
fi
