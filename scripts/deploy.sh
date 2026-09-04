#!/usr/bin/env bash

set -Eeuo pipefail

readonly APP_DIR="/opt/production-cicd-lab"
readonly COMPOSE_FILE="${APP_DIR}/compose.staging.yml"
readonly IMAGE_REFERENCE="${1:-}"

if [[ -z "$IMAGE_REFERENCE" ]]; then
  echo "Usage: deploy.sh <immutable-image-reference>" >&2
  exit 1
fi

if [[ ! "$IMAGE_REFERENCE" =~ ^ghcr\.io/sprobe-dan/production-cicd-lab:[0-9a-f]{40}$ ]]; then
  echo "Deployment requires a full 40-character commit SHA image tag" >&2
  exit 1
fi

printf 'APP_IMAGE=%s\n' "$IMAGE_REFERENCE" >"${APP_DIR}/.env.next"
mv "${APP_DIR}/.env.next" "${APP_DIR}/.env"

docker compose \
  --file "$COMPOSE_FILE" \
  pull

docker compose \
  --file "$COMPOSE_FILE" \
  up \
  --detach \
  --remove-orphans

if ! "${APP_DIR}/smoke-test.sh"; then
  echo "Deployment verification failed" >&2

  docker compose \
    --file "$COMPOSE_FILE" \
    logs \
    --tail 100

  exit 1
fi

docker image prune --force

echo "Successfully deployed ${IMAGE_REFERENCE}"