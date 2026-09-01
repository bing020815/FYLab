#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# FYLab - Export QIIME2 outputs to phyloseq
#
# 功能：
#   1. table.qza -> feature-table.biom -> otu_table.tsv
#   2. rep-seqs.qza -> dna-sequences.fasta
#   3. taxonomy.qza / taxonomy.tsv -> taxonomy.tsv
#
#   4. DADA2 provenance：
#      - Primary：從 rep-seqs.qza 的 QIIME2 provenance 讀取
#      - Fallback：logs/latest_denoise.status
#      - 支援 denoise-paired / denoise-single / denoise-ccs
#
#   5. 從 logs/latest_taxonomy.status 反查 taxonomy 執行方式
#
#   6. classify-sklearn：
#      - classifier path / SHA256
#      - classifier_manifest.tsv
#      - reference_set
#      - reference_variant
#      - reference_source
#      - reference_url
#      - taxonomy_depth
#      - db_version
#      - region
#      - classifier training sklearn version
#      - export 當下 runtime sklearn version
#
#   7. classify-consensus-vsearch：
#      - reference reads
#      - reference taxonomy
#
#   8. 建立：
#      phyloseq/taxonomy_source.txt
#      phyloseq/analysis_metadata.txt
#
# 使用：
#   ./scripts/post_upstream/export_table_qza_to_phyloseq.sh
#
# 或：
#   ./scripts/post_upstream/export_table_qza_to_phyloseq.sh /path/to/project
# ============================================================


# ============================================================
# Basic settings
# ============================================================

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

TABLE_QZA="${PROJECT_DIR}/table.qza"
REPSEQS_QZA="${PROJECT_DIR}/rep-seqs.qza"

TAXONOMY_QZA="${PROJECT_DIR}/taxonomy.qza"
TAXONOMY_TSV="${PROJECT_DIR}/taxonomy.tsv"

PROJECT_TAXONOMY_SOURCE="${PROJECT_DIR}/taxonomy_source.txt"

OUTDIR_NAME="${OUTDIR_NAME:-phyloseq}"
OUTDIR="${PROJECT_DIR}/${OUTDIR_NAME}"

LOG_DIR="${PROJECT_DIR}/logs"

LATEST_DENOISE_STATUS="${LOG_DIR}/latest_denoise.status"
LATEST_TAXONOMY_STATUS="${LOG_DIR}/latest_taxonomy.status"

CLASSIFIER_MANIFEST="${CLASSIFIER_MANIFEST:-/home/adprc/classifier/classifier_manifest.tsv}"

QIIME_ENV_NAME="${QIIME_ENV_NAME:-qiime2-2023.2}"

TIMEZONE="${TIMEZONE:-Asia/Taipei}"
export TZ="${TIMEZONE}"

PHYLOSEQ_TAXONOMY_SOURCE="${OUTDIR}/taxonomy_source.txt"
ANALYSIS_METADATA="${OUTDIR}/analysis_metadata.txt"


# ============================================================
# Helpers
# ============================================================

read_kv_value() {
    local file="$1"
    local key="$2"

    grep "^${key}=" "${file}" 2>/dev/null \
        | head -n 1 \
        | cut -d'=' -f2-
}


check_cmd() {
    local cmd="$1"
    local hint="$2"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[ERROR] 找不到 ${cmd} 指令"
        echo "[ERROR] ${hint}"
        exit 1
    fi
}


check_file() {
    local file="$1"

    if [ ! -f "${file}" ]; then
        echo "[ERROR] 找不到輸入檔案：${file}"
        exit 1
    fi
}


