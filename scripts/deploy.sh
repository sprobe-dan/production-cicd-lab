#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/opt/production-cicd-lab"
COMPOSE_FILE="${APP_DIR}/compose.staging.yml"
ENV_FILE="${APP_DIR}/.env.staging"
APP_IMAGE="${1:-}"
CONTAINER_NAME="production-cicd-lab-staging"
CURRENT_IMAGE_FILE="${APP_DIR}/.current-image.staging"
PREVIOUS_IMAGE_FILE="${APP_DIR}/.previous-image.staging"

SKIP_MIGRATIONS="${SKIP_MIGRATIONS:-false}"

if [[ "${SKIP_MIGRATIONS}" != "true" ]] &&
  [[ "${SKIP_MIGRATIONS}" != "false" ]]; then
  echo "Error: SKIP_MIGRATIONS must be true or false."
  exit 1
fi

write_state_file() {
  local destination="$1"
  local value="$2"
  local temporary_file

  temporary_file="$(mktemp "${destination}.tmp.XXXXXX")"
  printf '%s\n' "${value}" > "${temporary_file}"
  chmod 600 "${temporary_file}"
  mv "${temporary_file}" "${destination}"
}

if [[ ! "${APP_IMAGE}" =~ ^ghcr\.io/sprobe-dan/production-cicd-lab:[0-9a-f]{40}$ ]]; then
  echo "Error: provide an immutable image tagged with a full commit SHA."
  exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Error: ${COMPOSE_FILE} does not exist."
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: ${ENV_FILE} does not exist."
  exit 1
fi

DB_PASSWORD="$(
  awk -F= '
    $1 == "DB_PASSWORD" {
      print substr($0, index($0, "=") + 1)
      exit
    }
  ' "${ENV_FILE}"
)"

if [[ ! "${DB_PASSWORD}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Error: DB_PASSWORD is missing or invalid."
  exit 1
fi

umask 077

TEMP_ENV_FILE="$(mktemp "${APP_DIR}/.env.staging.tmp.XXXXXX")"
trap 'rm -f "${TEMP_ENV_FILE}"' EXIT

printf 'DB_PASSWORD=%s\n' "${DB_PASSWORD}" > "${TEMP_ENV_FILE}"
printf 'APP_IMAGE=%s\n' "${APP_IMAGE}" >> "${TEMP_ENV_FILE}"

chmod 600 "${TEMP_ENV_FILE}"
mv "${TEMP_ENV_FILE}" "${ENV_FILE}"

compose=(
  docker compose
  --project-name production-cicd-lab
  --env-file "${ENV_FILE}"
  --file "${COMPOSE_FILE}"
)

DEPLOYED_IMAGE="$(
  docker inspect \
    --format='{{.Config.Image}}' \
    "${CONTAINER_NAME}" \
    2>/dev/null || true
)"

if [[ "${DEPLOYED_IMAGE}" =~ ^ghcr\.io/sprobe-dan/production-cicd-lab:[0-9a-f]{40}$ ]] &&
  [[ "${DEPLOYED_IMAGE}" != "${APP_IMAGE}" ]]; then
  write_state_file "${PREVIOUS_IMAGE_FILE}" "${DEPLOYED_IMAGE}"
fi

DEPLOYED_IMAGE="$(
  docker inspect \
    --format='{{.Config.Image}}' \
    "${CONTAINER_NAME}" \
    2>/dev/null || true
)"

if [[ "${DEPLOYED_IMAGE}" =~ ^ghcr\.io/sprobe-dan/production-cicd-lab:[0-9a-f]{40}$ ]] &&
  [[ "${DEPLOYED_IMAGE}" != "${APP_IMAGE}" ]]; then
  write_state_file "${PREVIOUS_IMAGE_FILE}" "${DEPLOYED_IMAGE}"
fi

echo "Pulling staging images"

"${compose[@]}" pull

echo "Starting the staging database"

"${compose[@]}" up \
  --detach \
  --wait \
  --wait-timeout 60 \
  db

if [[ "${SKIP_MIGRATIONS}" == "true" ]]; then
  echo "Skipping migrations during application rollback"
else
  echo "Applying staging database migrations"

  "${compose[@]}" run \
    --rm \
    --no-deps \
    api \
    alembic upgrade head
fi

"${compose[@]}" run \
  --rm \
  --no-deps \
  api \
  alembic upgrade head

echo "Starting the staging application"

"${compose[@]}" up \
  --detach \
  --remove-orphans \
  --wait \
  --wait-timeout 60 \
  api

echo "Running staging smoke test"

if ! curl \
  --fail \
  --silent \
  --show-error \
  --retry 10 \
  --retry-delay 2 \
  --retry-connrefused \
  http://127.0.0.1:8000/ready > /dev/null; then

  echo "Staging smoke test failed."
  "${compose[@]}" logs --tail 100
  exit 1
fi

write_state_file "${CURRENT_IMAGE_FILE}" "${APP_IMAGE}"

docker image prune --force

echo "Staging deployment completed successfully."