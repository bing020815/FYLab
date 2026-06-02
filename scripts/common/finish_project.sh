#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# finish_project.sh
#
# Purpose:
#   Move one completed or paused SSD workspace project to NAS.
#
# Workflow:
#   SSD workspace
#     -> rsync to NAS _incoming
#     -> verify
#     -> move to official NAS project path
#     -> automatically remove SSD source
#
# Usage:
#   finish_project.sh <owner> <project>
#
# Example:
#   finish_project.sh sj liver_202606
# ============================================================

SSD_ROOT="/home/adprc/workspaces"
NAS_MOUNT="/home/NAS"
NAS_ROOT="${NAS_MOUNT}/projects"
INCOMING_ROOT="${NAS_ROOT}/_incoming"
LOG_DIR="${NAS_ROOT}/_logs"
REGISTRY_DIR="${NAS_ROOT}/_registry"
REGISTRY_FILE="${REGISTRY_DIR}/project_registry.tsv"

OWNER="${1:-}"
PROJECT="${2:-}"

die() {
    echo "Error: $*" >&2
    exit 1
}

validate_name() {
    local label="$1"
    local value="$2"

    if [[ -z "${value}" ]]; then
        die "${label} must not be empty."
    fi

    if [[ ! "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        die "${label} contains invalid characters: ${value}
Allowed characters: letters, numbers, dot, underscore, and hyphen.
The first character must be a letter or number."
    fi
}

check_nas() {
    if ! mountpoint -q "${NAS_MOUNT}"; then
        die "NAS is not mounted at ${NAS_MOUNT}."
    fi

    mkdir -p "${NAS_ROOT}"

    local test_file="${NAS_ROOT}/.write_test_finish_project.$$"

    if ! touch "${test_file}" 2>/dev/null; then
        die "NAS is mounted but not writable: ${NAS_ROOT}"
    fi

    rm -f "${test_file}"
}

verify_copy() {
    local source_dir="$1"
    local target_dir="$2"

    echo
    echo "Verifying copied project..."

    local changes
    changes="$(
        rsync -rltHhn \
            --delete \
            --itemize-changes \
            --exclude='.rsync-partial/' \
            "${source_dir}/" \
            "${target_dir}/"
    )"

    if [[ -n "${changes}" ]]; then
        echo "${changes}"
        die "Verification failed: source and target are not synchronized."
    fi

    local source_files
    local target_files
    local source_bytes
    local target_bytes

    source_files=$(find "${source_dir}" -type f | wc -l)
    target_files=$(find "${target_dir}" -type f | wc -l)

    source_bytes=$(
        find "${source_dir}" -type f -printf '%s\n' \
            | awk '{ total += $1 } END { print total + 0 }'
    )

    target_bytes=$(
        find "${target_dir}" -type f -printf '%s\n' \
            | awk '{ total += $1 } END { print total + 0 }'
    )

    if [[ "${source_files}" -ne "${target_files}" ]]; then
        die "Verification failed: file counts differ.
Source files: ${source_files}
Target files: ${target_files}"
    fi

    if [[ "${source_bytes}" -ne "${target_bytes}" ]]; then
        die "Verification failed: total file sizes differ.
Source bytes: ${source_bytes}
Target bytes: ${target_bytes}"
    fi

    echo "Verification passed."
    echo "  Files: ${source_files}"
    echo "  Bytes: ${source_bytes}"
}

append_registry() {
    local action="$1"
    local source_path="$2"
    local target_path="$3"

    mkdir -p "${REGISTRY_DIR}"

    if [[ ! -f "${REGISTRY_FILE}" ]]; then
        printf "timestamp\towner\tproject\taction\tsource\ttarget\n" \
            > "${REGISTRY_FILE}"
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(date '+%F %T')" \
        "${OWNER}" \
        "${PROJECT}" \
        "${action}" \
        "${source_path}" \
        "${target_path}" \
        >> "${REGISTRY_FILE}"
}

validate_name "OWNER" "${OWNER}"
validate_name "PROJECT" "${PROJECT}"
check_nas

SSD_OWNER_DIR="${SSD_ROOT}/${OWNER}"
NAS_OWNER_DIR="${NAS_ROOT}/${OWNER}"
INCOMING_OWNER_DIR="${INCOMING_ROOT}/${OWNER}"

SSD_PROJECT="${SSD_OWNER_DIR}/${PROJECT}"
NAS_PROJECT="${NAS_OWNER_DIR}/${PROJECT}"
INCOMING_PROJECT="${INCOMING_OWNER_DIR}/${PROJECT}"

mkdir -p "${NAS_OWNER_DIR}"
mkdir -p "${INCOMING_OWNER_DIR}"
mkdir -p "${LOG_DIR}"

SSD_EXISTS=false
NAS_EXISTS=false

[[ -d "${SSD_PROJECT}" ]] && SSD_EXISTS=true
[[ -d "${NAS_PROJECT}" ]] && NAS_EXISTS=true

# ------------------------------------------------------------
# Case 1: Project exists in both SSD and NAS
# ------------------------------------------------------------
if [[ "${SSD_EXISTS}" == true && "${NAS_EXISTS}" == true ]]; then
    die "Project exists in both SSD and NAS.
Manual review is required.

SSD:
  ${SSD_PROJECT}

NAS:
  ${NAS_PROJECT}"
fi

# ------------------------------------------------------------
# Case 2: Project is already archived
# ------------------------------------------------------------
if [[ "${SSD_EXISTS}" == false && "${NAS_EXISTS}" == true ]]; then
    echo "Project is already archived in NAS:"
    echo "  ${NAS_PROJECT}"
    exit 0
fi

# ------------------------------------------------------------
# Case 3: Project does not exist
# ------------------------------------------------------------
if [[ "${SSD_EXISTS}" == false && "${NAS_EXISTS}" == false ]]; then
    die "Project was not found in SSD workspace or NAS archive.

SSD:
  ${SSD_PROJECT}

NAS:
  ${NAS_PROJECT}"
fi

# ------------------------------------------------------------
# Case 4: Archive SSD project to NAS
# ------------------------------------------------------------
echo "Archiving SSD workspace project to NAS..."
echo
echo "Source:"
echo "  ${SSD_PROJECT}"
echo
echo "Temporary NAS target:"
echo "  ${INCOMING_PROJECT}"
echo
echo "Final NAS target:"
echo "  ${NAS_PROJECT}"
echo

if [[ -d "${INCOMING_PROJECT}" ]]; then
    echo "Existing temporary NAS directory detected."
    echo "The previous transfer may have been interrupted."
    echo "Resuming transfer:"
    echo "  ${INCOMING_PROJECT}"
else
    mkdir -p "${INCOMING_PROJECT}"
fi

LOG_FILE="${LOG_DIR}/finish_${OWNER}_${PROJECT}_$(date '+%Y%m%d_%H%M%S').log"

rsync -rltHh \
    --info=progress2 \
    --partial-dir='.rsync-partial' \
    --log-file="${LOG_FILE}" \
    "${SSD_PROJECT}/" \
    "${INCOMING_PROJECT}/"

verify_copy "${SSD_PROJECT}" "${INCOMING_PROJECT}"

if [[ -e "${NAS_PROJECT}" ]]; then
    die "Final NAS project unexpectedly exists:
  ${NAS_PROJECT}"
fi

mv "${INCOMING_PROJECT}" "${NAS_PROJECT}"

echo
echo "Removing SSD source after successful verification..."
rm -rf -- "${SSD_PROJECT}"

rmdir --ignore-fail-on-non-empty "${SSD_OWNER_DIR}" 2>/dev/null || true
rmdir --ignore-fail-on-non-empty "${INCOMING_OWNER_DIR}" 2>/dev/null || true

append_registry \
    "archived_ssd_to_nas" \
    "${SSD_PROJECT}" \
    "${NAS_PROJECT}"

echo
echo "Project archived successfully."
echo "SSD source has been removed."
echo
echo "Archived NAS project:"
echo "  ${NAS_PROJECT}"
