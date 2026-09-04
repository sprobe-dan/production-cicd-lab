#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/opt/production-cicd-lab"
COMPOSE_FILE="${APP_DIR}/compose.production.yml"
ENV_FILE="${APP_DIR}/.env.production"
APP_IMAGE="${1:-}"

if [[ ! "${APP_IMAGE}" =~ ^ghcr\.io/sprobe-dan/production-cicd-lab:[0-9a-f]{40}$ ]]; then
  echo "Error: provide an immutable production image with a full commit SHA."
  echo "Example: ghcr.io/sprobe-dan/production-cicd-lab:<40-character-sha>"
  exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Error: ${COMPOSE_FILE} does not exist."
  exit 1
fi

umask 077
printf 'APP_IMAGE=%s\n' "${APP_IMAGE}" > "${ENV_FILE}"

echo "Pulling production image: ${APP_IMAGE}"

docker compose \
  --project-name production-cicd-lab-production \
  --env-file "${ENV_FILE}" \
  --file "${COMPOSE_FILE}" \
  pull

echo "Starting production container"

docker compose \
  --project-name production-cicd-lab-production \
  --env-file "${ENV_FILE}" \
  --file "${COMPOSE_FILE}" \
  up --detach --remove-orphans --wait --wait-timeout 60

echo "Running production smoke test"

if ! curl \
  --fail \
  --silent \
  --show-error \
  --retry 10 \
  --retry-delay 2 \
  --retry-connrefused \
  http://127.0.0.1:8001/health > /dev/null; then

  echo "Production smoke test failed."

  docker compose \
    --project-name production-cicd-lab-production \
    --env-file "${ENV_FILE}" \
    --file "${COMPOSE_FILE}" \
    logs --tail 100

  exit 1
fi

docker image prune --force

echo "Production deployment completed successfully."