# Inception — User documentation

This document is for **end users** and **administrators** who run the stack on a VM.

## What the stack provides

| Service   | Role |
|-----------|------|
| **nginx** | HTTPS entrypoint (port **443** only). TLS termination, static files from the WordPress volume, PHP requests forwarded to PHP-FPM. |
| **wordpress** | **WordPress** + **PHP-FPM** (FastCGI on port 9000 inside the container). Not exposed directly to the host. |
| **mariadb** | **MariaDB** database for WordPress. Port 3306 only inside the Docker network. |

Containers are attached to a private **bridge network** so they reach each other by service name (`wordpress`, `mariadb`, `nginx`).

## Start and stop the project

From the **repository root** (where the `Makefile` is):

```bash
make up      # default target `make` runs the same rule
make down    # stop and remove containers (named volumes are kept)
make clean   # stop containers and delete host data under HOST_VOLUME_PATH (irreversible)
make re      # clean then up — full reset of local data and fresh install on next boot
```

## Access the website and WordPress admin

1. Set `DOMAIN_NAME` in `srcs/.env` to `<your_login>.42.fr` and point that name to your VM (hosts file or DNS as required by your environment).
2. Open **`https://<your_login>.42.fr`** in a browser. Use **HTTPS** only; HTTP on port 80 is not exposed for the site.
3. Accept the **self-signed certificate** warning if prompted.
4. **Administration:** go to **`https://<your_login>.42.fr/wp-admin`**. Sign in with the **administrator** username and password you defined in `srcs/.env` (`WP_ADMIN_USER` / `WP_ADMIN_PASSWORD`). The administrator name must **not** contain `admin` or `Admin` (subject rule).
5. A second user (`WP_USER`) exists for normal content tasks (e.g. comments as an author).

## Credentials and where they live

- All secrets and site-specific variables are in **`srcs/.env`** on the machine (created from **`srcs/.env.example`**). That file must **not** be committed to Git.
- Database: `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`.
- WordPress: `WP_ADMIN_*`, `WP_USER_*`, `DOMAIN_NAME`.
- To **rotate** credentials: edit `srcs/.env`, then for a full re-provision you typically need `make re` (destroys existing DB and files under your data path) or manual DB/user updates — plan accordingly.

## Check that services are running

```bash
docker compose -f srcs/docker-compose.yml ps
```

All three services should show as **running**. To see logs for one service:

```bash
docker compose -f srcs/docker-compose.yml logs -f nginx
docker compose -f srcs/docker-compose.yml logs -f wordpress
docker compose -f srcs/docker-compose.yml logs -f mariadb
```

To confirm **named volumes** and host paths (evaluation-style check):

```bash
docker volume ls
docker volume inspect srcs_mariadb_data
docker volume inspect srcs_wordpress_data
```

Look for your configured host path under `/home/<login>/data/` in the volume metadata, as required by the subject.

## TLS

The site uses **TLS 1.2 and 1.3** only (see NGINX SSL configuration). The certificate is **self-signed** unless you replace it with your own.
