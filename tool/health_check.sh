#!/usr/bin/env sh
set -eu
curl --fail --show-error --silent "${API_BASE_URL:-http://localhost:8080}/actuator/health"
