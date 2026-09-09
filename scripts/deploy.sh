#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/opt/production-cicd-lab"
COMPOSE_FILE="${APP_DIR}/compose.staging.yml"
ENV_FILE="${APP_DIR}/.env.staging"
APP_IMAGE="${1:-}"

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

echo "Pulling staging images"

"${compose[@]}" pull

echo "Starting the staging database"

"${compose[@]}" up \
  --detach \
  --wait \
  --wait-timeout 60 \
  db

echo "Applying staging database migrations"

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
  http://127.0.0.1:8000/health > /dev/null; then

  echo "Staging smoke test failed."
  "${compose[@]}" logs --tail 100
  exit 1
fi

docker image prune --force

echo "Staging deployment completed successfully."