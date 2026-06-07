# Lab 3: гайд по сдаче CI/CD для этого проекта

Этот гайд адаптирован под текущий репозиторий `v14cl/devops-lab3`.

Цель: показать, что GitHub Actions CI, branch protection, GHCR image, self-hosted runner и CD на отдельный target node реально работают для .NET-приложения `mywebapp`.

## 0. Что находится в проекте

| Компонент | Файл или путь |
| --- | --- |
| Solution | `devops-lab3.sln` |
| Web app | `lab1/src/mywebapp` |
| Tests | `tests/mywebapp.Tests` |
| Dockerfile | `lab1/src/mywebapp/Dockerfile` |
| Docker build context | `lab1` |
| GitHub Actions workflow | `.github/workflows/ci-cd.yml` |
| Vagrant VMs | `Vagrantfile` |
| Target provisioning | `scripts/provision-target.sh` |
| Runner provisioning | `scripts/provision-runner.sh` |
| Deploy script | `scripts/deploy.sh` |
| Deploy verification | `scripts/verify-deploy.sh` |

Приложение `mywebapp` хранит notes в PostgreSQL и в production доступно через nginx.

Основные endpoints:

| Method | Path | Назначение |
| --- | --- | --- |
| `GET` | `/` | HTML-страница со списком публичных endpoints |
| `GET` | `/notes` | список заметок |
| `POST` | `/notes` | создание заметки |
| `GET` | `/notes/{id}` | чтение заметки |
| `GET` | `/health/alive` | внутренний healthcheck приложения |
| `GET` | `/health/ready` | внутренний readiness check с PostgreSQL |

В deployment через nginx публично открыты только `/`, `/notes` и `/notes/{id}`. Health endpoints должны возвращать `404` через nginx, но быть доступны напрямую на target node по `127.0.0.1:8000`.

## 1. Минимальный сценарий сдачи

1. Поднять `target` и `runner` через Vagrant.
2. Зарегистрировать `runner` как GitHub self-hosted runner.
3. Дать runner SSH-доступ к пользователю `mywebapp` на target.
4. Добавить GitHub Actions variables для target.
5. Настроить branch protection для `main`.
6. Показать успешный PR с passed checks.
7. Показать failed PR, который нельзя merge.
8. Запустить release CD через annotated tag `v*`.
9. Показать successful deploy и verification.
10. Показать failed verification demo, если это требуется в отчете.

## 2. GitHub repository settings

В GitHub repository открыть:

```text
Settings -> Actions -> General
```

Проверить:

| Настройка | Значение |
| --- | --- |
| Actions permissions | Actions enabled |
| Workflow permissions | Read and write permissions |
| Allow GitHub Actions to create and approve pull requests | можно оставить disabled |

`GITHUB_TOKEN` вручную добавлять не нужно. GitHub создает его автоматически, а workflow сам запрашивает `packages: write` в job `build`.

## 3. Branch protection для `main`

В GitHub открыть:

```text
Settings -> Branches -> Add branch protection rule
```

Рекомендуемые настройки:

| Поле | Значение |
| --- | --- |
| Branch name pattern | `main` |
| Require a pull request before merging | enabled |
| Require status checks to pass before merging | enabled |
| Require branches to be up to date before merging | enabled |
| Required checks | `Lint and Static Analysis`, `Tests and Coverage` |

Не добавляй `Build and Push Image` как required check для PR. В этом проекте `build` запускается только на `push`, а не на `pull_request`.

## 4. Что делает workflow `CI/CD`

Workflow находится в `.github/workflows/ci-cd.yml`.

Он запускается на:

| Event | Что запускается |
| --- | --- |
| `pull_request` в `main` | `lint`, `test` |
| `push` в `main` | `lint`, `test`, `build` |
| `push` tag `v*` | `lint`, `test`, `build`, `deploy` |

Jobs:

| Job id | UI name | Что делает |
| --- | --- | --- |
| `lint` | `Lint and Static Analysis` | `dotnet format`, `dotnet build -warnaserror`, Hadolint, ShellCheck, JSON validation, Docker Compose validation |
| `test` | `Tests and Coverage` | `dotnet test` с Coverlet threshold `40%` по line coverage |
| `build` | `Build and Push Image` | собирает Docker image и публикует в GHCR |
| `deploy` | `Deploy and Verify` | запускается на self-hosted runner и деплоит image на target по SSH |

Docker image публикуется как:

```text
ghcr.io/v14cl/devops-lab3
```

Для `main` workflow публикует tags:

```text
latest
sha-<full-commit-sha>
```

Для release tag `v1.0.0` workflow публикует tags:

```text
stable
v1.0.0
```

## 5. Локальная проверка перед push