resolve_path() {
    local path="$1"

    if [[ "${path}" = /* ]]; then
        printf '%s\n' "${path}"
    else
        printf '%s\n' "${PROJECT_DIR}/${path}"
    fi
}


sha256_file() {
    local file="$1"

    if [ ! -f "${file}" ]; then
        echo "unavailable"
        return
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    else
        echo "unavailable"
    fi
}


extract_cmd_argument() {
    local cmd="$1"
    local arg="$2"

    python - "${cmd}" "${arg}" <<'PY'
import shlex
import sys

cmd = sys.argv[1]
target = sys.argv[2]

try:
    tokens = shlex.split(cmd)
except ValueError:
    tokens = cmd.split()

for i, token in enumerate(tokens[:-1]):
    if token == target:
        print(tokens[i + 1])
        break
PY
}


get_runtime_sklearn_version() {
    python - <<'PY' 2>/dev/null || true
try:
    import sklearn
    print(sklearn.__version__)
except Exception:
    print("unavailable")
PY
}


get_runtime_python_version() {
    python - <<'PY' 2>/dev/null || true
import platform
print(platform.python_version())
PY
}


# ============================================================
# Determine taxonomy input
# ============================================================

prepare_taxonomy_source() {

    TAXONOMY_MODE="auto"
    TAXONOMY_SOURCE_TYPE=""
    TAXONOMY_SOURCE_FILE=""
    TAXONOMY_INPUT=""

    if [ -f "${PROJECT_TAXONOMY_SOURCE}" ]; then

        TAXONOMY_MODE="$(
            read_kv_value \
                "${PROJECT_TAXONOMY_SOURCE}" \
                "taxonomy_mode"
        )"

        TAXONOMY_SOURCE_TYPE="$(
            read_kv_value \
                "${PROJECT_TAXONOMY_SOURCE}" \
                "taxonomy_source_type"
        )"

        TAXONOMY_SOURCE_FILE="$(
            read_kv_value \
                "${PROJECT_TAXONOMY_SOURCE}" \
                "taxonomy_source_file"
        )"

        if [ -n "${TAXONOMY_SOURCE_FILE}" ]; then
            TAXONOMY_INPUT="$(resolve_path "${TAXONOMY_SOURCE_FILE}")"
        fi
    fi


    if [ -z "${TAXONOMY_INPUT}" ]; then

        if [ -f "${TAXONOMY_QZA}" ]; then

            TAXONOMY_MODE="auto"
            TAXONOMY_SOURCE_TYPE="local_qza"
            TAXONOMY_SOURCE_FILE="taxonomy.qza"
            TAXONOMY_INPUT="${TAXONOMY_QZA}"

        elif [ -f "${TAXONOMY_TSV}" ]; then

            TAXONOMY_MODE="auto"
            TAXONOMY_SOURCE_TYPE="local_tsv"
            TAXONOMY_SOURCE_FILE="taxonomy.tsv"
            TAXONOMY_INPUT="${TAXONOMY_TSV}"

        else

            echo "[ERROR] 找不到 taxonomy 來源"
            echo "[ERROR] 請確認專案根目錄至少存在："
            echo "  taxonomy.qza"
            echo "  或 taxonomy.tsv"

            exit 1
        fi
    fi


    if [ ! -f "${TAXONOMY_INPUT}" ]; then
        echo "[ERROR] 找不到 taxonomy 來源檔案：${TAXONOMY_INPUT}"
        exit 1
    fi
}


# ============================================================
# Export table
# ============================================================

export_table_and_biom() {

    echo "[INFO] 匯出 table.qza"

    qiime tools export \
        --input-path "${TABLE_QZA}" \
        --output-path "${OUTDIR}"

    check_file "${OUTDIR}/feature-table.biom"


    echo "[INFO] feature-table.biom -> otu_table.tsv"

    biom convert \
        -i "${OUTDIR}/feature-table.biom" \
        -o "${OUTDIR}/otu_table.tsv" \
        --to-tsv

    check_file "${OUTDIR}/otu_table.tsv"
}


# ============================================================
# Export representative sequences
# ============================================================

export_repseqs() {

    echo "[INFO] 匯出 rep-seqs.qza"

    qiime tools export \
        --input-path "${REPSEQS_QZA}" \
        --output-path "${OUTDIR}"

    check_file "${OUTDIR}/dna-sequences.fasta"
}


# ============================================================
# Prepare taxonomy.tsv
# ============================================================

prepare_taxonomy_tsv() {

    case "${TAXONOMY_INPUT}" in

        *.qza)

            echo "[INFO] taxonomy 來源為 QZA"

            local tmp_dir="${OUTDIR}/taxonomy_export_tmp"

            rm -rf "${tmp_dir}"
            mkdir -p "${tmp_dir}"

            qiime tools export \
                --input-path "${TAXONOMY_INPUT}" \
                --output-path "${tmp_dir}"

            check_file "${tmp_dir}/taxonomy.tsv"

            cp \
                "${tmp_dir}/taxonomy.tsv" \
                "${OUTDIR}/taxonomy.tsv"

            rm -rf "${tmp_dir}"
            ;;


        *.tsv)

            echo "[INFO] taxonomy 來源為 TSV"

            cp \
                "${TAXONOMY_INPUT}" \
                "${OUTDIR}/taxonomy.tsv"
            ;;


        *)

            echo "[ERROR] 不支援 taxonomy 格式：${TAXONOMY_INPUT}"
            exit 1
            ;;
    esac

    check_file "${OUTDIR}/taxonomy.tsv"
}


# ============================================================
# Denoise provenance
# ============================================================

reset_denoise_provenance() {

    DENOISE_PROVENANCE_SOURCE="unavailable"

    DENOISE_METHOD="unknown"

    DENOISE_JOB_STATUS="unknown"
    DENOISE_JOB_NAME=""
    DENOISE_JOB_ID=""
    DENOISE_JOB_START=""
    DENOISE_JOB_END=""

    DENOISE_CMD=""
    DENOISE_INPUT=""

    DENOISE_TRIM_LEFT=""
    DENOISE_TRUNC_LEN=""

    DENOISE_TRIM_LEFT_F=""
    DENOISE_TRIM_LEFT_R=""
    DENOISE_TRUNC_LEN_F=""
    DENOISE_TRUNC_LEN_R=""

    DENOISE_FRONT=""
    DENOISE_ADAPTER=""
    DENOISE_MIN_LEN=""
    DENOISE_MAX_LEN=""
    DENOISE_MAX_EE=""
    DENOISE_MAX_MISMATCH=""
    DENOISE_INDELS=""
    DENOISE_TRUNC_Q=""
    DENOISE_POOLING_METHOD=""
    DENOISE_CHIMERA_METHOD=""
    DENOISE_MIN_FOLD_PARENT_OVER_ABUNDANCE=""
    DENOISE_ALLOW_ONE_OFF=""

    DENOISE_THREADS=""
    DENOISE_N_READS_LEARN=""
    DENOISE_HASHED_FEATURE_IDS=""
    DENOISE_RETAIN_ALL_SAMPLES=""

    DENOISE_QIIME_VERSION=""
    DENOISE_PLUGIN_VERSION=""
    DENOISE_PYTHON_VERSION=""
    DENOISE_ACTION_UUID=""
}


infer_denoise_from_qza() {

    local qza_path="$1"
    local parser_output
    local parser_status

    if [ ! -f "${qza_path}" ]; then
        return 1
    fi

    set +e

    parser_output="$(
        python - "${qza_path}" <<'PY'
import re
import sys
import zipfile

qza_path = sys.argv[1]

TARGET_ACTIONS = {
    "denoise_paired": "dada2-paired",
    "denoise-paired": "dada2-paired",
    "denoise_single": "dada2-single",
    "denoise-single": "dada2-single",
    "denoise_ccs": "dada2-ccs",
    "denoise-ccs": "dada2-ccs",
}


def clean(value):
    if value is None:
        return ""
    value = str(value).strip()
    # Keep QIIME2 literal "none" as provenance information.
    return value.replace("\t", " ").replace("\r", " ").replace("\n", " ")


def extract_action_block(text):
    m = re.search(
        r"(?ms)^action:\s*\n(?P<body>.*?)(?=^[A-Za-z][A-Za-z0-9_-]*:\s*(?:\n|$)|\Z)",
        text,
    )
    return m.group("body") if m else ""


def extract_simple_field(block, key):
    m = re.search(
        rf"(?m)^\s{{4}}{re.escape(key)}:\s*(.*?)\s*$",
        block,
    )
    return clean(m.group(1)) if m else ""


def extract_plugin(block):
    raw = extract_simple_field(block, "plugin")
    if not raw:
        return ""

    # QIIME2 2024.x:
    # plugin: !ref 'environment:plugins:dada2'
    m = re.search(r"environment:plugins:([^'\"]+)", raw)
    if m:
        return clean(m.group(1))

    raw = re.sub(r"^!ref\s*", "", raw).strip("'\" ")
    return clean(raw)


def extract_mapping_list(block, section):
    """
    Parse QIIME2 provenance list mappings, e.g.
      parameters:
      -   front: none
      -   max_ee: 2
    """
    m = re.search(
        rf"(?ms)^\s{{4}}{re.escape(section)}:\s*\n"
        rf"(?P<body>.*?)(?=^\s{{4}}[A-Za-z][A-Za-z0-9_-]*:\s*(?:\n|$)|\Z)",
        block,
    )
    if not m:
        return {}

    out = {}
    body = m.group("body")

    for line in body.splitlines():
        mm = re.match(r"^\s*-\s+([A-Za-z0-9_-]+):\s*(.*?)\s*$", line)
        if mm:
            out[mm.group(1)] = clean(mm.group(2))

    return out


def extract_environment_version(text, package):
    """
    QIIME2 provenance environment section can contain package versions in
    different YAML layouts. Search textually so !ref/!cite custom YAML tags
    do not break parsing.
    """
    patterns = [
        rf"(?m)^\s*{re.escape(package)}:\s*([0-9][^\s#]*)\s*$",
        rf"(?m)^\s*-\s*{re.escape(package)}:\s*([0-9][^\s#]*)\s*$",
        rf"(?ms)^\s*{re.escape(package)}:\s*\n(?:\s+.*\n)*?\s+version:\s*([^\s#]+)",
    ]
    for pattern in patterns:
        m = re.search(pattern, text)
        if m:
            return clean(m.group(1))
    return ""


def extract_execution_uuid(text):
    m = re.search(
        r"(?ms)^execution:\s*\n(?P<body>.*?)(?=^[A-Za-z][A-Za-z0-9_-]*:\s*(?:\n|$)|\Z)",
        text,
    )
    if not m:
        return ""
    body = m.group("body")
    mm = re.search(r"(?m)^\s+uuid:\s*(.*?)\s*$", body)
    return clean(mm.group(1)) if mm else ""


candidates = []

try:
    with zipfile.ZipFile(qza_path, "r") as zf:

        action_paths = sorted(
            name for name in zf.namelist()
            if name.endswith("/action/action.yaml")
            and "/provenance/" in name
        )

        for action_path in action_paths:
            try:
                text = zf.read(action_path).decode("utf-8")
            except Exception:
                continue

            block = extract_action_block(text)
            if not block:
                continue

            plugin = extract_plugin(block)
            action_name = extract_simple_field(block, "action")

            if plugin != "dada2":
                continue

            if action_name not in TARGET_ACTIONS:
                continue

            params = extract_mapping_list(block, "parameters")
            inputs = extract_mapping_list(block, "inputs")

            # Same DADA2 execution may appear once per output artifact.
            # UUID + action + params are used later for de-duplication.
            candidates.append({
                "path": action_path,
                "method": TARGET_ACTIONS[action_name],
                "action_name": action_name,
                "params": params,
                "inputs": inputs,
                "uuid": extract_execution_uuid(text),
                "qiime_version": extract_environment_version(text, "qiime2"),
                "plugin_version": extract_environment_version(text, "q2-dada2"),
                "python_version": extract_environment_version(text, "python"),
            })

except zipfile.BadZipFile:
    print("[ERROR] rep-seqs.qza 不是有效的 QIIME2/ZIP artifact", file=sys.stderr)
    sys.exit(4)


if not candidates:
    sys.exit(1)


# Deduplicate the same DADA2 execution recorded for multiple outputs
# (e.g. table and representative_sequences).
unique = []
seen = set()

for c in candidates:
    params_key = tuple(sorted(c["params"].items()))
    identity = (
        c["uuid"],
        c["action_name"],
        params_key,
    )
    if identity in seen:
        continue
    seen.add(identity)
    unique.append(c)


if len(unique) > 1:
    print(
        "[WARN] QZA provenance 中找到多個不同的 DADA2 denoise execution；"
        "將使用排序後第一筆。",
        file=sys.stderr,
    )
    for c in unique:
        print(
            f"[WARN] {c['action_name']} | uuid={c['uuid']} | {c['path']}",
            file=sys.stderr,
        )


c = unique[0]
p = c["params"]
i = c["inputs"]


def first(mapping, *names):
    for name in names:
        if name in mapping:
            return clean(mapping[name])
    return ""


values = {
    "denoise_provenance_source": "qiime2_artifact",
    "denoise_method": c["method"],
    "denoise_input": first(i, "demultiplexed_seqs", "demultiplexed-seqs"),

    "denoise_trim_left": first(p, "trim_left", "trim-left"),
    "denoise_trunc_len": first(p, "trunc_len", "trunc-len"),

    "denoise_trim_left_f": first(p, "trim_left_f", "trim-left-f"),
    "denoise_trim_left_r": first(p, "trim_left_r", "trim-left-r"),
    "denoise_trunc_len_f": first(p, "trunc_len_f", "trunc-len-f"),
    "denoise_trunc_len_r": first(p, "trunc_len_r", "trunc-len-r"),

    "denoise_front": first(p, "front"),
    "denoise_adapter": first(p, "adapter"),
    "denoise_min_len": first(p, "min_len", "min-len"),
    "denoise_max_len": first(p, "max_len", "max-len"),
    "denoise_max_ee": first(p, "max_ee", "max-ee"),
    "denoise_max_mismatch": first(p, "max_mismatch", "max-mismatch"),
    "denoise_indels": first(p, "indels"),
    "denoise_trunc_q": first(p, "trunc_q", "trunc-q"),

    "denoise_pooling_method": first(p, "pooling_method", "pooling-method"),
    "denoise_chimera_method": first(p, "chimera_method", "chimera-method"),
    "denoise_min_fold_parent_over_abundance": first(
        p,
        "min_fold_parent_over_abundance",
        "min-fold-parent-over-abundance",
    ),
    "denoise_allow_one_off": first(p, "allow_one_off", "allow-one-off"),

    "denoise_threads": first(p, "n_threads", "n-threads"),
    "denoise_n_reads_learn": first(p, "n_reads_learn", "n-reads-learn"),
    "denoise_hashed_feature_ids": first(
        p, "hashed_feature_ids", "hashed-feature-ids"
    ),
    "denoise_retain_all_samples": first(
        p, "retain_all_samples", "retain-all-samples"
    ),

    "denoise_qiime_version": c["qiime_version"],
    "denoise_plugin_version": c["plugin_version"],
    "denoise_python_version": c["python_version"],
    "denoise_action_uuid": c["uuid"],
}


for key, value in values.items():
    print(f"{key}\t{clean(value)}")

PY
    )"

    parser_status=$?

    set -e

    if [ "${parser_status}" -ne 0 ]; then
        return "${parser_status}"
    fi


    while IFS=$'\t' read -r key value; do

        case "${key}" in
            denoise_provenance_source) DENOISE_PROVENANCE_SOURCE="${value}" ;;
            denoise_method) DENOISE_METHOD="${value}" ;;
            denoise_input) DENOISE_INPUT="${value}" ;;

            denoise_trim_left) DENOISE_TRIM_LEFT="${value}" ;;
            denoise_trunc_len) DENOISE_TRUNC_LEN="${value}" ;;

            denoise_trim_left_f) DENOISE_TRIM_LEFT_F="${value}" ;;
            denoise_trim_left_r) DENOISE_TRIM_LEFT_R="${value}" ;;
            denoise_trunc_len_f) DENOISE_TRUNC_LEN_F="${value}" ;;
            denoise_trunc_len_r) DENOISE_TRUNC_LEN_R="${value}" ;;

            denoise_front) DENOISE_FRONT="${value}" ;;
            denoise_adapter) DENOISE_ADAPTER="${value}" ;;
            denoise_min_len) DENOISE_MIN_LEN="${value}" ;;
            denoise_max_len) DENOISE_MAX_LEN="${value}" ;;
            denoise_max_ee) DENOISE_MAX_EE="${value}" ;;
            denoise_max_mismatch) DENOISE_MAX_MISMATCH="${value}" ;;
            denoise_indels) DENOISE_INDELS="${value}" ;;
            denoise_trunc_q) DENOISE_TRUNC_Q="${value}" ;;

            denoise_pooling_method) DENOISE_POOLING_METHOD="${value}" ;;
            denoise_chimera_method) DENOISE_CHIMERA_METHOD="${value}" ;;
            denoise_min_fold_parent_over_abundance)
                DENOISE_MIN_FOLD_PARENT_OVER_ABUNDANCE="${value}"
                ;;
            denoise_allow_one_off) DENOISE_ALLOW_ONE_OFF="${value}" ;;

            denoise_threads) DENOISE_THREADS="${value}" ;;
            denoise_n_reads_learn) DENOISE_N_READS_LEARN="${value}" ;;
            denoise_hashed_feature_ids) DENOISE_HASHED_FEATURE_IDS="${value}" ;;
            denoise_retain_all_samples) DENOISE_RETAIN_ALL_SAMPLES="${value}" ;;

            denoise_qiime_version) DENOISE_QIIME_VERSION="${value}" ;;
            denoise_plugin_version) DENOISE_PLUGIN_VERSION="${value}" ;;
            denoise_python_version) DENOISE_PYTHON_VERSION="${value}" ;;
            denoise_action_uuid) DENOISE_ACTION_UUID="${value}" ;;
        esac

    done <<< "${parser_output}"


    [ "${DENOISE_PROVENANCE_SOURCE}" = "qiime2_artifact" ]
}


infer_denoise_from_status() {

    if [ ! -f "${LATEST_DENOISE_STATUS}" ]; then
        return 1
    fi

    DENOISE_PROVENANCE_SOURCE="latest_denoise_status"

    DENOISE_JOB_STATUS="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "status"
    )"

    DENOISE_JOB_NAME="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "job_name"
    )"

    DENOISE_JOB_ID="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "job_id"
    )"

    DENOISE_JOB_START="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "start_time"
    )"

    DENOISE_JOB_END="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "end_time"
    )"

    DENOISE_CMD="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "cmd_full"
    )"


    if [[ "${DENOISE_CMD}" == *"dada2 denoise-paired"* ]]; then

        DENOISE_METHOD="dada2-paired"

        DENOISE_INPUT="$(extract_cmd_argument "${DENOISE_CMD}" "--i-demultiplexed-seqs")"

        DENOISE_TRIM_LEFT_F="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trim-left-f")"
        DENOISE_TRIM_LEFT_R="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trim-left-r")"

        DENOISE_TRUNC_LEN_F="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trunc-len-f")"
        DENOISE_TRUNC_LEN_R="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trunc-len-r")"

        DENOISE_THREADS="$(extract_cmd_argument "${DENOISE_CMD}" "--p-n-threads")"


    elif [[ "${DENOISE_CMD}" == *"dada2 denoise-ccs"* ]]; then

        DENOISE_METHOD="dada2-ccs"

        DENOISE_INPUT="$(extract_cmd_argument "${DENOISE_CMD}" "--i-demultiplexed-seqs")"

        DENOISE_FRONT="$(extract_cmd_argument "${DENOISE_CMD}" "--p-front")"
        DENOISE_ADAPTER="$(extract_cmd_argument "${DENOISE_CMD}" "--p-adapter")"

        DENOISE_TRIM_LEFT="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trim-left")"
        DENOISE_TRUNC_LEN="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trunc-len")"

        DENOISE_MIN_LEN="$(extract_cmd_argument "${DENOISE_CMD}" "--p-min-len")"
        DENOISE_MAX_LEN="$(extract_cmd_argument "${DENOISE_CMD}" "--p-max-len")"
        DENOISE_MAX_EE="$(extract_cmd_argument "${DENOISE_CMD}" "--p-max-ee")"
        DENOISE_MAX_MISMATCH="$(extract_cmd_argument "${DENOISE_CMD}" "--p-max-mismatch")"

        DENOISE_POOLING_METHOD="$(extract_cmd_argument "${DENOISE_CMD}" "--p-pooling-method")"
        DENOISE_CHIMERA_METHOD="$(extract_cmd_argument "${DENOISE_CMD}" "--p-chimera-method")"

        DENOISE_THREADS="$(extract_cmd_argument "${DENOISE_CMD}" "--p-n-threads")"


    elif [[ "${DENOISE_CMD}" == *"dada2 denoise-single"* ]]; then

        DENOISE_METHOD="dada2-single"

        DENOISE_INPUT="$(extract_cmd_argument "${DENOISE_CMD}" "--i-demultiplexed-seqs")"

        DENOISE_TRIM_LEFT="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trim-left")"
        DENOISE_TRUNC_LEN="$(extract_cmd_argument "${DENOISE_CMD}" "--p-trunc-len")"

        DENOISE_THREADS="$(extract_cmd_argument "${DENOISE_CMD}" "--p-n-threads")"


    else

        echo "[WARN] 無法辨識 latest_denoise.status 中的 denoise command"
        return 1

    fi


    return 0
}


fill_denoise_job_metadata_from_status() {

    if [ ! -f "${LATEST_DENOISE_STATUS}" ]; then
        return 0
    fi

    # QZA 是參數 provenance 的 primary source。
    # 若 status 同時存在，只補 job-level metadata，不覆蓋 QZA 的 DADA2 參數。
    DENOISE_JOB_STATUS="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "status"
    )"

    DENOISE_JOB_NAME="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "job_name"
    )"

    DENOISE_JOB_ID="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "job_id"
    )"

    DENOISE_JOB_START="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "start_time"
    )"

    DENOISE_JOB_END="$(
        read_kv_value \
            "${LATEST_DENOISE_STATUS}" \
            "end_time"
    )"
}


infer_denoise_provenance() {

    reset_denoise_provenance


    # ========================================================
    # Priority 1：QIIME2 artifact provenance
    # ========================================================

    if infer_denoise_from_qza "${REPSEQS_QZA}"; then

        echo "[INFO] denoise provenance source = QIIME2 artifact"

        fill_denoise_job_metadata_from_status

        return
    fi


    echo "[WARN] rep-seqs.qza provenance 找不到可辨識的 DADA2 denoise action"


    # ========================================================
    # Priority 2：latest_denoise.status fallback
    # ========================================================

    if infer_denoise_from_status; then

        echo "[INFO] denoise provenance source = latest_denoise.status"

        return
    fi


    echo "[WARN] 找不到可用的 denoise provenance"
    echo "[WARN] QZA provenance 與 latest_denoise.status 均無法取得 DADA2 設定"
}

# ============================================================
# Classifier manifest lookup
# ============================================================

lookup_classifier_manifest() {

    local classifier_path="$1"
    local classifier_file
    local lookup_status

    classifier_file="$(basename "${classifier_path}")"


    if [ ! -f "${CLASSIFIER_MANIFEST}" ]; then

        echo "[WARN] 找不到 classifier manifest：${CLASSIFIER_MANIFEST}"
        echo "[WARN] classifier path / filename / SHA256 仍會保留"
        echo "[WARN] reference DB Metadata 將不完整"

        return 1
    fi


    set +e

    while IFS=$'\t' read -r manifest_key manifest_value; do

        case "${manifest_key}" in
            db_key) DB_KEY="${manifest_value}" ;;
            db_family) DB_FAMILY="${manifest_value}" ;;
            db_version) DB_VERSION="${manifest_value}" ;;
            region) REGION="${manifest_value}" ;;

            reference_set) REFERENCE_SET="${manifest_value}" ;;
            reference_variant) REFERENCE_VARIANT="${manifest_value}" ;;
            reference_source) REFERENCE_SOURCE="${manifest_value}" ;;
            reference_url) REFERENCE_URL="${manifest_value}" ;;
            taxonomy_depth) TAXONOMY_DEPTH="${manifest_value}" ;;

            qiime_release) QIIME_RELEASE="${manifest_value}" ;;
            qiime_version) QIIME_VERSION="${manifest_value}" ;;
            qiime_env_name) QIIME_ENV="${manifest_value}" ;;

            sklearn_version) CLASSIFIER_SKLEARN_VERSION="${manifest_value}" ;;
            training_type) TRAINING_TYPE="${manifest_value}" ;;
            status) CLASSIFIER_STATUS="${manifest_value}" ;;
        esac

    done < <(
        python - \
            "${CLASSIFIER_MANIFEST}" \
            "${classifier_path}" \
            "${classifier_file}" \
            "${CONDA_DEFAULT_ENV:-}" <<'PY'
import csv
import sys

manifest_path = sys.argv[1]
classifier_path = sys.argv[2]
classifier_file = sys.argv[3]
current_env = sys.argv[4]

with open(
    manifest_path,
    "r",
    encoding="utf-8-sig",
    newline="",
) as fh:

    reader = csv.DictReader(
        fh,
        delimiter="\t",
    )

    rows = []

    for row in reader:

        cleaned = {
            (key or "").strip(): (value or "").strip()
            for key, value in row.items()
        }

        rows.append(cleaned)


match = None


# ------------------------------------------------------------
# Priority 1: classifier_path exact match
# ------------------------------------------------------------

for row in rows:

    if row.get("classifier_path") == classifier_path:
        match = row
        break


# ------------------------------------------------------------
# Priority 2: classifier_file + current env
# ------------------------------------------------------------

if match is None:

    candidates = [
        row
        for row in rows
        if (
            row.get("classifier_file") == classifier_file
            and row.get("qiime_env_name") == current_env
        )
    ]


    if len(candidates) == 1:

        match = candidates[0]


    elif len(candidates) > 1:

        print(
            "[ERROR] classifier manifest 找到多筆 fallback matches",
            file=sys.stderr,
        )

        for row in candidates:

            print(
                "[ERROR] "
                f"{row.get('classifier_file')} | "
                f"{row.get('classifier_path')}",
                file=sys.stderr,
            )

        sys.exit(2)


if match is None:
    sys.exit(1)


keys = [
    "db_key",
    "db_family",
    "db_version",
    "region",

    "reference_set",
    "reference_variant",
    "reference_source",
    "reference_url",
    "taxonomy_depth",

    "qiime_release",
    "qiime_version",
    "qiime_env_name",

    "sklearn_version",
    "training_type",
    "status",
]


for key in keys:
    value = match.get(key, "")
    value = value.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    print(f"{key}\t{value}")

PY
    )

    lookup_status="${PIPESTATUS[0]:-0}"

    set -e


    # process substitution 的 Python exit status 無法直接由 while 取得，
    # 因此再用一個輕量 check 確認至少有 db_key。
    if [ -z "${DB_KEY:-}" ]; then
        return 1
    fi


    return 0
}


# ============================================================
# Taxonomy provenance
# ============================================================

infer_taxonomy_provenance() {

    TAXONOMY_JOB_STATUS="unknown"
    TAXONOMY_JOB_NAME=""
    TAXONOMY_JOB_ID=""
    TAXONOMY_JOB_START=""
    TAXONOMY_JOB_END=""

    TAXONOMY_METHOD="unknown"
    TAXONOMY_CMD=""

    CLASSIFIER_PATH=""
    CLASSIFIER_FILE=""
    CLASSIFIER_SHA256=""

    REFERENCE_READS=""
    REFERENCE_TAXONOMY=""

    DB_KEY=""
    DB_FAMILY=""
    DB_VERSION=""
    REGION=""

    REFERENCE_SET=""
    REFERENCE_VARIANT=""
    REFERENCE_SOURCE=""
    REFERENCE_URL=""
    TAXONOMY_DEPTH=""

    QIIME_RELEASE=""
    QIIME_VERSION=""
    QIIME_ENV=""

    CLASSIFIER_SKLEARN_VERSION=""
    RUNTIME_SKLEARN_VERSION="$(get_runtime_sklearn_version)"
    RUNTIME_PYTHON_VERSION="$(get_runtime_python_version)"

    TRAINING_TYPE=""
    CLASSIFIER_STATUS=""


    if [ ! -f "${LATEST_TAXONOMY_STATUS}" ]; then

        echo "[WARN] 找不到 ${LATEST_TAXONOMY_STATUS}"
        echo "[WARN] taxonomy provenance 將不完整"

        return
    fi


    TAXONOMY_JOB_STATUS="$(read_kv_value "${LATEST_TAXONOMY_STATUS}" "status")"
    TAXONOMY_JOB_NAME="$(read_kv_value "${LATEST_TAXONOMY_STATUS}" "job_name")"
    TAXONOMY_JOB_ID="$(read_kv_value "${LATEST_TAXONOMY_STATUS}" "job_id")"
    TAXONOMY_JOB_START="$(read_kv_value "${LATEST_TAXONOMY_STATUS}" "start_time")"
    TAXONOMY_JOB_END="$(read_kv_value "${LATEST_TAXONOMY_STATUS}" "end_time")"

    TAXONOMY_CMD="$(read_kv_value "${LATEST_TAXONOMY_STATUS}" "cmd_full")"


    # ========================================================
    # classify-sklearn
    # ========================================================

    if [[ "${TAXONOMY_CMD}" == *"classify-sklearn"* ]]; then

        TAXONOMY_METHOD="classify-sklearn"

        CLASSIFIER_PATH="$(
            extract_cmd_argument \
                "${TAXONOMY_CMD}" \
                "--i-classifier"
        )"


        if [ -n "${CLASSIFIER_PATH}" ]; then

            CLASSIFIER_FILE="$(basename "${CLASSIFIER_PATH}")"

            CLASSIFIER_SHA256="$(
                sha256_file "${CLASSIFIER_PATH}"
            )"


            if lookup_classifier_manifest "${CLASSIFIER_PATH}"; then

                echo "[INFO] classifier manifest match = found"

            else

                echo "[WARN] classifier manifest 找不到對應 model："
                echo "[WARN] ${CLASSIFIER_PATH}"

            fi
        fi


        if \
            [ -n "${CLASSIFIER_SKLEARN_VERSION}" ] && \
            [ "${CLASSIFIER_SKLEARN_VERSION}" != "unavailable" ] && \
            [ -n "${RUNTIME_SKLEARN_VERSION}" ] && \
            [ "${RUNTIME_SKLEARN_VERSION}" != "unavailable" ] && \
            [ "${CLASSIFIER_SKLEARN_VERSION}" != "${RUNTIME_SKLEARN_VERSION}" ]
        then
            echo "[WARN] classifier 訓練時 sklearn=${CLASSIFIER_SKLEARN_VERSION}"
            echo "[WARN] export 當下 sklearn=${RUNTIME_SKLEARN_VERSION}"
            echo "[WARN] 版本不同，已保留兩者於 provenance；請確認實際 taxonomy 執行環境。"
        fi


    # ========================================================
    # classify-consensus-vsearch
    # ========================================================

    elif [[ "${TAXONOMY_CMD}" == *"classify-consensus-vsearch"* ]]; then

        TAXONOMY_METHOD="classify-consensus-vsearch"

        REFERENCE_READS="$(
            extract_cmd_argument \
                "${TAXONOMY_CMD}" \
                "--i-reference-reads"
        )"

        REFERENCE_TAXONOMY="$(
            extract_cmd_argument \
                "${TAXONOMY_CMD}" \
                "--i-reference-taxonomy"
        )"


    else

        echo "[WARN] 無法辨識 taxonomy command 類型"

    fi
}


# ============================================================
# taxonomy_source.txt
# ============================================================

write_taxonomy_source() {

    cat > "${PHYLOSEQ_TAXONOMY_SOURCE}" <<EOF
taxonomy_mode=${TAXONOMY_MODE}
taxonomy_source_type=${TAXONOMY_SOURCE_TYPE}
taxonomy_source_file=${TAXONOMY_SOURCE_FILE}

taxonomy_method=${TAXONOMY_METHOD}

taxonomy_job_status=${TAXONOMY_JOB_STATUS}
taxonomy_job_name=${TAXONOMY_JOB_NAME}
taxonomy_job_id=${TAXONOMY_JOB_ID}
taxonomy_job_start=${TAXONOMY_JOB_START}
taxonomy_job_end=${TAXONOMY_JOB_END}
EOF


    if [ "${TAXONOMY_METHOD}" = "classify-sklearn" ]; then

        cat >> "${PHYLOSEQ_TAXONOMY_SOURCE}" <<EOF

reference_db=${DB_FAMILY}
reference_db_key=${DB_KEY}
reference_db_version=${DB_VERSION}

reference_set=${REFERENCE_SET}
reference_variant=${REFERENCE_VARIANT}
reference_source=${REFERENCE_SOURCE}
reference_url=${REFERENCE_URL}
reference_taxonomy_depth=${TAXONOMY_DEPTH}

# backward-compatible alias
reference_db_variant=${REFERENCE_VARIANT}

classifier_region=${REGION}
classifier_file=${CLASSIFIER_FILE}
classifier_path=${CLASSIFIER_PATH}
classifier_sha256=${CLASSIFIER_SHA256}
classifier_training_type=${TRAINING_TYPE}
classifier_status=${CLASSIFIER_STATUS}

qiime_release=${QIIME_RELEASE}
qiime_version=${QIIME_VERSION}
qiime_env_name=${QIIME_ENV}

classifier_sklearn_version=${CLASSIFIER_SKLEARN_VERSION}
runtime_sklearn_version=${RUNTIME_SKLEARN_VERSION}
runtime_python_version=${RUNTIME_PYTHON_VERSION}

# backward-compatible alias: training-time sklearn from manifest
sklearn_version=${CLASSIFIER_SKLEARN_VERSION}
EOF


    elif [ "${TAXONOMY_METHOD}" = "classify-consensus-vsearch" ]; then

        cat >> "${PHYLOSEQ_TAXONOMY_SOURCE}" <<EOF

reference_reads=${REFERENCE_READS}
reference_taxonomy=${REFERENCE_TAXONOMY}
EOF

    fi
}


# ============================================================
# analysis_metadata.txt
# ============================================================

write_analysis_metadata() {

    # --------------------------------------------------------
    # General
    # --------------------------------------------------------

    cat > "${ANALYSIS_METADATA}" <<EOF
metadata_version=2

phyloseq_exported_at=$(date --iso-8601=seconds)
phyloseq_export_env=${CONDA_DEFAULT_ENV:-unknown}
EOF


    # ========================================================
    # Denoise
    # ========================================================

    cat >> "${ANALYSIS_METADATA}" <<EOF

denoise_provenance_source=${DENOISE_PROVENANCE_SOURCE}
denoise_method=${DENOISE_METHOD}
denoise_qiime_version=${DENOISE_QIIME_VERSION}
denoise_plugin_version=${DENOISE_PLUGIN_VERSION}
denoise_python_version=${DENOISE_PYTHON_VERSION}
denoise_action_uuid=${DENOISE_ACTION_UUID}
denoise_job_status=${DENOISE_JOB_STATUS}
denoise_job_name=${DENOISE_JOB_NAME}
denoise_job_id=${DENOISE_JOB_ID}
denoise_job_start=${DENOISE_JOB_START}
denoise_job_end=${DENOISE_JOB_END}
denoise_input=${DENOISE_INPUT}
EOF


    # --------------------------------------------------------
    # DADA2 paired
    # --------------------------------------------------------

    if [ "${DENOISE_METHOD}" = "dada2-paired" ]; then

        cat >> "${ANALYSIS_METADATA}" <<EOF

denoise_trim_left_f=${DENOISE_TRIM_LEFT_F}
denoise_trim_left_r=${DENOISE_TRIM_LEFT_R}
denoise_trunc_len_f=${DENOISE_TRUNC_LEN_F}
denoise_trunc_len_r=${DENOISE_TRUNC_LEN_R}
denoise_threads=${DENOISE_THREADS}
EOF


    # --------------------------------------------------------
    # DADA2 PacBio CCS
    # --------------------------------------------------------

    elif [ "${DENOISE_METHOD}" = "dada2-ccs" ]; then

        cat >> "${ANALYSIS_METADATA}" <<EOF

denoise_front=${DENOISE_FRONT}
denoise_adapter=${DENOISE_ADAPTER}
denoise_trim_left=${DENOISE_TRIM_LEFT}
denoise_trunc_len=${DENOISE_TRUNC_LEN}
denoise_min_len=${DENOISE_MIN_LEN}
denoise_max_len=${DENOISE_MAX_LEN}
denoise_max_ee=${DENOISE_MAX_EE}
denoise_max_mismatch=${DENOISE_MAX_MISMATCH}
denoise_indels=${DENOISE_INDELS}
denoise_trunc_q=${DENOISE_TRUNC_Q}
denoise_pooling_method=${DENOISE_POOLING_METHOD}
denoise_chimera_method=${DENOISE_CHIMERA_METHOD}
denoise_min_fold_parent_over_abundance=${DENOISE_MIN_FOLD_PARENT_OVER_ABUNDANCE}
denoise_allow_one_off=${DENOISE_ALLOW_ONE_OFF}
denoise_threads=${DENOISE_THREADS}
denoise_n_reads_learn=${DENOISE_N_READS_LEARN}
denoise_hashed_feature_ids=${DENOISE_HASHED_FEATURE_IDS}
denoise_retain_all_samples=${DENOISE_RETAIN_ALL_SAMPLES}
EOF


    # --------------------------------------------------------
    # DADA2 single
    # --------------------------------------------------------

    elif [ "${DENOISE_METHOD}" = "dada2-single" ]; then

        cat >> "${ANALYSIS_METADATA}" <<EOF

denoise_trim_left=${DENOISE_TRIM_LEFT}
denoise_trunc_len=${DENOISE_TRUNC_LEN}
denoise_threads=${DENOISE_THREADS}
EOF

    fi


    # ========================================================
    # Taxonomy
    # ========================================================

    cat >> "${ANALYSIS_METADATA}" <<EOF

taxonomy_method=${TAXONOMY_METHOD}
taxonomy_job_status=${TAXONOMY_JOB_STATUS}
taxonomy_job_name=${TAXONOMY_JOB_NAME}
taxonomy_job_id=${TAXONOMY_JOB_ID}
taxonomy_job_start=${TAXONOMY_JOB_START}
taxonomy_job_end=${TAXONOMY_JOB_END}
EOF


    if [ "${TAXONOMY_METHOD}" = "classify-sklearn" ]; then

        cat >> "${ANALYSIS_METADATA}" <<EOF

reference_db=${DB_FAMILY}
reference_db_key=${DB_KEY}
reference_db_version=${DB_VERSION}

reference_set=${REFERENCE_SET}
reference_variant=${REFERENCE_VARIANT}
reference_source=${REFERENCE_SOURCE}
reference_url=${REFERENCE_URL}
reference_taxonomy_depth=${TAXONOMY_DEPTH}

# backward-compatible alias
reference_db_variant=${REFERENCE_VARIANT}

classifier_region=${REGION}
classifier_file=${CLASSIFIER_FILE}
classifier_path=${CLASSIFIER_PATH}
classifier_sha256=${CLASSIFIER_SHA256}
classifier_training_type=${TRAINING_TYPE}
classifier_status=${CLASSIFIER_STATUS}

taxonomy_qiime_release=${QIIME_RELEASE}
taxonomy_qiime_version=${QIIME_VERSION}
taxonomy_qiime_env=${QIIME_ENV}

taxonomy_classifier_sklearn_version=${CLASSIFIER_SKLEARN_VERSION}
taxonomy_runtime_sklearn_version=${RUNTIME_SKLEARN_VERSION}
taxonomy_runtime_python_version=${RUNTIME_PYTHON_VERSION}

# backward-compatible alias: training-time sklearn from manifest
taxonomy_sklearn_version=${CLASSIFIER_SKLEARN_VERSION}
EOF


    elif [ "${TAXONOMY_METHOD}" = "classify-consensus-vsearch" ]; then

        cat >> "${ANALYSIS_METADATA}" <<EOF

reference_reads=${REFERENCE_READS}
reference_taxonomy=${REFERENCE_TAXONOMY}
EOF

    fi


    # ========================================================
    # Downstream
    # ========================================================

    cat >> "${ANALYSIS_METADATA}" <<EOF

dehost_performed=false
EOF
}


# ============================================================
# Display provenance
# ============================================================

show_provenance() {

    echo
    echo "============================================================"
    echo " Denoise provenance"
    echo "============================================================"

    echo "[INFO] provenance source         = ${DENOISE_PROVENANCE_SOURCE:-unknown}"
    echo "[INFO] method                    = ${DENOISE_METHOD}"
    echo "[INFO] QIIME version             = ${DENOISE_QIIME_VERSION:-unknown}"
    echo "[INFO] q2-dada2 version          = ${DENOISE_PLUGIN_VERSION:-unknown}"
    echo "[INFO] Python version            = ${DENOISE_PYTHON_VERSION:-unknown}"
    echo "[INFO] action UUID               = ${DENOISE_ACTION_UUID:-unknown}"
    echo "[INFO] denoise job               = ${DENOISE_JOB_NAME:-unknown}"
    echo "[INFO] denoise status            = ${DENOISE_JOB_STATUS}"


    if [ "${DENOISE_METHOD}" = "dada2-paired" ]; then

        echo "[INFO] trim-left F               = ${DENOISE_TRIM_LEFT_F:-unknown}"
        echo "[INFO] trim-left R               = ${DENOISE_TRIM_LEFT_R:-unknown}"
        echo "[INFO] trunc-len F               = ${DENOISE_TRUNC_LEN_F:-unknown}"
        echo "[INFO] trunc-len R               = ${DENOISE_TRUNC_LEN_R:-unknown}"
        echo "[INFO] threads                   = ${DENOISE_THREADS:-unknown}"


    elif [ "${DENOISE_METHOD}" = "dada2-ccs" ]; then

        echo "[INFO] front primer              = ${DENOISE_FRONT:-unknown}"
        echo "[INFO] adapter                   = ${DENOISE_ADAPTER:-unknown}"
        echo "[INFO] min-len                   = ${DENOISE_MIN_LEN:-unknown}"
        echo "[INFO] max-len                   = ${DENOISE_MAX_LEN:-unknown}"
        echo "[INFO] max-ee                    = ${DENOISE_MAX_EE:-unknown}"
        echo "[INFO] max-mismatch              = ${DENOISE_MAX_MISMATCH:-unknown}"
        echo "[INFO] indels                    = ${DENOISE_INDELS:-unknown}"
        echo "[INFO] trunc-q                   = ${DENOISE_TRUNC_Q:-unknown}"
        echo "[INFO] pooling                   = ${DENOISE_POOLING_METHOD:-unknown}"
        echo "[INFO] chimera                   = ${DENOISE_CHIMERA_METHOD:-unknown}"
        echo "[INFO] min-fold-parent           = ${DENOISE_MIN_FOLD_PARENT_OVER_ABUNDANCE:-unknown}"
        echo "[INFO] allow-one-off             = ${DENOISE_ALLOW_ONE_OFF:-unknown}"
        echo "[INFO] threads                   = ${DENOISE_THREADS:-unknown}"
        echo "[INFO] n-reads-learn             = ${DENOISE_N_READS_LEARN:-unknown}"
        echo "[INFO] hashed-feature-ids        = ${DENOISE_HASHED_FEATURE_IDS:-unknown}"
        echo "[INFO] retain-all-samples        = ${DENOISE_RETAIN_ALL_SAMPLES:-unknown}"


    elif [ "${DENOISE_METHOD}" = "dada2-single" ]; then

        echo "[INFO] trim-left                 = ${DENOISE_TRIM_LEFT:-unknown}"
        echo "[INFO] trunc-len                 = ${DENOISE_TRUNC_LEN:-unknown}"
        echo "[INFO] threads                   = ${DENOISE_THREADS:-unknown}"

    fi


    echo
    echo "============================================================"
    echo " Taxonomy provenance"
    echo "============================================================"

    echo "[INFO] method                    = ${TAXONOMY_METHOD}"
    echo "[INFO] taxonomy job              = ${TAXONOMY_JOB_NAME:-unknown}"
    echo "[INFO] taxonomy status           = ${TAXONOMY_JOB_STATUS}"


    if [ "${TAXONOMY_METHOD}" = "classify-sklearn" ]; then

        echo "[INFO] classifier                = ${CLASSIFIER_FILE:-unknown}"
        echo "[INFO] classifier path           = ${CLASSIFIER_PATH:-unknown}"

        echo
        echo "[INFO] classifier manifest       = ${CLASSIFIER_MANIFEST}"

        echo "[INFO] reference DB              = ${DB_FAMILY:-unknown}"
        echo "[INFO] reference DB key          = ${DB_KEY:-unknown}"
        echo "[INFO] DB version                = ${DB_VERSION:-unknown}"

        echo "[INFO] reference set             = ${REFERENCE_SET:-unknown}"
        echo "[INFO] reference variant         = ${REFERENCE_VARIANT:-unknown}"
        echo "[INFO] reference source          = ${REFERENCE_SOURCE:-unknown}"
        echo "[INFO] taxonomy depth            = ${TAXONOMY_DEPTH:-unknown}"

        echo "[INFO] region                    = ${REGION:-unknown}"

        echo "[INFO] classifier QIIME env      = ${QIIME_ENV:-unknown}"
        echo "[INFO] classifier QIIME version  = ${QIIME_VERSION:-unknown}"
        echo "[INFO] classifier sklearn        = ${CLASSIFIER_SKLEARN_VERSION:-unknown}"

        echo "[INFO] runtime env               = ${CONDA_DEFAULT_ENV:-unknown}"
        echo "[INFO] runtime sklearn           = ${RUNTIME_SKLEARN_VERSION:-unknown}"
        echo "[INFO] runtime Python            = ${RUNTIME_PYTHON_VERSION:-unknown}"


    elif [ "${TAXONOMY_METHOD}" = "classify-consensus-vsearch" ]; then

        echo "[INFO] reference reads           = ${REFERENCE_READS:-unknown}"
        echo "[INFO] reference taxonomy        = ${REFERENCE_TAXONOMY:-unknown}"

    fi


    echo "============================================================"
}


# ============================================================
# Main
# ============================================================

main() {

    check_cmd \
        "qiime" \
        "請先啟用 QIIME2 環境，例如：conda activate ${QIIME_ENV_NAME}"

    check_cmd \
        "biom" \
        "請確認目前 QIIME2 環境包含 biom"

    check_cmd \
        "python" \
        "目前環境需要 Python 才能解析 classifier_manifest.tsv"


    check_file "${TABLE_QZA}"
    check_file "${REPSEQS_QZA}"


    prepare_taxonomy_source

    mkdir -p "${OUTDIR}"


    echo
    echo "[INFO] PROJECT_DIR          = ${PROJECT_DIR}"
    echo "[INFO] OUTPUT_DIR           = ${OUTDIR}"
    echo "[INFO] CURRENT_ENV          = ${CONDA_DEFAULT_ENV:-unknown}"
    echo "[INFO] TIMEZONE             = ${TIMEZONE}"
    echo "[INFO] DENOISE_STATUS       = ${LATEST_DENOISE_STATUS}"
    echo "[INFO] TAXONOMY_SOURCE      = ${TAXONOMY_INPUT}"
    echo "[INFO] CLASSIFIER_MANIFEST  = ${CLASSIFIER_MANIFEST}"


    # --------------------------------------------------------
    # Provenance
    # --------------------------------------------------------

    infer_denoise_provenance
    infer_taxonomy_provenance

    show_provenance


    # --------------------------------------------------------
    # Export
    # --------------------------------------------------------

    export_table_and_biom
    export_repseqs
    prepare_taxonomy_tsv


    # --------------------------------------------------------
    # Metadata
    # --------------------------------------------------------

    write_taxonomy_source
    write_analysis_metadata


    echo
    echo "============================================================"
    echo " Export completed"
    echo "============================================================"

    echo "[INFO] biom               = ${OUTDIR}/feature-table.biom"
    echo "[INFO] otu_table.tsv      = ${OUTDIR}/otu_table.tsv"
    echo "[INFO] dna-sequences      = ${OUTDIR}/dna-sequences.fasta"
    echo "[INFO] taxonomy.tsv       = ${OUTDIR}/taxonomy.tsv"

    echo
    echo "[INFO] taxonomy metadata  = ${PHYLOSEQ_TAXONOMY_SOURCE}"
    echo "[INFO] analysis metadata  = ${ANALYSIS_METADATA}"
}


main "$@"
