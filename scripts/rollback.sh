#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/opt/production-cicd-lab"
TARGET_ENVIRONMENT="${1:-}"

case "${TARGET_ENVIRONMENT}" in
  staging)
    PREVIOUS_IMAGE_FILE="${APP_DIR}/.previous-image.staging"
    DEPLOY_SCRIPT="${APP_DIR}/deploy.sh"
    ;;

  production)
    PREVIOUS_IMAGE_FILE="${APP_DIR}/.previous-image.production"
    DEPLOY_SCRIPT="${APP_DIR}/deploy-production.sh"
    ;;

  *)
    echo "Usage: $0 <staging|production>"
    exit 1
    ;;
esac

if [[ ! -f "${PREVIOUS_IMAGE_FILE}" ]]; then
  echo "Error: no previous ${TARGET_ENVIRONMENT} image has been recorded."
  exit 1
fi

PREVIOUS_IMAGE="$(<"${PREVIOUS_IMAGE_FILE}")"

if [[ ! "${PREVIOUS_IMAGE}" =~ ^ghcr\.io/sprobe-dan/production-cicd-lab:[0-9a-f]{40}$ ]]; then
  echo "Error: recorded previous image is invalid."
  exit 1
fi

echo "Rolling back ${TARGET_ENVIRONMENT} to ${PREVIOUS_IMAGE}"

chmod 750 "${DEPLOY_SCRIPT}"

export SKIP_MIGRATIONS=true
exec "${DEPLOY_SCRIPT}" "${PREVIOUS_IMAGE}"