Если локально установлен .NET 10 SDK, можно проверить то же, что проверяет CI:

```bash
`dotnet restore devops-lab3.sln`
dotnet format devops-lab3.sln --verify-no-changes --no-restore --verbosity minimal
dotnet build devops-lab3.sln --configuration Release --no-restore -warnaserror
mkdir -p coverage TestResults
dotnet test tests/mywebapp.Tests/mywebapp.Tests.csproj \
  --configuration Release \
  --no-restore \
  --logger trx \
  --results-directory TestResults \
  /p:CollectCoverage=true \
  /p:CoverletOutput="$(pwd)/coverage/" \
  /p:CoverletOutputFormat=cobertura \
  /p:Threshold=40 \
  /p:ThresholdType=line \
  /p:ThresholdStat=total
```

Проверка Docker Compose из lab1:

```bash
docker compose -f lab1/docker-compose.yml config >/dev/null
```

Запуск приложения локально через Docker Compose:

```bash
cd lab1
docker compose up --build
```

Проверки:

```bash
curl -i http://localhost/
curl -i http://localhost/notes
curl -i http://localhost/health/alive
curl -i http://localhost/health/ready
```

## 6. Поднять target node и runner node

Из корня проекта:

```bash
vagrant up target
vagrant up runner
```

Ожидаемые VM:

| VM | Hostname | IP | Назначение |
| --- | --- | --- | --- |
| `target` | `target-node` | `192.168.56.10` | тут работает PostgreSQL, nginx и deployed app |
| `runner` | `github-runner` | `192.168.56.20` | тут работает GitHub Actions self-hosted runner |

Forwarded port для target:

| Host | Guest |
| --- | --- |
| `localhost:8080` | `target:80` |

Приложение нельзя деплоить на runner node. Runner только выполняет GitHub Actions job и ходит по SSH на target node.

`provision-target.sh` устанавливает Docker, PostgreSQL, nginx, пользователей, `/etc/mywebapp/config.json`, `/etc/mywebapp/deployment.env` и systemd unit `mywebapp-container.service`.

`provision-runner.sh` устанавливает Docker, GitHub Actions runner files, `jq`, SSH key пользователя `runner` и SSH config для `target-node`.

## 7. Добавить SSH key runner-а на target

Получить public key на runner VM:

```bash
vagrant ssh runner
sudo -iu runner
cat ~/.ssh/id_ed25519.pub
exit
exit
```

Добавить этот ключ на target VM в пользователя `mywebapp`:

```bash
vagrant ssh target
sudo tee -a /home/mywebapp/.ssh/authorized_keys
sudo chown mywebapp:mywebapp /home/mywebapp/.ssh/authorized_keys
sudo chmod 600 /home/mywebapp/.ssh/authorized_keys
exit
```

После команды `sudo tee -a ...` вставь public key, нажми `Enter`, затем `Ctrl+D`.

Проверить SSH с runner на target:

```bash
vagrant ssh runner
sudo -iu runner
ssh mywebapp@192.168.56.10 'hostname && docker --version && sudo systemctl is-active mywebapp-container.service'
exit
exit
```

Если SSH не работает, CD тоже не заработает.

## 8. Зарегистрировать self-hosted runner в GitHub

В GitHub открыть:

```text
Settings -> Actions -> Runners -> New self-hosted runner -> Linux x64
```

На runner VM выполнить команды, которые покажет GitHub. Общая структура:

```bash
vagrant ssh runner
sudo -iu runner
cd ~/actions-runner
./config.sh --url https://github.com/v14cl/devops-lab3 --token <TOKEN_FROM_GITHUB>
exit
sudo /home/runner/actions-runner/svc.sh install runner
sudo /home/runner/actions-runner/svc.sh start
sudo /home/runner/actions-runner/svc.sh status
exit
```

Важно: runner registration token нельзя коммитить и нельзя вставлять в markdown-файлы.

После регистрации в GitHub должен появиться online runner с label `self-hosted`.

## 9. GitHub Actions variables

Workflow `deploy` использует GitHub Actions variables, не secrets:

```yaml
env:
  TARGET_HOST: ${{ vars.TARGET_HOST }}
  TARGET_USER: ${{ vars.TARGET_USER }}
```

В GitHub открыть:

```text
Settings -> Secrets and variables -> Actions -> Variables -> New repository variable
```

Добавить:

| Variable | Значение |
| --- | --- |
| `TARGET_HOST` | `192.168.56.10` |
| `TARGET_USER` | `mywebapp` |

Если variables не заданы, workflow использует fallback значения `192.168.56.10` и `mywebapp`.

## 10. GHCR package

CI публикует image в GitHub Container Registry:

