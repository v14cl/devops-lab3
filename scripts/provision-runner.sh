#!/usr/bin/env bash
# shellcheck disable=SC1091
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
RUNNER_VERSION="${RUNNER_VERSION:-2.321.0}"
RUNNER_USER="${RUNNER_USER:-runner}"
TARGET_HOST="${TARGET_HOST:-192.168.56.10}"
TARGET_USER="${TARGET_USER:-mywebapp}"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Run this script as root or through sudo." >&2
        exit 1
    fi
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

configure_runner_user() {
    if id "${RUNNER_USER}" >/dev/null 2>&1; then
        usermod -s /bin/bash "${RUNNER_USER}"
    else
        useradd -m -s /bin/bash "${RUNNER_USER}"
    fi
    usermod -aG docker "${RUNNER_USER}"

    install -d -m 0700 -o "${RUNNER_USER}" -g "${RUNNER_USER}" "/home/${RUNNER_USER}/.ssh"
    if [[ ! -f "/home/${RUNNER_USER}/.ssh/id_ed25519" ]]; then
        sudo -u "${RUNNER_USER}" ssh-keygen -t ed25519 -N "" -f "/home/${RUNNER_USER}/.ssh/id_ed25519"
    fi

    cat >"/home/${RUNNER_USER}/.ssh/config" <<SSH_CONFIG
Host target-node
  HostName ${TARGET_HOST}
  User ${TARGET_USER}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host ${TARGET_HOST}
  User ${TARGET_USER}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
SSH_CONFIG
    chown "${RUNNER_USER}:${RUNNER_USER}" "/home/${RUNNER_USER}/.ssh/config"
    chmod 0600 "/home/${RUNNER_USER}/.ssh/config"
}

install_github_runner() {
    local runner_dir="/home/${RUNNER_USER}/actions-runner"
    install -d -m 0755 -o "${RUNNER_USER}" -g "${RUNNER_USER}" "${runner_dir}"

    if [[ ! -f "${runner_dir}/config.sh" ]]; then
        curl -fsSL -o "/tmp/actions-runner.tar.gz" \
            "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
        tar -xzf /tmp/actions-runner.tar.gz -C "${runner_dir}"
        rm -f /tmp/actions-runner.tar.gz
        chown -R "${RUNNER_USER}:${RUNNER_USER}" "${runner_dir}"
    fi

    "${runner_dir}/bin/installdependencies.sh"
}

main() {
    require_root
    apt-get update -qq
    apt-get install -y ca-certificates curl git gnupg jq libicu-dev sudo
    install_docker
    configure_runner_user
    install_github_runner

    echo "Runner provisioning finished. Register the runner manually with GitHub."
    echo "Public SSH key to add on the target node:"
    cat "/home/${RUNNER_USER}/.ssh/id_ed25519.pub"
}

main "$@"
