#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# restore_legacy_project.sh
#
# Purpose:
#   Restore a legacy folder from a NAS archive snapshot
#   into the SSD workspace structure:
#
#     /home/adprc/workspaces/<owner>/<project>
#
#   The NAS snapshot remains unchanged.
#
# Default usage:
#   restore_legacy_project.sh <legacy_folder> <owner_name> <project_name>
#
# Explicit snapshot:
#   restore_legacy_project.sh \
#     --snapshot <snapshot_name> \
#     <legacy_folder> \
#     <owner_name> \
#     <project_name>
# ============================================================

ARCHIVE_ROOT="/home/NAS/archive"
NAS_MOUNT="/home/NAS"
SSD_ROOT="/home/adprc/workspaces"
TEMP_ROOT="${SSD_ROOT}/_incoming_legacy_restore"

DEFAULT_SNAPSHOT="adprc_personal_backup_20260602"
SNAPSHOT="${DEFAULT_SNAPSHOT}"

die() {
    echo "Error: $*" >&2
    exit 1
}

validate_standard_name() {
    local label="$1"
    local value="$2"

    if [[ -z "${value}" ]]; then
        die "${label} must not be empty."
    fi

    if [[ "${value}" == "." || "${value}" == ".." ]]; then
        die "${label} must not be '.' or '..': ${value}"
    fi

    if [[ "${value}" == *"/"* ]]; then
        die "${label} must not contain slash '/': ${value}"
    fi

    if [[ "${value}" == *$'
'* || "${value}" == *$''* || "${value}" == *$'	'* ]]; then
        die "${label} must not contain tabs or line breaks."
    fi

    if [[ "${value}" == " "* || "${value}" == *" " ]]; then
        die "${label} must not begin or end with a space: ${value}"
    fi

    if [[ "${value}" == .* || "${value}" == _* || "${value}" == -* ]]; then
        die "${label} must not begin with '.', '_' or '-': ${value}"
    fi
}

validate_legacy_folder() {
    local value="$1"

    if [[ -z "${value}" ]]; then
        die "LEGACY_FOLDER must not be empty."
    fi

    if [[ "${value}" == "." || "${value}" == ".." || "${value}" == *"/"* ]]; then
        die "LEGACY_FOLDER must be a single folder name without slash:
  ${value}"
    fi
}

show_usage() {
    echo "Usage:"
    echo "  restore_legacy_project.sh <legacy_folder> <owner_name> <project_name>"
    echo
    echo "Or specify another snapshot:"
    echo "  restore_legacy_project.sh --snapshot <snapshot_name> <legacy_folder> <owner_name> <project_name>"
    echo
    echo "Examples:"
    echo "  restore_legacy_project.sh Adprc_QC Andy qc_reanalysis_202606"
    echo
    echo "  restore_legacy_project.sh \\"
    echo "    --snapshot adprc_before_migration_20260801 \\"
    echo "    Adprc_QC \\"
    echo "    Andy \\"
    echo "    qc_reanalysis_202608"
}

if [[ "${1:-}" == "--snapshot" || "${1:-}" == "-s" ]]; then
    if [[ "$#" -ne 5 ]]; then
        show_usage
        exit 1
    fi

    SNAPSHOT="$2"
    shift 2
elif [[ "$#" -ne 3 ]]; then
    show_usage
    exit 1
fi

LEGACY_FOLDER="$1"
OWNER="$2"
PROJECT="$3"

validate_standard_name "SNAPSHOT" "${SNAPSHOT}"
validate_legacy_folder "${LEGACY_FOLDER}"
validate_standard_name "OWNER" "${OWNER}"
validate_standard_name "PROJECT" "${PROJECT}"

if ! mountpoint -q "${NAS_MOUNT}"; then
    die "NAS is not mounted:
  ${NAS_MOUNT}"
fi

SNAPSHOT_ROOT="${ARCHIVE_ROOT}/${SNAPSHOT}"
SOURCE="${SNAPSHOT_ROOT}/${LEGACY_FOLDER}"

TARGET_OWNER_DIR="${SSD_ROOT}/${OWNER}"
TARGET="${TARGET_OWNER_DIR}/${PROJECT}"

TEMP_OWNER_DIR="${TEMP_ROOT}/${OWNER}"
TEMP_TARGET="${TEMP_OWNER_DIR}/${PROJECT}"

if [[ ! -d "${SNAPSHOT_ROOT}" ]]; then
    die "Snapshot folder does not exist:
  ${SNAPSHOT_ROOT}

Available snapshots:
$(find "${ARCHIVE_ROOT}" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf '  %f\n' \
    | sort)"
fi

if [[ ! -d "${SOURCE}" ]]; then
    die "Legacy folder was not found in snapshot:
  ${SOURCE}

Available folders in snapshot:
$(find "${SNAPSHOT_ROOT}" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf '  %f\n' \
    | sort)"
fi

if [[ -e "${TARGET}" ]]; then
    die "Target SSD workspace already exists:
  ${TARGET}

Please inspect the existing workspace before continuing."
fi

mkdir -p "${TARGET_OWNER_DIR}"
mkdir -p "${TEMP_OWNER_DIR}"

echo "Restoring legacy project to SSD workspace..."
echo
echo "Snapshot:"
echo "  ${SNAPSHOT_ROOT}"
echo
echo "Legacy source:"
echo "  ${SOURCE}"
echo
echo "Temporary SSD target:"
echo "  ${TEMP_TARGET}"
echo
echo "Final SSD workspace:"
echo "  ${TARGET}"
echo

if [[ -d "${TEMP_TARGET}" ]]; then
    echo "Existing temporary restore directory detected."
    echo "The previous transfer may have been interrupted."
    echo "Resuming transfer..."
    echo
else
    mkdir -p "${TEMP_TARGET}"
fi

rsync -rltHh \
    --info=progress2 \
    --partial-dir='.rsync-partial' \
    "${SOURCE}/" \
    "${TEMP_TARGET}/"

echo
echo "Verifying restored workspace..."

changes="$(
    rsync -rltHhn \
        --delete \
        --itemize-changes \
        --exclude='.rsync-partial/' \
        "${SOURCE}/" \
        "${TEMP_TARGET}/"
)"

if [[ -n "${changes}" ]]; then
    echo "${changes}"
    die "Verification failed.
The NAS snapshot remains unchanged.
The temporary SSD folder was preserved for review:
  ${TEMP_TARGET}"
fi

source_files=$(find "${SOURCE}" -type f | wc -l)
target_files=$(find "${TEMP_TARGET}" -type f ! -path '*/.rsync-partial/*' | wc -l)

source_bytes=$(
    find "${SOURCE}" -type f -printf '%s\n' \
        | awk '{ total += $1 } END { print total + 0 }'
)

target_bytes=$(
    find "${TEMP_TARGET}" -type f ! -path '*/.rsync-partial/*' -printf '%s\n' \
        | awk '{ total += $1 } END { print total + 0 }'
)

if [[ "${source_files}" -ne "${target_files}" ]]; then
    die "Verification failed: file counts differ.
Source files: ${source_files}
Target files: ${target_files}

The NAS snapshot remains unchanged."
fi

if [[ "${source_bytes}" -ne "${target_bytes}" ]]; then
    die "Verification failed: total file sizes differ.
Source bytes: ${source_bytes}
Target bytes: ${target_bytes}

The NAS snapshot remains unchanged."
fi

rm -rf -- "${TEMP_TARGET}/.rsync-partial"

if [[ -e "${TARGET}" ]]; then
    die "Final SSD workspace unexpectedly exists:
  ${TARGET}"
fi

mv "${TEMP_TARGET}" "${TARGET}"

rmdir --ignore-fail-on-non-empty "${TEMP_OWNER_DIR}" 2>/dev/null || true
rmdir --ignore-fail-on-non-empty "${TEMP_ROOT}" 2>/dev/null || true

echo
echo "Legacy project restored successfully."
echo "The NAS snapshot remains unchanged."
echo
echo "Files:"
echo "  ${source_files}"
echo
echo "Bytes:"
echo "  ${source_bytes}"
echo
echo "SSD workspace:"
echo "  ${TARGET}"
