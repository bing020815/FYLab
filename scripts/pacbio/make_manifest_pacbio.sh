#!/usr/bin/env bash
set -euo pipefail

usage() {
cat <<'EOF'
Usage:
  make_manifest_pacbio.sh [PROJECT_DIR] [options]

Description:
  建立 PacBio full-length FASTQ 的 samples.tsv 與 metadata.tsv。

  預設自動移除：
    .fastq / .fastq.gz
    _hifi_reads
    結尾的 _RQ<number>

  Example:
    S012240827A_PB16F24065_RQ30_hifi_reads.fastq.gz
    -> S012240827A_PB16F24065

Options:
  --remove STRING
      額外移除 sample ID 中指定的固定字串。
      若 delimiter（例如 _ 或 -）也不要保留，請包含在 STRING 中。
      可重複使用。

  -h, --help
      顯示使用說明。

Examples:
  make_manifest_pacbio.sh
  make_manifest_pacbio.sh /path/to/project
  make_manifest_pacbio.sh . --remove "_test"
  make_manifest_pacbio.sh . --remove "_test" --remove "_PacBio"

Outputs:
  PROJECT_DIR/samples.tsv
  PROJECT_DIR/metadata.tsv
EOF
}

PROJECT_DIR=""
REMOVE_STRINGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --remove)
            if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
                echo "[ERROR] --remove 需要指定要移除的字串" >&2
                exit 1
            fi
            REMOVE_STRINGS+=("$2")
            shift 2
            ;;
        --*)
            echo "[ERROR] 未知參數：$1" >&2
            echo "[INFO] 使用 --help 查看使用方法" >&2
            exit 1
            ;;
        *)
            if [ -n "$PROJECT_DIR" ]; then
                echo "[ERROR] 只能指定一個 PROJECT_DIR：$1" >&2
                exit 1
            fi
            PROJECT_DIR="$1"
            shift
            ;;
    esac
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
[ -d "$PROJECT_DIR" ] || { echo "[ERROR] PROJECT_DIR 不存在：$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

RAW_DIR="${PROJECT_DIR}/raw_fastq"
SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"

if [ ! -d "$RAW_DIR" ]; then
    echo "[ERROR] 找不到資料夾：$RAW_DIR"
    echo "[ERROR] 請先建立 raw_fastq/，並將 PacBio fastq 或 tar.gz 放入其中"
    exit 1
fi

extract_tar_archives() {
    mapfile -t TAR_FILES < <(find "$RAW_DIR" -maxdepth 1 -type f         \( -name "*.fastq.tar.gz" -o -name "*.tar.gz" \) | sort)
    [ "${#TAR_FILES[@]}" -gt 0 ] || return 0
    echo "[INFO] 偵測到 tar 壓縮檔，開始解壓縮"
    local tarf base stem outdir
    for tarf in "${TAR_FILES[@]}"; do
        base="$(basename "$tarf")"; stem="${base%.tar.gz}"
        outdir="${RAW_DIR}/extracted_${stem}"
        if [ -d "$outdir" ]; then
            echo "[INFO] 已存在解壓縮資料夾，略過：$outdir"
            continue
        fi
        mkdir -p "$outdir"
        echo "[INFO] 解壓縮 $base -> $outdir"
        tar -xzf "$tarf" -C "$outdir"
    done
}

collect_fastq_files() {
    mapfile -t FASTQ_FILES < <(find "$RAW_DIR" -type f         \( -name "*.fastq.gz" -o -name "*.fastq" \) ! -name "*.tar.gz" | sort)
}

infer_sample_name() {
    local filepath="$1" base remove_string
    base="$(basename "$filepath")"
    base="${base%.fastq.gz}"
    base="${base%.fastq}"
    base="${base%_hifi_reads}"
    base="$(printf '%s\n' "$base" | sed -E 's/_RQ[0-9]+$//')"
    for remove_string in "${REMOVE_STRINGS[@]}"; do
        base="${base//"$remove_string"/}"
    done
    printf '%s\n' "$base"
}

extract_tar_archives
collect_fastq_files

if [ "${#FASTQ_FILES[@]}" -eq 0 ]; then
    echo "[ERROR] $RAW_DIR 內沒有可用的 fastq 檔案"
    echo "[ERROR] 支援：*.fastq、*.fastq.gz、*.fastq.tar.gz"
    exit 1
fi

declare -A SAMPLE_TO_FILE=()
SAMPLE_NAMES=()

echo "[INFO] Sample ID 預覽"
for f in "${FASTQ_FILES[@]}"; do
    sample="$(infer_sample_name "$f")"
    if [ -z "$sample" ]; then
        echo "[ERROR] Sample ID 為空：$f" >&2; exit 1
    fi
    if [[ -v 'SAMPLE_TO_FILE[$sample]' ]]; then
        echo "[ERROR] Sample ID 重複：$sample" >&2
        echo "[ERROR] 第一個檔案：${SAMPLE_TO_FILE[$sample]}" >&2
        echo "[ERROR] 第二個檔案：$f" >&2
        echo "[ERROR] 請調整檔名或 --remove 設定後重新執行。" >&2
        exit 1
    fi
    SAMPLE_TO_FILE["$sample"]="$f"
    SAMPLE_NAMES+=("$sample")
    printf '  %s -> %s\n' "$(basename "$f")" "$sample"
done

SAMPLES_TMP="$(mktemp "${PROJECT_DIR}/.samples.tsv.XXXXXX")"
METADATA_TMP="$(mktemp "${PROJECT_DIR}/.metadata.tsv.XXXXXX")"
cleanup() { rm -f "${SAMPLES_TMP:-}" "${METADATA_TMP:-}"; }
trap cleanup EXIT

printf 'sample-id\tabsolute-filepath\n' > "$SAMPLES_TMP"
printf 'sample_name\tcondition\n' > "$METADATA_TMP"
for sample in "${SAMPLE_NAMES[@]}"; do
    f="${SAMPLE_TO_FILE[$sample]}"; abs="$(realpath "$f")"
    printf '%s\t%s\n' "$sample" "$abs" >> "$SAMPLES_TMP"
    printf '%s\tUnknown\n' "$sample" >> "$METADATA_TMP"
done

mv "$SAMPLES_TMP" "$SAMPLES_TSV"
mv "$METADATA_TMP" "$METADATA_TSV"
trap - EXIT

echo
echo "[INFO] 已建立：$SAMPLES_TSV"
echo "[INFO] 已建立：$METADATA_TSV"
echo "[INFO] 共納入 ${#FASTQ_FILES[@]} 個 FASTQ 檔案"
if [ "${#REMOVE_STRINGS[@]}" -gt 0 ]; then
    echo "[INFO] 額外移除字串："
    for remove_string in "${REMOVE_STRINGS[@]}"; do echo "       $remove_string"; done
fi
echo "[INFO] 請確認 metadata.tsv 的 condition 是否需要手動修改。"
