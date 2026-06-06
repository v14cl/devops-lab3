#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ ! -f "${REPO_ROOT}/deploy/deployment.defaults" ]]; then
    echo "Cannot find deploy/deployment.defaults" >&2
    exit 1
fi

source "${REPO_ROOT}/deploy/deployment.defaults"

export DEBIAN_FRONTEND=noninteractive
DB_PASSWORD="${DB_PASSWORD:-change_me_mywebapp}"
DEFAULT_LOGIN_PASSWORD="${DEFAULT_LOGIN_PASSWORD:-12345678}"
SYSTEMCTL="$(command -v systemctl)"
ENV_SUBST_VARS='${DEPLOY_APP_NAME} ${DEPLOY_UNIT} ${DEPLOY_APP_USER} ${DEPLOY_CONFIG_DIR} ${DEPLOY_CONFIG_FILE} ${DEPLOY_ENV_FILE} ${DEPLOY_CONTAINER_NAME} ${DEPLOY_IMAGE} ${DEPLOY_APP_PORT} ${DEPLOY_APP_BIND} ${DEPLOY_DB_HOST} ${DEPLOY_DB_PORT} ${DEPLOY_DB_NAME} ${DEPLOY_DB_USER} ${DEPLOY_NGINX_ACCESS_LOG} ${DEPLOY_NGINX_ERROR_LOG} ${DB_PASSWORD}'

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Run this script as root or through sudo." >&2
        exit 1
    fi
}

render_template() {
    local src="$1"
    local dst="$2"
    envsubst "${ENV_SUBST_VARS}" <"${src}" >"${dst}"
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        return
    fi

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        >/etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ensure_login_user() {
    local username="$1"
    if id "${username}" >/dev/null 2>&1; then
        usermod -s /bin/bash "${username}"
    else
        useradd -m -s /bin/bash "${username}"
    fi
    echo "${username}:${DEFAULT_LOGIN_PASSWORD}" | chpasswd
    chage -d 0 "${username}"
}

configure_users() {
    ensure_login_user student
    ensure_login_user teacher
    ensure_login_user operator

    if id "${DEPLOY_APP_USER}" >/dev/null 2>&1; then
        usermod -s /bin/bash "${DEPLOY_APP_USER}"
    else
        useradd -m -s /bin/bash "${DEPLOY_APP_USER}"
    fi

    usermod -aG sudo student
    usermod -aG sudo teacher
    usermod -aG docker "${DEPLOY_APP_USER}"

    install -d -m 0700 -o "${DEPLOY_APP_USER}" -g "${DEPLOY_APP_USER}" "/home/${DEPLOY_APP_USER}/.ssh"
    touch "/home/${DEPLOY_APP_USER}/.ssh/authorized_keys"
    chown "${DEPLOY_APP_USER}:${DEPLOY_APP_USER}" "/home/${DEPLOY_APP_USER}/.ssh/authorized_keys"
    chmod 0600 "/home/${DEPLOY_APP_USER}/.ssh/authorized_keys"

    cat >/etc/sudoers.d/operator-mywebapp <<SUDOERS_OPERATOR
operator ALL=(root) NOPASSWD: ${SYSTEMCTL} start ${DEPLOY_UNIT}.service, ${SYSTEMCTL} stop ${DEPLOY_UNIT}.service, ${SYSTEMCTL} restart ${DEPLOY_UNIT}.service, ${SYSTEMCTL} status ${DEPLOY_UNIT}.service, ${SYSTEMCTL} reload nginx, ${SYSTEMCTL} reload nginx.service
SUDOERS_OPERATOR
    chmod 0440 /etc/sudoers.d/operator-mywebapp

    cat >/etc/sudoers.d/mywebapp-deploy <<SUDOERS_DEPLOY
${DEPLOY_APP_USER} ALL=(root) NOPASSWD: ${SYSTEMCTL} restart ${DEPLOY_UNIT}.service, ${SYSTEMCTL} status ${DEPLOY_UNIT}.service, ${SYSTEMCTL} is-active ${DEPLOY_UNIT}.service
SUDOERS_DEPLOY
    chmod 0440 /etc/sudoers.d/mywebapp-deploy
}

configure_postgresql() {
    systemctl enable --now postgresql
    sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DEPLOY_DB_USER}') THEN
        CREATE ROLE ${DEPLOY_DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
    ELSE
        ALTER ROLE ${DEPLOY_DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${DEPLOY_DB_NAME} OWNER ${DEPLOY_DB_USER}'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${DEPLOY_DB_NAME}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${DEPLOY_DB_NAME} TO ${DEPLOY_DB_USER};
SQL
}

configure_application_files() {
    install -d -m 0750 -o root -g "${DEPLOY_APP_USER}" "${DEPLOY_CONFIG_DIR}"

    render_template "${REPO_ROOT}/deploy/templates/config.json.template" "${DEPLOY_CONFIG_FILE}"
    chown root:"${DEPLOY_APP_USER}" "${DEPLOY_CONFIG_FILE}"
    chmod 0640 "${DEPLOY_CONFIG_FILE}"

    printf 'MYWEBAPP_IMAGE=%s\n' "${DEPLOY_IMAGE}" >"${DEPLOY_ENV_FILE}"
    chown "${DEPLOY_APP_USER}:${DEPLOY_APP_USER}" "${DEPLOY_ENV_FILE}"
    chmod 0640 "${DEPLOY_ENV_FILE}"
}

configure_systemd() {
    render_template "${REPO_ROOT}/deploy/templates/mywebapp-container.service.template" "/etc/systemd/system/${DEPLOY_UNIT}.service"
    systemctl daemon-reload
    systemctl enable "${DEPLOY_UNIT}.service"
}

configure_nginx() {
    render_template "${REPO_ROOT}/deploy/templates/nginx-mywebapp.conf.template" "/etc/nginx/sites-available/${DEPLOY_APP_NAME}"
    rm -f /etc/nginx/sites-enabled/default
    ln -sfn "/etc/nginx/sites-available/${DEPLOY_APP_NAME}" "/etc/nginx/sites-enabled/${DEPLOY_APP_NAME}"
    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx
}

write_gradebook() {
    install -o student -g student -m 0644 /dev/null /home/student/gradebook
    printf '3\n' >/home/student/gradebook
    chown student:student /home/student/gradebook
}

main() {
    require_root
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg gettext-base nginx openssh-server postgresql postgresql-contrib sudo
    install_docker
    configure_users
    configure_postgresql
    configure_application_files
    configure_systemd
    configure_nginx
    write_gradebook
    passwd -l vagrant 2>/dev/null || true
    echo "Target node provisioning finished. Add the runner SSH public key to /home/${DEPLOY_APP_USER}/.ssh/authorized_keys."
}

main "$@"
