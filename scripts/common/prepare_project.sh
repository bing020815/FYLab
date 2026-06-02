#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# prepare_project.sh
#
# Purpose:
#   1. If the project exists only in NAS:
#        Move NAS project back to SSD workspace safely.
#   2. If the project does not exist in NAS or SSD:
#        Create a new SSD workspace.
#   3. If the project already exists only in SSD:
#        Print the existing workspace path.
#
# Usage:
#   prepare_project.sh <owner> <project>
#
# Example:
#   prepare_project.sh sj liver_202606
# ============================================================

SSD_ROOT="/home/adprc/workspaces"
NAS_MOUNT="/home/NAS"
NAS_ROOT="${NAS_MOUNT}/projects"
RESTORE_ROOT="${SSD_ROOT}/_incoming_restore"
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

    local test_file="${NAS_ROOT}/.write_test_prepare_project.$$"

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

SSD_PROJECT="${SSD_OWNER_DIR}/${PROJECT}"
NAS_PROJECT="${NAS_OWNER_DIR}/${PROJECT}"

RESTORE_OWNER_DIR="${RESTORE_ROOT}/${OWNER}"
RESTORE_PROJECT="${RESTORE_OWNER_DIR}/${PROJECT}"

mkdir -p "${SSD_OWNER_DIR}"
mkdir -p "${NAS_OWNER_DIR}"
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
# Case 2: Project already active in SSD
# ------------------------------------------------------------
if [[ "${SSD_EXISTS}" == true && "${NAS_EXISTS}" == false ]]; then
    echo "Project is already active in SSD workspace:"
    echo "  ${SSD_PROJECT}"
    echo
    echo "Continue working with:"
    echo "  cd \"${SSD_PROJECT}\""
    exit 0
fi

# ------------------------------------------------------------
# Case 3: New project
# ------------------------------------------------------------
if [[ "${SSD_EXISTS}" == false && "${NAS_EXISTS}" == false ]]; then
    mkdir -p "${SSD_PROJECT}"

    append_registry \
        "created_new_workspace" \
        "-" \
        "${SSD_PROJECT}"

    echo "New project workspace created:"
    echo "  ${SSD_PROJECT}"
    echo
    echo "Continue working with:"
    echo "  cd \"${SSD_PROJECT}\""
    exit 0
fi

# ------------------------------------------------------------
# Case 4: Restore archived project from NAS to SSD
# ------------------------------------------------------------
echo "Archived project found in NAS."
echo "Restoring project to SSD workspace..."
echo
echo "Source:"
echo "  ${NAS_PROJECT}"
echo
echo "Temporary target:"
echo "  ${RESTORE_PROJECT}"
echo
echo "Final SSD workspace:"
echo "  ${SSD_PROJECT}"
echo

mkdir -p "${RESTORE_OWNER_DIR}"

if [[ -d "${RESTORE_PROJECT}" ]]; then
    echo "Existing temporary restore directory detected."
    echo "The previous transfer may have been interrupted."
    echo "Resuming transfer:"
    echo "  ${RESTORE_PROJECT}"
else
    mkdir -p "${RESTORE_PROJECT}"
fi

LOG_FILE="${LOG_DIR}/prepare_${OWNER}_${PROJECT}_$(date '+%Y%m%d_%H%M%S').log"

rsync -rltHh \
    --info=progress2 \
    --partial-dir='.rsync-partial' \
    --log-file="${LOG_FILE}" \
    "${NAS_PROJECT}/" \
    "${RESTORE_PROJECT}/"

verify_copy "${NAS_PROJECT}" "${RESTORE_PROJECT}"

if [[ -e "${SSD_PROJECT}" ]]; then
    die "Final SSD workspace unexpectedly exists:
  ${SSD_PROJECT}"
fi

mv "${RESTORE_PROJECT}" "${SSD_PROJECT}"

echo
echo "Removing archived NAS source after successful verification..."
rm -rf -- "${NAS_PROJECT}"

rmdir --ignore-fail-on-non-empty "${NAS_OWNER_DIR}" 2>/dev/null || true
rmdir --ignore-fail-on-non-empty "${RESTORE_OWNER_DIR}" 2>/dev/null || true

append_registry \
    "restored_nas_to_ssd" \
    "${NAS_PROJECT}" \
    "${SSD_PROJECT}"

echo
echo "Project restored successfully."
echo "NAS source has been removed."
echo
echo "Active SSD workspace:"
echo "  ${SSD_PROJECT}"
echo
echo "Continue working with:"
echo "  cd \"${SSD_PROJECT}\""
