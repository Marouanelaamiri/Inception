# Inception — Developer documentation

## Prerequisites

- **Linux VM** (as required by the subject).
- **Docker** with **BuildKit** enabled as usual, and **Docker Compose v2** (`docker compose`).
- Sudo rights if you use `make clean` (removes the data directory under `/home/<login>/data`).
- **No passwords or API keys in Git.** Use `srcs/.env.example` as a template only.

## Repository layout

```
.
├── Makefile                 # wraps docker compose
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
└── srcs/
    ├── docker-compose.yml   # services, networks, volumes
    ├── .env                 # local only — gitignored
    ├── .env.example         # template for peers / CI
    └── requirements/
        ├── nginx/
        ├── wordpress/
        └── mariadb/
```

Each service has its **own Dockerfile** under `srcs/requirements/<service>/`.

## Configuration and secrets

1. Copy `srcs/.env.example` to `srcs/.env`.
2. Set at least:
   - `DOMAIN_NAME` — `<login>.42.fr`
   - `HOST_VOLUME_PATH` — `/home/<login>/data`
   - MariaDB and WordPress variables (see example file).
3. Ensure directories exist (or let `make up` create them):

```bash
mkdir -p /home/<login>/data/wordpress /home/<login>/data/mariadb
```

## Build and run (Makefile)

| Target   | Action |
|----------|--------|
| `make` / `make up` | `mkdir` data dirs, `docker compose up --build -d` |
| `make down`        | `docker compose down` |
| `make clean`       | `docker compose down` + `sudo rm -rf $(DATA_DIR)` |
| `make re`          | `clean` then `make up` |

Compose file path: `srcs/docker-compose.yml`. The Makefile sets:

```text
docker compose -f srcs/docker-compose.yml ...
```

## Docker Compose commands (reference)

From repo root:

```bash
docker compose -f srcs/docker-compose.yml config    # validate YAML
docker compose -f srcs/docker-compose.yml build
docker compose -f srcs/docker-compose.yml up -d
docker compose -f srcs/docker-compose.yml down
docker compose -f srcs/docker-compose.yml logs -f
```

## Containers and images

- **Image names** match service names with a tag: `nginx:inception`, `wordpress:inception`, `mariadb:inception`.
- **Base image:** Debian (pin aligned with the subject’s “penultimate stable” rule — verify the tag at defense time).
- **Forbidden by subject:** pulling ready-made app images from Docker Hub for the three services; `FROM debian:…` is the allowed base.

## Data persistence

- **WordPress files:** named volume `wordpress_data` → mounted at `/var/www/html` in **wordpress** and **nginx**.
- **MariaDB data:** named volume `mariadb_data` → `/var/lib/mysql` in **mariadb**.
- Volume definitions use `HOST_VOLUME_PATH` so evaluation can find data under **`/home/<login>/data/`** when inspecting volumes.

After a VM reboot, run `make up` again; data should persist if the host directories and volume definitions are unchanged.

## Networking

- Custom bridge: **`inception_network`**.
- **No** `network: host`, **no** `links:` / `--link`.

## Entrypoints and PID 1

- **NGINX:** `CMD ["nginx", "-g", "daemon off;"]` — nginx is PID 1.
- **WordPress / MariaDB:** shell scripts end with **`exec`** into `php-fpm` or `mysqld_safe` so the main process receives signals correctly.

## TLS

Certificate is generated at **image build** time from `DOMAIN_NAME` (build arg). Regenerate by rebuilding the nginx image after changing the domain.
