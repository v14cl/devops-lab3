# Розгортання

## Лабораторна робота 1

### Середовище для VM

Для перевірки використовувалась VM з Ubuntu Server 24.04.

Рекомендовані ресурси:

| Ресурс | Значення |
| --- | --- |
| CPU | 1 vCPU |
| RAM | 2 GB |
| Disk | 10 GB або більше |

Мережа налаштовується через NAT. Для зручної роботи можна пробросити порти:

| Сервіс | Host port | Guest port |
| --- | --- | --- |
| SSH | `2222` | `22` |
| nginx | `8080` | `80` |

### Запуск встановлення

Підключитися до VM можна через консоль VirtualBox або SSH.

```bash
sudo apt-get install openssh-server
```

Далі потрібно отримати репозиторій та запустити єдину точку входу автоматизації:

```bash
git clone https://github.com/v14cl/devops-lab3.git
cd devops-lab3/lab1/scripts
sudo ./setup.sh
```

Скрипт встановлює потрібні пакети, створює користувачів, налаштовує PostgreSQL, nginx, systemd unit/socket для `mywebapp`, створює конфігурацію `/etc/mywebapp/config.json` та файл `/home/student/gradebook`.

### Перевірка після встановлення

Перевірити, що systemd-сервіси запущені:

```bash
systemctl status mywebapp.service
systemctl status mywebapp.socket
systemctl status nginx
systemctl status postgresql
```

Перевірити nginx з VM:

```bash
curl -i http://localhost/
curl -i http://localhost/notes
```

Якщо використовується port forwarding `8080 -> 80`, з host-машини застосунок відкривається так:

```bash
curl -i http://localhost:8080/
```

Health endpoints для Lab 1 перевіряються напряму на локальному порту застосунку:

```bash
curl -i http://127.0.0.1:8000/health/alive
curl -i http://127.0.0.1:8000/health/ready
```

Перевірити PostgreSQL:

```bash
sudo -u postgres psql -d mywebappdb -c '\dt'
sudo -u postgres psql -d mywebappdb -c '\di'
```

Перевірити файл для оцінювання:

```bash
cat /home/student/gradebook
```

Очікуване значення:

```text
3
```

## Лабораторна робота 2

### Запуск контейнерів

Перед запуском потрібні Docker та Docker Compose.

```bash
git clone https://github.com/v14cl/devops-lab3.git
cd devops-lab3/lab1
docker compose up --build
```

У Compose запускаються три сервіси:

| Сервіс | Призначення |
| --- | --- |
| `nginx` | reverse proxy |
| `mywebapp` | web application |
| `postgres` | база даних |

### Перевірка Docker-розгортання

Список контейнерів:

```bash
docker ps
docker compose ps
```

Перевірка роботи nginx:

```bash
curl -i http://localhost/
```

Перевірка API:

```bash
curl http://localhost/notes
curl -X POST http://localhost/notes
curl http://localhost/notes/1
```

Перевірка health endpoints:

```bash
curl http://localhost/health/alive
curl http://localhost/health/ready
```

Перевірка окремої Docker network:

```bash
docker network ls
```

Перевірка Docker volume для PostgreSQL:

```bash
docker volume ls
```

Щоб перевірити persistence, потрібно створити нотатку, перезапустити контейнери та знову отримати список нотаток:

```bash
curl -X POST http://localhost/notes
docker compose restart
curl http://localhost/notes
```
