*This project has been created as part of the 42 curriculum by malaamir.*

## Description

### Project description

Inception is a small **Docker Compose** infrastructure that runs **NGINX** (TLS termination), **WordPress with PHP-FPM**, and **MariaDB** in separate containers on a private bridge network. The goal is to practice container networking, persistent storage, TLS, and process lifecycle (PID 1, graceful shutdown).

**Docker in this repo:** images are built from local **Dockerfiles** (Debian base only from the registry; application images are built locally). Sources live under **`srcs/`**: `docker-compose.yml` defines services, the custom bridge **network**, and **named volumes** for WordPress files and the MariaDB datadir. **Design choices:** single public entry (**HTTPS / 443**), FastCGI to **PHP-FPM** over the internal network, **MariaDB** not published to the host, and **persistent data** under `/home/<login>/data` via Compose volume configuration.

### Virtual Machines vs Docker

A **VM** runs a full guest OS on emulated hardware; each VM has its own kernel and higher overhead. **Docker** runs containers as isolated processes on the **host kernel** (namespaces for view, cgroups for limits), sharing the kernel and starting much faster. Containers package the app and its dependencies without shipping a whole OS.

### Secrets vs Environment Variables

**Environment variables** are convenient for configuration and are injected at runtime (e.g. from a `.env` file read by Compose). They can appear in process listings and inspect output, so they are not ideal for highly sensitive values in production. **Docker secrets** (or external secret stores) mount sensitive material as files in memory and reduce accidental exposure in images and logs. This project uses a **local `.env` file** for development (must stay **out of Git**); production-style setups would prefer secrets for passwords.

### Docker Network vs Host Network

A **custom bridge network** gives each container a stable DNS name (service name), isolated from the host’s main interfaces unless you publish ports. **`network: host`** shares the host network namespace (no isolation, port collisions, harder TLS routing). The subject forbids `network: host`; this project uses a **named bridge network** (`inception_network`).

### Docker Volumes vs Bind Mounts

A **named volume** is managed by Docker (metadata under Docker’s storage, lifecycle via `docker volume`). A **bind mount** maps a specific host path into a container. The subject requires **named volumes** for WordPress and MariaDB data and that persisted data lives under **`/home/<login>/data`** on the host for evaluation checks. This repository uses **named volumes** with a **local bind driver** so data resolves under that path while still appearing as named volumes in `docker volume ls` (confirm with your campus whether this satisfies the “no bind mounts” wording).

## Instructions

1. **Prerequisites:** Docker Engine and Docker Compose v2, Linux VM as required by the subject.
2. **Host layout:** Ensure `/home/<your_login>/data/wordpress` and `/home/<your_login>/data/mariadb` exist (the `Makefile` creates them on `make up`).
3. **Configuration:** Copy `srcs/.env.example` to `srcs/.env` and set `DOMAIN_NAME`, database credentials, WordPress users, and `HOST_VOLUME_PATH` (must be `/home/<your_login>/data`). **Do not commit `srcs/.env`.**
4. **DNS:** Map `DOMAIN_NAME` (e.g. `<login>.42.fr`) to your VM IP (e.g. `/etc/hosts` on the VM and evaluation machine as required).
5. **Run:** From the repository root:
   - `make` or `make up` — build and start the stack in the background.
   - `make down` — stop and remove containers (volumes kept).
   - `make clean` — stop and remove the local data directory (destructive).
   - `make re` — `clean` then bring the stack up again.
6. **Access:** Open `https://<login>.42.fr` in a browser (HTTPS only; expect a warning for the self-signed certificate). WordPress should already be installed by the entrypoint script (no install wizard if volumes were empty on first run).

For day-to-day operation and defense checks, see **USER_DOC.md**. For developers, see **DEV_DOC.md**.

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose specification](https://docs.docker.com/compose/compose-file/)
- [NGINX SSL termination](https://nginx.org/en/docs/http/configuring_https_servers.html)
- [WordPress Codex / Developer Resources](https://developer.wordpress.org/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [PHP-FPM](https://www.php.net/manual/en/install.fpm.php)

### Use of AI

AI tools were used to speed up repetitive tasks (drafting configuration comments, cross-checking Compose/YAML structure, and outlining documentation sections). All YAML, shell scripts, Dockerfiles, and runtime behavior were **reviewed and tested manually**; architectural choices (TLS-only NGINX, PHP-FPM on TCP 9000, named volumes, network layout) follow the subject and peer-evaluation criteria.
