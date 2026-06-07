<h1>Лабораторна робота 3</h1>

<h3>Макоткін Владислав ІМ-43</h3>

Посилання на документацію

- [Розрахунок варіанту](./lab1/docs/variant.md)

- [Розроблений веб-застосунок](./lab1/docs/app.md)

- [Розгортання](./lab1/docs/deploy.md)

- [Лабораторна робота 3: CI/CD та оформлення в GitHub](./LAB3_REPORT.md)

# devops-lab3

Notes Service for DevOps Lab 3.

## Application

`mywebapp` stores text notes in PostgreSQL and is exposed through nginx:

client -> nginx:80 -> mywebapp:8000 -> PostgreSQL

API:

| Method | Path | Result |
| --- | --- | --- |
| GET | `/` | HTML list of business endpoints |
| GET | `/notes` | note ids and titles |
| POST | `/notes` | creates a note from `title` and `content` |
| GET | `/notes/{id}` | full note data |
| GET | `/health/alive` | `OK` |
| GET | `/health/ready` | `OK` if PostgreSQL is reachable |

## Docker Run

```bash
cd lab1
docker compose up --build
```

The service is available at http://localhost when port 80 is free.

## VM Deployment

Tested target: Ubuntu Server 24.04, 1 CPU, 2 GB RAM, 10 GB disk.

Recommended VM access:

```bash
ssh student@localhost -p 2222
```

Run the installer:

```bash
cd lab1/scripts
sudo ./setup.sh
```

## Checks

```bash
curl http://localhost/
curl http://localhost/notes
curl -X POST http://localhost/notes
curl http://localhost/notes/1
curl http://localhost/health/alive
curl http://localhost/health/ready
docker network ls
docker volume ls
```

CI/CD demo: successful pull request.
deploy success demo
