# Лабораторна робота 3

Макоткін Владислав, ІМ-43

Основний workflow: `.github/workflows/ci-cd.yml`.

## GitHub Actions

Workflow запускається на:

- `push` у `main`;
- `pull_request` у `main`;
- tags `v*`.

Jobs:

| Job | Коли запускається | Що робить |
| --- | --- | --- |
| `lint` | `main`, PR, tags | static analysis, Dockerfile lint, shell scripts lint, config validation |
| `test` | `main`, PR, tags | автоматичні тести та coverage threshold `40%` |
| `build` | тільки `push` | збирає і пушить image у GHCR |
| `deploy` | тільки annotated tags `v*` | розгортає image на target node та запускає verification |

Для release deploy використовується тільки annotated tag. Lightweight tag зупиниться на job `build`.

## Налаштування GitHub

1. Створити або перейменувати GitHub repository у `devops-lab3`.
2. Запушити код у `main`.
3. Перевірити, що repository має permission для GHCR: `Settings -> Actions -> General -> Workflow permissions -> Read and write permissions`.
4. У `Settings -> Secrets and variables -> Actions -> Variables` додати змінні, якщо адреси відрізняються від Vagrant defaults:

| Variable | Default | Призначення |
| --- | --- | --- |
| `TARGET_HOST` | `192.168.56.10` | IP target node |
| `TARGET_USER` | `mywebapp` | Linux user для deploy на target node |

5. У `Settings -> Packages` після першого build зробити package `devops-lab3` public, якщо pull з target node має працювати без GHCR token.
6. Налаштувати branch protection для `main`: `Settings -> Branches -> Add branch protection rule`.
7. Увімкнути `Require a pull request before merging`.
8. Увімкнути `Require status checks to pass before merging`.
9. Додати required checks: `Lint and Static Analysis`, `Tests and Coverage`.
10. За потреби увімкнути `Require branches to be up to date before merging`.

## Підготовка VM

Підняти дві VM:

```bash
vagrant up target
vagrant up runner
```

Target node provisioning виконує `scripts/provision-target.sh` і встановлює Docker, PostgreSQL, nginx, systemd unit для контейнера, користувача `mywebapp` та конфіг `/etc/mywebapp/config.json`.

Runner provisioning виконує `scripts/provision-runner.sh`, встановлює Docker, залежності GitHub runner та генерує SSH key для користувача `runner`.

Після provisioning потрібно вручну зареєструвати runner у GitHub:

```bash
vagrant ssh runner
sudo -iu runner
cd ~/actions-runner
./config.sh --url https://github.com/v14cl/devops-lab3 --token <GITHUB_RUNNER_TOKEN> --labels self-hosted,linux,x64
exit
cd /home/runner/actions-runner
sudo ./svc.sh install runner
sudo ./svc.sh start
```

Токен runner не додавати в репозиторій.

Додати SSH public key runner на target node:

```bash
vagrant ssh runner -c 'sudo cat /home/runner/.ssh/id_ed25519.pub'
vagrant ssh target
sudo -iu mywebapp
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo '<RUNNER_PUBLIC_KEY>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Перевірити SSH з runner на target:

```bash
vagrant ssh runner
sudo -iu runner
ssh mywebapp@192.168.56.10 'hostname && whoami'
```

Після здачі лабораторної зупинити runner VM:

```bash
vagrant halt runner
```