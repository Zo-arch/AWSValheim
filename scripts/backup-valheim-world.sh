#!/usr/bin/env bash
set -euo pipefail

BACKUP_BUCKET_NAME="${BACKUP_BUCKET_NAME:?BACKUP_BUCKET_NAME is required}"
BACKUP_PREFIX="${BACKUP_PREFIX:-backups/worlds}"
VALHEIM_DATA_DIR="${VALHEIM_DATA_DIR:-/srv/valheim}"
VALHEIM_ENV_FILE="${VALHEIM_ENV_FILE:-/etc/valheim/valheim.env}"
VALHEIM_WORLDS_DIR="${VALHEIM_WORLDS_DIR:-${VALHEIM_DATA_DIR}/worlds_local}"
VALHEIM_BACKUP_TMP_DIR="${VALHEIM_BACKUP_TMP_DIR:-/tmp/valheim-backups}"

if [[ ! -f "${VALHEIM_ENV_FILE}" ]]; then
  echo "Valheim env file not found: ${VALHEIM_ENV_FILE}" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is not installed." >&2
  exit 1
fi

source "${VALHEIM_ENV_FILE}"

WORLD_NAME="${WORLD_NAME:-}"
if [[ -z "${WORLD_NAME}" ]]; then
  echo "WORLD_NAME is not set in ${VALHEIM_ENV_FILE}" >&2
  exit 1
fi

WORLD_DB="${VALHEIM_WORLDS_DIR}/${WORLD_NAME}.db"
WORLD_FWL="${VALHEIM_WORLDS_DIR}/${WORLD_NAME}.fwl"

if [[ ! -f "${WORLD_DB}" || ! -f "${WORLD_FWL}" ]]; then
  echo "World files not found for ${WORLD_NAME}" >&2
  exit 1
fi

mkdir -p "${VALHEIM_BACKUP_TMP_DIR}"

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="${WORLD_NAME}-world-backup-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${VALHEIM_BACKUP_TMP_DIR}/${ARCHIVE_NAME}"
S3_URI="s3://${BACKUP_BUCKET_NAME}/${BACKUP_PREFIX%/}/${ARCHIVE_NAME}"

tar -czf "${ARCHIVE_PATH}" -C "${VALHEIM_WORLDS_DIR}" "${WORLD_NAME}.db" "${WORLD_NAME}.fwl"
aws s3 cp "${ARCHIVE_PATH}" "${S3_URI}"
rm -f "${ARCHIVE_PATH}"

echo "backup_s3_uri=${S3_URI}"
