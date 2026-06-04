#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="/home/NAS/archive/adprc_personal_backup_20260602"
SSD_ROOT="/home/adprc/workspaces"

LEGACY_FOLDER="${1:-}"
OWNER="${2:-}"
PROJECT="${3:-}"

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
        die "${label} contains invalid characters: ${value}"
    fi
}

validate_name "LEGACY_FOLDER" "${LEGACY_FOLDER}"
validate_name "OWNER" "${OWNER}"
validate_name "PROJECT" "${PROJECT}"

SOURCE="${BACKUP_ROOT}/${LEGACY_FOLDER}"
TARGET_OWNER_DIR="${SSD_ROOT}/${OWNER}"
TARGET="${TARGET_OWNER_DIR}/${PROJECT}"

if [[ ! -d "${SOURCE}" ]]; then
    die "Legacy backup folder does not exist:
  ${SOURCE}"
fi

if [[ -e "${TARGET}" ]]; then
    die "Target workspace already exists:
  ${TARGET}"
fi

mkdir -p "${TARGET_OWNER_DIR}"

echo "Restoring legacy project to SSD workspace..."
echo
echo "Source:"
echo "  ${SOURCE}"
echo
echo "Target:"
echo "  ${TARGET}"
echo

rsync -rltHh \
    --info=progress2 \
    --partial \
    "${SOURCE}/" \
    "${TARGET}/"

echo
echo "Verifying restored workspace..."

changes="$(
    rsync -rltHhn \
        --itemize-changes \
        "${SOURCE}/" \
        "${TARGET}/"
)"

if [[ -n "${changes}" ]]; then
    echo "${changes}"
    die "Verification failed. Legacy source will remain unchanged."
fi

source_files=$(find "${SOURCE}" -type f | wc -l)
target_files=$(find "${TARGET}" -type f | wc -l)

source_bytes=$(du -sb --apparent-size --count-links "${SOURCE}" | cut -f1)
target_bytes=$(du -sb --apparent-size --count-links "${TARGET}" | cut -f1)

if [[ "${source_files}" -ne "${target_files}" ]]; then
    die "Verification failed: file counts differ.
Source files: ${source_files}
Target files: ${target_files}"
fi

if [[ "${source_bytes}" -ne "${target_bytes}" ]]; then
    die "Verification failed: apparent sizes differ.
Source bytes: ${source_bytes}
Target bytes: ${target_bytes}"
fi

echo
echo "Legacy project restored successfully."
echo "The NAS backup remains unchanged."
echo
echo "Workspace:"
echo "  ${TARGET}"
