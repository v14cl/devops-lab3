#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <image-repository> <image-tag>" >&2
    echo "Example: $0 ghcr.io/v14cl/devops-lab3 v1.0.0" >&2
    exit 1
fi

IMAGE_REPOSITORY="$1"
IMAGE_TAG="$2"
IMAGE_REF="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
CONFIG_FILE="${CONFIG_FILE:-/etc/mywebapp/config.json}"
ENV_FILE="${ENV_FILE:-/etc/mywebapp/deployment.env}"
UNIT_NAME="${UNIT_NAME:-mywebapp-container.service}"

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Required command is missing: ${command_name}" >&2
        exit 1
    fi
}

require_command docker
require_command sudo

if [[ -n "${GHCR_USERNAME:-}" && -n "${GHCR_TOKEN:-}" ]]; then
    echo "==> Logging in to ghcr.io"
    printf '%s' "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin
fi

echo "==> Pulling Docker image: ${IMAGE_REF}"
docker pull "${IMAGE_REF}"

echo "==> Running database migrations"
docker run --rm \
    --network host \
    -v "${CONFIG_FILE}:${CONFIG_FILE}:ro" \
    -e DOTNET_ENVIRONMENT=Production \
    "${IMAGE_REF}" --migrate

if [[ ! -w "${ENV_FILE}" ]]; then
    echo "Deployment env file is not writable: ${ENV_FILE}" >&2
    echo "Run scripts/provision-target.sh on the target node before deploying." >&2
    exit 1
fi

printf 'MYWEBAPP_IMAGE=%s\n' "${IMAGE_REF}" >"${ENV_FILE}"

echo "==> Restarting ${UNIT_NAME}"
sudo systemctl restart "${UNIT_NAME}"

sleep 5

echo "==> Checking ${UNIT_NAME} status"
if sudo systemctl is-active --quiet "${UNIT_NAME}"; then
    echo "${UNIT_NAME} is active"
else
    echo "${UNIT_NAME} is not active" >&2
    sudo systemctl status "${UNIT_NAME}" || true
    exit 1
fi