```text
ghcr.io/v14cl/devops-lab3
```

Для лабораторной самый простой вариант: сделать package public.

В GitHub:

```text
Packages -> devops-lab3 -> Package settings -> Change visibility -> Public
```

Если package private, target node не сможет выполнить `docker pull ghcr.io/v14cl/devops-lab3:<tag>` без `docker login ghcr.io`. В текущем CD credentials на target отдельно не передаются, поэтому public package проще и надежнее для демонстрации.

## 11. Проверить CI на `main`

Запушить `main`:

```bash
git checkout main
git pull
git push origin main
```

В GitHub Actions должен пройти workflow `CI/CD`.

Ожидаемые jobs на `main` push:

| Job | Ожидаемый результат |
| --- | --- |
| `Lint and Static Analysis` | passed |
| `Tests and Coverage` | passed |
| `Build and Push Image` | passed |

Для отчета нужен screenshot успешного workflow run.

## 12. Coverage artifact

Job `Tests and Coverage` загружает artifact только для `main`:

```text
coverage-report
```

В успешном workflow run открыть нижнюю часть страницы `Artifacts` и показать `coverage-report`.

Если тесты упали, workflow дополнительно загружает artifact:

```text
test-results
```

## 13. Успешный PR

Создать ветку:

```bash
git checkout main
git pull
git checkout -b demo/success-pr
```

Сделать безопасную правку, например добавить строку в `README.md` или поправить текст в `LAB3_REPORT.md`.

```bash
git add README.md
git commit -m "docs: update readme for success pr demo"
git push -u origin demo/success-pr
```

В GitHub создать PR в `main`, дождаться checks:

```text
Lint and Static Analysis
Tests and Coverage
```

Оба checks должны пройти. После этого PR можно merge.

Для отчета: screenshot PR с passed checks и merge commit.

## 14. Failed PR, который нельзя merge

Создать ветку:

```bash
git checkout main
git pull
git checkout -b demo/failing-pr
```

Безопасный вариант поломки: временно сломать тест, например ожидание в `tests/mywebapp.Tests/SystemEndpointsTests.cs`.

Пример:

```csharp
Assert.Equal("BROKEN", body);
```

Закоммитить и запушить ветку:

```bash
git add tests/mywebapp.Tests/SystemEndpointsTests.cs
git commit -m "test: intentionally fail pr checks"
git push -u origin demo/failing-pr
```

В GitHub создать PR в `main`, дождаться failed check `Tests and Coverage` и показать, что merge заблокирован branch protection rule.

Эту ветку не мержить.

Для отчета: screenshot failed PR с disabled merge.

## 15. Запустить CD через annotated tag

CD запускается только на tags `v*`. Для release нужен именно annotated tag, потому что workflow проверяет тип tag через `git cat-file -t`.

```bash
git checkout main
git pull
git tag -a v1.0.0 -m "Lab 3 release v1.0.0"
git push origin v1.0.0
```

Ожидаемый результат:

| Job | Что происходит |
| --- | --- |
| `Lint and Static Analysis` | проходит на tag |
| `Tests and Coverage` | проходит на tag |
| `Build and Push Image` | публикует `stable` и `v1.0.0` в GHCR |
| `Deploy and Verify` | self-hosted runner деплоит image на target и запускает verification |

Для отчета нужен screenshot или log успешного job `Deploy and Verify`.

Если случайно создал lightweight tag, удалить его и создать annotated:

```bash
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
git tag -a v1.0.0 -m "Lab 3 release v1.0.0"
git push origin v1.0.0
```

## 16. Что делает deploy

Job `Deploy and Verify` выполняется на self-hosted runner.

Deploy step:

1. Берет image repository из `IMAGE_NAME`: `ghcr.io/v14cl/devops-lab3`.
2. Берет image tag из `GITHUB_REF_NAME`: например `v1.0.0`.
3. Подключается по SSH к `mywebapp@192.168.56.10`.
4. На target выполняет `scripts/deploy.sh`.

На target `scripts/deploy.sh`:

1. Pull image `ghcr.io/v14cl/devops-lab3:v1.0.0`.
2. Запускает EF Core migrations через контейнер с аргументом `--migrate`.
3. Записывает `MYWEBAPP_IMAGE=<image>` в `/etc/mywebapp/deployment.env`.
4. Перезапускает systemd unit `mywebapp-container.service`.
5. Проверяет, что unit active.

## 17. Ручная проверка deployment

После успешного CD можно проверить с host machine:

```bash
curl -i http://localhost:8080/
curl -i http://localhost:8080/notes
curl -i http://localhost:8080/health/alive
```

Ожидания через nginx:

