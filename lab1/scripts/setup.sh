#!/usr/bin/env bash
# shellcheck disable=SC1091
set -Eeuo pipefail

APP_NAME="mywebapp"
APP_PORT="8000"
APP_HOST="127.0.0.1"
SERVICE_USER="mywebapp"
LEGACY_APP_USER="app"
DB_NAME="mywebappdb"
DB_USER="mywebapp"
DB_PASSWORD="mywebapp"
CONFIG_DIR="/etc/mywebapp"
PUBLISH_DIR="/opt/mywebapp"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    printf '\n==> %s\n' "$1"
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Run this script as root or through sudo."
        exit 1
    fi
}

install_packages() {
    log "Installing packages"
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y ca-certificates curl wget gnupg nginx postgresql postgresql-contrib openssh-server sudo

    if ! command -v dotnet >/dev/null 2>&1; then
        if ! apt-cache show dotnet-sdk-10.0 >/dev/null 2>&1; then
            . /etc/os-release
            wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
            dpkg -i /tmp/packages-microsoft-prod.deb
            rm -f /tmp/packages-microsoft-prod.deb
            apt-get update
        fi

        apt-get install -y dotnet-sdk-10.0
    fi
}

ensure_login_user() {
    local username="$1"

    if id "${username}" >/dev/null 2>&1; then
        usermod -s /bin/bash "${username}"
        mkdir -p "/home/${username}"
        chown "${username}:${username}" "/home/${username}"
    else
        useradd -m -s /bin/bash "${username}"
    fi

    echo "${username}:12345678" | chpasswd
    chage -d 0 "${username}"
}

ensure_system_user() {
    local username="$1"
    local home_dir="$2"

    if id "${username}" >/dev/null 2>&1; then
        usermod -d "${home_dir}" -s /usr/sbin/nologin "${username}"
    else
        useradd --system --create-home --home-dir "${home_dir}" --shell /usr/sbin/nologin "${username}"
    fi
}

create_users() {
    log "Creating Linux users"

    ensure_login_user student
    ensure_login_user teacher
    ensure_login_user operator

    usermod -aG sudo student
    usermod -aG sudo teacher

    ensure_system_user "${SERVICE_USER}" "/var/lib/${SERVICE_USER}"
    ensure_system_user "${LEGACY_APP_USER}" "/var/lib/${LEGACY_APP_USER}"

    local systemctl_path
    systemctl_path="$(command -v systemctl)"

    cat > /etc/sudoers.d/operator-mywebapp <<EOF
operator ALL=(root) NOPASSWD: ${systemctl_path} start ${APP_NAME}.service, ${systemctl_path} stop ${APP_NAME}.service, ${systemctl_path} restart ${APP_NAME}.service, ${systemctl_path} status ${APP_NAME}.service, ${systemctl_path} reload nginx, ${systemctl_path} reload nginx.service
EOF
    chmod 0440 /etc/sudoers.d/operator-mywebapp
    visudo -cf /etc/sudoers.d/operator-mywebapp >/dev/null
}

configure_postgresql() {
    log "Configuring PostgreSQL"

    systemctl enable --now postgresql

    sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
ALTER SYSTEM SET listen_addresses = '${APP_HOST}';
SQL
    systemctl restart postgresql

    sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
    ELSE
        ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL
}

publish_application() {
    log "Publishing ${APP_NAME}"

    install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${PUBLISH_DIR}"
    dotnet publish "${REPO_ROOT}/src/mywebapp/mywebapp.csproj" -c Release -o "${PUBLISH_DIR}"
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${PUBLISH_DIR}"
}

write_application_config() {
    log "Writing /etc/mywebapp/config.json"

    install -d -m 0750 -o root -g "${SERVICE_USER}" "${CONFIG_DIR}"

    cat > "${CONFIG_DIR}/config.json" <<EOF
{
  "Application": {
    "Name": "${APP_NAME}",
    "Host": "${APP_HOST}",
    "Port": ${APP_PORT}
  },
  "ConnectionStrings": {
    "DefaultConnection": "Host=${APP_HOST};Port=5432;Database=${DB_NAME};Username=${DB_USER};Password=${DB_PASSWORD}"
  },
  "Database": {
    "AutoMigrate": false
  }
}
EOF

    chown root:"${SERVICE_USER}" "${CONFIG_DIR}/config.json"
    chmod 0640 "${CONFIG_DIR}/config.json"
}

install_systemd_units() {
    log "Installing systemd units"

    cat > "/etc/systemd/system/${APP_NAME}.socket" <<EOF
[Unit]
Description=${APP_NAME} socket

[Socket]
ListenStream=${APP_HOST}:${APP_PORT}
NoDelay=true

[Install]
WantedBy=sockets.target
EOF

    cat > "/etc/systemd/system/${APP_NAME}.service" <<EOF
[Unit]
Description=Notes Service (${APP_NAME})
Requires=postgresql.service
Wants=${APP_NAME}.socket
After=network.target postgresql.service ${APP_NAME}.socket

[Service]
Type=notify
WorkingDirectory=${PUBLISH_DIR}
ExecStartPre=/usr/bin/dotnet ${PUBLISH_DIR}/${APP_NAME}.dll --migrate
ExecStart=/usr/bin/dotnet ${PUBLISH_DIR}/${APP_NAME}.dll
Restart=on-failure
RestartSec=3
User=${SERVICE_USER}
Group=${SERVICE_USER}
Environment=DOTNET_ENVIRONMENT=Production
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "${APP_NAME}.socket"
    systemctl enable "${APP_NAME}.service"
    systemctl restart "${APP_NAME}.service"
}

configure_nginx() {
    log "Configuring nginx"

    cat > "/etc/nginx/sites-available/${APP_NAME}" <<EOF
upstream ${APP_NAME}_backend {
    server ${APP_HOST}:${APP_PORT};
    keepalive 16;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;

    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    location = / {
        proxy_pass http://${APP_NAME}_backend;
    }

    location = /notes {
        proxy_pass http://${APP_NAME}_backend;
    }

    location ~ ^/notes/[0-9]+$ {
        proxy_pass http://${APP_NAME}_backend;
    }

    location / {
        return 404;
    }
}
EOF

    ln -sfn "/etc/nginx/sites-available/${APP_NAME}" "/etc/nginx/sites-enabled/${APP_NAME}"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx
}

write_gradebook() {
    log "Writing gradebook"

    install -o student -g student -m 0644 /dev/null /home/student/gradebook
    printf '3\n' > /home/student/gradebook
    chown student:student /home/student/gradebook
}

lock_default_user() {
    log "Locking default VM user"

    local default_user
    default_user="$(getent passwd 1000 | cut -d: -f1 || true)"

    case "${default_user}" in
        ""|student|teacher|operator)
            ;;
        *)
            passwd -l "${default_user}" || true
            usermod -s /usr/sbin/nologin "${default_user}" || true
            ;;
    esac
}

main() {
    require_root
    install_packages
    create_users
    configure_postgresql
    publish_application
    write_application_config
    install_systemd_units
    configure_nginx
    write_gradebook
    lock_default_user
    log "Deployment completed"
}

main "$@"
