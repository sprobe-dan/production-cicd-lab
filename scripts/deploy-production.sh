#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/opt/production-cicd-lab"
COMPOSE_FILE="${APP_DIR}/compose.production.yml"
ENV_FILE="${APP_DIR}/.env.production"
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

TEMP_ENV_FILE="$(mktemp "${APP_DIR}/.env.production.tmp.XXXXXX")"
trap 'rm -f "${TEMP_ENV_FILE}"' EXIT

printf 'DB_PASSWORD=%s\n' "${DB_PASSWORD}" > "${TEMP_ENV_FILE}"
printf 'APP_IMAGE=%s\n' "${APP_IMAGE}" >> "${TEMP_ENV_FILE}"

chmod 600 "${TEMP_ENV_FILE}"
mv "${TEMP_ENV_FILE}" "${ENV_FILE}"

compose=(
  docker compose
  --project-name production-cicd-lab-production
  --env-file "${ENV_FILE}"
  --file "${COMPOSE_FILE}"
)

echo "Pulling production images"

"${compose[@]}" pull

echo "Starting the production database"

"${compose[@]}" up \
  --detach \
  --wait \
  --wait-timeout 60 \
  db

echo "Applying production database migrations"

"${compose[@]}" run \
  --rm \
  --no-deps \
  api \
  alembic upgrade head

echo "Starting the production application"

"${compose[@]}" up \
  --detach \
  --remove-orphans \
  --wait \
  --wait-timeout 60 \
  api

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
  "${compose[@]}" logs --tail 100
  exit 1
fi

docker image prune --force

echo "Production deployment completed successfully."