| Проверка | Ожидаемо |
| --- | --- |
| `GET /` | `200`, HTML содержит `mywebapp` |
| `GET /notes` | `200` |
| `GET /health/alive` | `404` |

Проверить напрямую на target node:

```bash
vagrant ssh target
curl -i http://127.0.0.1:8000/health/alive
curl -i http://127.0.0.1:8000/health/ready
sudo systemctl status mywebapp-container --no-pager
sudo journalctl -u mywebapp-container -n 80 --no-pager
exit
```

Ожидания напрямую на target:

| Проверка | Ожидаемо |
| --- | --- |
| `GET 127.0.0.1:8000/health/alive` | `200`, body `OK` |
| `GET 127.0.0.1:8000/health/ready` | `200`, body `OK` |
| `mywebapp-container` | `active` |

Проверка создания note через nginx:

```bash
curl -i \
  -H 'Content-Type: application/json' \
  -d '{"title":"manual check","content":"created after deploy"}' \
  http://localhost:8080/notes

curl -i http://localhost:8080/notes
```

## 18. Failed verification demo

Verification script `scripts/verify-deploy.sh` проверяет, что nginx скрывает `/health/alive` и возвращает `404`.

Чтобы показать failed verification, временно сломай nginx на target так, чтобы health endpoint стал публичным:

```bash
vagrant ssh target
sudo sed -i 's/return 404;/proxy_pass http:\/\/mywebapp_backend;/' /etc/nginx/sites-available/mywebapp
sudo nginx -t
sudo systemctl reload nginx
exit
```

Создать новый annotated tag:

```bash
git checkout main
git pull
git tag -a v1.0.1 -m "Lab 3 failed verification demo"
git push origin v1.0.1
```

Ожидаемая ошибка в job `Deploy and Verify`:

```text
[FAIL] nginx returned 200 for /health/alive; expected 404
```

Для отчета: screenshot или log failed `Deploy and Verify`.

После демонстрации вернуть target в нормальное состояние:

```bash
vagrant provision target
```

Или вручную восстановить `/etc/nginx/sites-available/mywebapp` из `deploy/templates/nginx-mywebapp.conf.template` и выполнить:

```bash
vagrant ssh target
sudo nginx -t
sudo systemctl reload nginx
exit
```

## 19. Что приложить в мини-отчет

Минимальный набор доказательств:

| Требование | Что показать |
| --- | --- |
| Успешный PR | PR с `Lint and Static Analysis` и `Tests and Coverage` passed, затем merge commit |
| Заблокированный PR | PR с failed check и disabled merge |
| Успешный CI | workflow `CI/CD` на `main` с jobs `lint`, `test`, `build` |
| Coverage | artifact `coverage-report` |
| GHCR image | package `ghcr.io/v14cl/devops-lab3` с tags `latest`, `sha-*`, `stable`, `v1.0.0` |
| Self-hosted runner | runner online в repository settings |
| Успешный deployment | log job `Deploy and Verify` |
| Failed verification | log failed verification, если требуется |
| Target service | `systemctl status mywebapp-container` |
| Nginx behavior | curl logs для `/`, `/notes`, `/health/alive` |
| Direct healthcheck | curl logs для `127.0.0.1:8000/health/alive` и `/health/ready` на target |

## 20. Частые проблемы

| Симптом | Причина | Что проверить |
| --- | --- | --- |
| `Deploy and Verify` не стартует | Нет online self-hosted runner | `Settings -> Actions -> Runners` |
| SSH connection failed | Public key runner-а не добавлен на target | `/home/mywebapp/.ssh/authorized_keys` |
| `docker pull` failed с GHCR | Package private или неправильный image | visibility package и `ghcr.io/v14cl/devops-lab3` |
| `mywebapp-container.service` не active | Контейнер не стартовал или image не скачался | `journalctl -u mywebapp-container -n 80 --no-pager` |
| `/health/alive` через nginx возвращает `200` | Nginx config пропускает health endpoints наружу | `/etc/nginx/sites-available/mywebapp` |
| `dotnet format` failed | Есть форматирование C# не по правилам SDK | локально выполнить `dotnet format devops-lab3.sln` |
| Coverage failed | line coverage ниже `40%` | добавить тесты или вернуть удаленные tests |
| Release tag failed на проверке tag type | Создан lightweight tag | удалить tag и создать `git tag -a` |

## 21. После сдачи

Self-hosted runner в публичном репозитории нельзя оставлять постоянно включенным.

Остановить runner VM:

```bash
vagrant halt runner
```

Или удалить VM:

```bash
vagrant destroy runner
```

Также можно удалить runner в GitHub:

```text
Settings -> Actions -> Runners -> <runner> -> Remove
```
