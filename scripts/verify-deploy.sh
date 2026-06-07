#!/usr/bin/env bash
exit 1
# shellcheck disable=SC2029
set -Eeuo pipefail

TARGET_HOST="${1:-192.168.56.10}"
TARGET_USER="${TARGET_USER:-mywebapp}"
APP_PORT="${APP_PORT:-8000}"
BASE_URL="http://${TARGET_HOST}"

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Required command is missing: ${command_name}" >&2
        exit 1
    fi
}

require_command curl
require_command jq
require_command ssh

http_status() {
    local url="$1"
    curl -sS -o /dev/null -w '%{http_code}' "${url}"
}

echo "==> Verifying deployment on ${TARGET_HOST}"

echo "1. Checking public root endpoint through nginx"
ROOT_STATUS="$(http_status "${BASE_URL}/")"
if [[ "${ROOT_STATUS}" != "200" ]]; then
    echo "[FAIL] / returned ${ROOT_STATUS}; expected 200" >&2
    exit 1
fi
ROOT_BODY="$(curl -fsS "${BASE_URL}/")"
if ! grep -qi 'mywebapp' <<<"${ROOT_BODY}"; then
    echo "[FAIL] / response does not contain mywebapp marker" >&2
    exit 1
fi
echo "[OK] / is available through nginx"

echo "2. Checking public /notes endpoint through nginx"
NOTES_STATUS="$(http_status "${BASE_URL}/notes")"
if [[ "${NOTES_STATUS}" != "200" ]]; then
    echo "[FAIL] /notes returned ${NOTES_STATUS}; expected 200" >&2
    exit 1
fi
echo "[OK] /notes is available through nginx"

echo "3. Checking direct health endpoint on target node"
ALIVE_BODY="$(ssh "${TARGET_USER}@${TARGET_HOST}" "curl -fsS http://127.0.0.1:${APP_PORT}/health/alive")"
if [[ "${ALIVE_BODY}" != "OK" ]]; then
    echo "[FAIL] direct /health/alive returned '${ALIVE_BODY}'; expected OK" >&2
    exit 1
fi
echo "[OK] direct /health/alive returned OK"

echo "4. Checking nginx hides health endpoints"
NGINX_HEALTH_STATUS="$(http_status "${BASE_URL}/health/alive")"
if [[ "${NGINX_HEALTH_STATUS}" != "404" ]]; then
    echo "[FAIL] nginx returned ${NGINX_HEALTH_STATUS} for /health/alive; expected 404" >&2
    exit 1
fi
echo "[OK] nginx blocks /health/alive"

echo "5. Creating and reading a verification note"
NOTE_TITLE="verification-note-$(date +%s)"
NOTE_CONTENT="created by deployment verification"
CREATE_PAYLOAD="$(jq -n --arg title "${NOTE_TITLE}" --arg content "${NOTE_CONTENT}" '{title: $title, content: $content}')"
CREATE_RESPONSE="$(curl -fsS \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "${CREATE_PAYLOAD}" \
    "${BASE_URL}/notes")"
NOTE_ID="$(jq -r '.id' <<<"${CREATE_RESPONSE}")"
if [[ -z "${NOTE_ID}" || "${NOTE_ID}" == "null" ]]; then
    echo "[FAIL] could not parse created note id: ${CREATE_RESPONSE}" >&2
    exit 1
fi

READ_RESPONSE="$(curl -fsS -H 'Accept: application/json' "${BASE_URL}/notes/${NOTE_ID}")"
READ_TITLE="$(jq -r '.title' <<<"${READ_RESPONSE}")"
if [[ "${READ_TITLE}" != "${NOTE_TITLE}" ]]; then
    echo "[FAIL] note ${NOTE_ID} title is '${READ_TITLE}', expected '${NOTE_TITLE}'" >&2
    exit 1
fi
echo "[OK] note lifecycle works through nginx"

echo "==> Deployment verification passed"
