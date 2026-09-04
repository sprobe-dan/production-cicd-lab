#!/usr/bin/env bash

set -Eeuo pipefail

readonly BASE_URL="${1:-http://127.0.0.1:8000}"
readonly MAX_ATTEMPTS=15

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  if curl --fail --silent "${BASE_URL}/health" |
    grep --quiet '"status":"healthy"'; then
    echo "Health check passed"

    curl --fail --silent --show-error "${BASE_URL}/version"
    echo

    exit 0
  fi

  echo "Waiting for application: ${attempt}/${MAX_ATTEMPTS}"
  sleep 2
done

echo "Application did not become healthy" >&2
exit 1