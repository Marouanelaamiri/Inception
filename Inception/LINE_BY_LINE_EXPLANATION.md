# Inception: line-by-line explanation (expanded, plain English)

This document walks through the Inception-style stack **step by step**. It explains **what each part does**, **why it exists**, and **how it connects** to the rest. Wording is deliberately simple; technical terms are introduced when needed.

**How to read this:** skim the architecture once, then follow the order **Makefile → docker-compose → Dockerfiles → configs → setup scripts**. That matches how the system is built and started.

---

## Part A — Big picture 
### What you are running

You have **three separate programs**, each in its **own container**:

1. **MariaDB** — stores rows and tables for WordPress.  
2. **WordPress + PHP-FPM** — runs PHP and generates HTML; talks to MariaDB.  
3. **Nginx** — the **front door**: HTTPS on port **443**, serves some files directly, sends PHP work to WordPress.

They share a **private Docker network** so they can call each other by **name** (`mariadb`, `wordpress`, `nginx`) without hardcoding IP addresses.

They share **two persistent volumes** (conceptually: “USB sticks that survive container deletion”) for:

- **WordPress files** (themes, uploads, `wp-config.php`, etc.)  
- **MariaDB data files** (the actual database on disk)

### ASCII architecture (host + Docker)

```
┌─────────────────────────────────────────────────────────────┐
│ YOUR LINUX VM (the “host”)                                  │
│                                                             │
│  Browser / curl  ──►  host port 443  (HTTPS only)           │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Docker: custom bridge network                       │   │
│  │  (e.g. inception_network)                            │   │
│  │                                                      │   │
│  │   ┌─────────┐      ┌─────────────┐      ┌──────────┐ │   │
│  │   │  nginx  │ ──►  │  wordpress  │ ──►  │ mariadb  │ │   │
│  │   │  :443   │      │  PHP-FPM    │      │  :3306   │ │   │
│  │   │  TLS    │      │  :9000      │      │          │ │   │
│  │   └─────────┘      └─────────────┘      └──────────┘ │   │
│  │        │                   │                 │       │   │
│  └────────┼───────────────────┼─────────────────┼───────┘   │
│           │                   │                 │           │
│           └───────┬───────────┴─────────┬───────┘           │
│                   ▼                     ▼                   │
│     named volumes backed by host paths under                │
│     /home/<your_login>/data/wordpress  and .../mariadb      │
└─────────────────────────────────────────────────────────────┘
```

**Plain English data path for one page view:**

1. User opens `https://<login>.42.fr` (TLS to nginx).  
2. Nginx decrypts TLS, finds the file or PHP route.  
3. If PHP is needed, nginx speaks **FastCGI** to `wordpress:9000`.  
4. PHP runs WordPress; WordPress opens SQL to `mariadb:3306`.  
5. MariaDB reads/writes its files on the **database volume**.  
6. HTML goes back: WordPress → nginx → browser.

---

## Part B — Mini glossary

| Term | Simple meaning |
|------|----------------|
| **Image** | A packaged filesystem + default command: a **template** for containers. Built from a **Dockerfile**. |
| **Container** | A **running instance** of an image, plus a thin writable layer and your mounts. |
| **Dockerfile** | Recipe: `FROM`, then `RUN`/`COPY` steps that stack **layers** into an image. |
| **Compose file** | YAML that says: build/run these services, attach this network, mount these volumes. |
| **Volume** | Storage that **outlives** a normal container filesystem so data persists. |
| **Bridge network** | A virtual LAN inside Docker; **DNS** turns service names into IPs. |
| **TLS / HTTPS** | Encrypted HTTP; nginx terminates TLS in this project. |
| **FastCGI** | A binary protocol nginx uses to ask PHP-FPM to execute a `.php` file. |
| **`exec`** (in shell) | Replace the shell process with the real server so it becomes **PID 1** and handles Docker stop signals correctly. |

---

## Part C — Makefile (`Makefile` at repo root)

**Purpose in one sentence:** you type short commands (`make`, `make down`) instead of long `docker compose -f srcs/docker-compose.yml …` lines every time.

---

### `DATA_DIR := /home/malaamir/data`

- **What:** A Make variable named `DATA_DIR`.  
- **`:=`** means “expand the right side **once** when defined” (simple assignment).  
- **Why `/home/...`:** the 42 subject expects persistent data under **`/home/<login>/data`**. Replace `malaamir` with your own login on your machine.  
- **In plain English:** “this is the **parent folder** on the real Linux disk where WordPress and MariaDB host directories will live.”

---

### `WP_DIR := $(DATA_DIR)/wordpress` and `DB_DIR := $(DATA_DIR)/mariadb`

- **`$(DATA_DIR)`** is Make’s way of pasting the value of `DATA_DIR` into a longer path.  
- **Why two folders:** one tree for **website files**, one for **database files**. Easier backups and mental model; Compose’s volume `device:` paths point here.  
- **Plain English:** “before Docker mounts anything, the host directories must exist.”

---

### `COMPOSE := docker compose -f srcs/docker-compose.yml`

- **What:** A reusable string for the Compose **CLI** with an explicit **`-f`** file path.  
- **Why:** your `docker-compose.yml` lives in **`srcs/`**, not the default name at repo root.  
- **Result:** `$(COMPOSE) up` becomes `docker compose -f srcs/docker-compose.yml up`.  
- **Note:** this is **Docker Compose v2** syntax (`docker compose`), not the old standalone `docker-compose` binary.

---

### `all: up`

- **What:** the **default goal** when you run `make` with no target.  
- **Depends on:** `up` — Make runs `up`’s recipe.  
- **Plain English:** “when I say `make`, I mean bring the stack **up**.”

---

### The `up:` target

```makefile
up:
	@mkdir -p $(WP_DIR)
	@mkdir -p $(DB_DIR)
	$(COMPOSE) up --build -d
```

**Tab characters matter** in Makefiles: recipe lines must start with a tab.

**Line 1: `@mkdir -p $(WP_DIR)`**

- **`mkdir -p`:** create the directory and any missing parents; do **not** error if it already exists.  
- **`@` in front:** do **not** print the command line before running it (quieter log).  
- **Why before compose:** your Compose volumes use **bind-backed named volumes** whose `device:` path must exist on the host.

**Line 2: `@mkdir -p $(DB_DIR)`** — same idea for MariaDB’s host folder.

**Line 3: `$(COMPOSE) up --build -d`**

- **`up`:** create networks/volumes if needed, create/start containers.  
- **`--build`:** (re)build images from Dockerfiles so code changes get picked up.  
- **`-d`:** **detached** — containers keep running in the background; your terminal returns.  
- **Plain English:** “build if needed, then start everything and leave it running.”

---

### `down:`

```makefile
down:
	$(COMPOSE) down
```

- **What:** stops and **removes** the containers created by this Compose project.  
- **Default:** named volumes are **not** removed (your data under `/home/.../data` stays).  
- **Plain English:** “turn the lights off, keep the furniture.”

---

### `clean:`

```makefile
clean:
	$(COMPOSE) down
	sudo rm -rf $(DATA_DIR)
```

- **First line:** same as `down`.  
- **Second line:** delete the whole `DATA_DIR` tree on the host.  
- **Why `sudo`:** files under those paths may be owned by root after containers wrote as root/mysql.  
- **Warning:** this is **destructive**. Next `make up` is a “first install” again for DB + WP files.

---

### `re:`

```makefile
re: clean
	$(MAKE) up
```

- **What:** run **`clean`’s recipe first**, then run **`up`**.  
- **`$(MAKE) up`:** preferred over a bare `make up` inside Makefiles (handles flags/jobserver correctly).  
- **Plain English:** “factory reset data, then start fresh.”

---

### `.PHONY: all up down clean re`

- **What:** tells Make these targets are **not** real filenames.  
- **Why:** if a file named `up` existed, Make might refuse to run the `up` recipe without `.PHONY`.  
- **Plain English:** “these names are **commands**, not files.”

---

## Part D — `srcs/docker-compose.yml`

**Purpose:** declare **three services**, **two named volumes**, **one network**, and how they plug together.

---

### Top-level `volumes:` (named volumes with bind `device`)

```yaml
volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOST_VOLUME_PATH}/mariadb
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOST_VOLUME_PATH}/wordpress
```

**What each key means, slowly:**

- **`mariadb_data` / `wordpress_data`:** the **Compose volume names**. Services mount them by these names.  
- **`driver: local`:** store data on this machine (not a cloud plugin).  
- **`type: none` + `o: bind` + `device: ...`:** tell the local driver: “this named volume is really backed by **this exact host directory**.”

**Why people do this on Inception VMs:**

- Evaluators often check that data lives under **`/home/<login>/data`**.  
- Plain “anonymous Docker volume location” is often under `/var/lib/docker/...`, which is harder to align with the subject’s host path rule.

**Subject tension (you should know this for defense):** the PDF also says **bind mounts are not allowed** for those two storages, while requiring **named volumes** and host path under `/home/login/data`. Your file uses **named volumes** in Compose **with** a bind driver underneath. Some graders accept it; a strict reading may question it. That is a **policy** discussion, not a syntax error.

**`${HOST_VOLUME_PATH}`:** substituted from **`srcs/.env`** (Compose loads `.env` from the project directory when you run compose from `srcs/` or when env_file is used — your workflow sets this to e.g. `/home/malaamir/data`).

---

### Service: `mariadb`

```yaml
  mariadb:
    container_name: mariadb
```

- **Fixed name** `mariadb` becomes the **DNS hostname** other containers use (`mariadb:3306`).  
- Without `container_name`, Compose might generate a name like `srcs-mariadb-1` depending on project naming; then your WordPress config would need to match that.

```yaml
    build:
      context: ./requirements/mariadb
      dockerfile: Dockerfile
```

- **`context`:** the folder sent to the Docker daemon as build context (for `COPY`).  
- **`dockerfile`:** which file to use inside that folder.

```yaml
    image: mariadb:inception
```

- **Tags** the built result so `docker images` shows a friendly name. Subject wording often expects the **repository name** to match the **service name** (`mariadb`, `wordpress`, `nginx`).

```yaml
    restart: always
```

- **If the process crashes** or the **host reboots**, Docker tries to start the container again.  
- **Plain English:** “keep the database coming back.”

```yaml
    env_file:
      - .env
```

- Loads variables from **`srcs/.env`** into the container environment.  
- **Plain English:** “passwords and DB names are **not** baked into the image; they arrive at **runtime**.”

```yaml
    networks:
      - inception_network
```

- Attaches this container to your custom bridge.  
- **Plain English:** “put MariaDB on the private LAN with the others.”

```yaml
    volumes:
      - mariadb_data:/var/lib/mysql
```

- Mounts the named volume at MariaDB’s default **datadir** inside the container.  
- **Plain English:** “database bytes live on the volume, not only inside the throwaway container layer.”

---

### Service: `wordpress`

Same pattern as MariaDB for `build`, `image`, `restart`, `env_file`, `networks`.

```yaml
    volumes:
      - wordpress_data:/var/www/html
```

- **`/var/www/html`** is the usual web root; WordPress expects its files there.

```yaml
    depends_on:
      - mariadb
```

- **What Compose guarantees:** the **MariaDB container is started before** WordPress starts.  
- **What it does *not* guarantee:** MariaDB has **finished initializing** and is accepting connections.  
- **Race condition:** WordPress might run `wp` commands before SQL is ready. In your repo, **MariaDB’s** setup script uses `sleep 2` after `service mariadb start` during **first-time DB creation** — not WordPress. For day‑to‑day restarts, both sides skip init if data already exists, so the race is much rarer after first boot.

---

### Service: `nginx`

```yaml
    build:
      context: ./requirements/nginx
      dockerfile: Dockerfile
      args:
        DOMAIN_NAME: ${DOMAIN_NAME}
```

- **`args`:** **build-time** variables visible as `ARG` in the Dockerfile.  
- **Why:** the OpenSSL **certificate subject** (`CN=`) and `sed` on nginx config need the real domain when the **image** is built.

```yaml
    ports:
      - "443:443"
```

- Maps **host 443** to **container 443**.  
- **Subject angle:** only **443** is published for the web entry; no **80:80** mapping for HTTP in this design.

```yaml
    volumes:
      - wordpress_data:/var/www/html
```

- **Same volume as WordPress** so nginx can read **static files** (images, CSS) from disk and still forward PHP upstream.

```yaml
    depends_on:
      - wordpress
```

- Starts nginx after the WordPress **container** starts (again: not a guarantee PHP-FPM is listening yet, but order is usually fine in practice).

---

### `networks:`

```yaml
networks:
  inception_network:
    driver: bridge
```

- **Bridge:** the usual Linux bridge driver Docker uses for internal L2 networks.  
- **Embedded DNS:** resolves `wordpress`, `mariadb`, etc., to container IPs on that network.

---

## Part E — Nginx Dockerfile (`srcs/requirements/nginx/Dockerfile`)

**Goal:** an image that has nginx, TLS material, and your vhost config; main process is nginx in the foreground.

---

### `FROM debian:11`

- Start from Debian 11’s image layers.  
- **Subject note:** you must use the **penultimate stable** Debian or Alpine per the subject text at the time of your defense — verify the tag is still acceptable when you validate.

---

### `ARG DOMAIN_NAME`

- A **build-only** variable. Populated from Compose `build.args`.  
- It is **not** automatically a runtime env unless you also add `ENV`.

---

### `RUN apt-get update -y && apt-get install nginx openssl -y`

- **`update`:** refresh package index.  
- **`install nginx openssl`:** web server + tools to create certificates.  
- **One `RUN`:** one image layer containing all installed files (good for caching that chunk).

---

### `RUN mkdir -p /etc/nginx/ssl`

- Ensures the folder exists before `openssl` writes key/cert there.

---

### `RUN openssl req -x509 ...`

**Piece by piece:**

- **`req`:** certificate request / generation utility.  
- **`-x509`:** output a **self-signed** certificate instead of a CSR for a public CA.  
- **`-nodes`:** do not encrypt the private key with an extra passphrase (avoids interactive prompt in build).  
- **`-days 365`:** validity window.  
- **`-newkey rsa:2048`:** create a new RSA key pair.  
- **`-keyout` / `-out`:** where to write private key and certificate.  
- **`-subj ... CN=${DOMAIN_NAME}`:** put your domain in the cert’s Common Name field (browsers use CN/SAN for identity checks).

**Plain English:** “bake a dev certificate into the image so HTTPS works immediately.”

---

### `COPY conf/nginx.conf /etc/nginx/sites-available/default`

- Replace Debian’s default site file with yours.  
- **Still contains** `DOMAIN_NAME_PLACEHOLDER` until the next line fixes it.

---

### `RUN sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/g" ...`

- **`sed -i`:** edit file in place.  
- **`s/old/new/g`:** substitute every occurrence.  
- **Why not put the domain only in Compose?** you need nginx’s `server_name` to match what clients send in **TLS SNI** / `Host:` headers.

---

### `EXPOSE 443`

- **Documentation** for humans and some tools. **Publishing** is still done in Compose `ports:`.

---

### `CMD ["nginx", "-g", "daemon off;"]`

- **JSON form** = exec form (no shell wrapper).  
- **`daemon off;`:** nginx stays in the **foreground** so Docker tracks one main process.  
- **Plain English:** “if nginx goes to background daemon mode, Docker may think the container is done and exit.”

---

## Part F — WordPress Dockerfile (`srcs/requirements/wordpress/Dockerfile`)

**Goal:** PHP-FPM + WP-CLI + your pool config + startup script; final PID 1 should be php-fpm after `exec`.

---

### `RUN apt-get ... php7.4-fpm php7.4-mysql wget`

- **`php7.4-fpm`:** FastCGI worker pool.  
- **`php7.4-mysql`:** PHP’s MySQL/MariaDB driver so WordPress can talk SQL.  
- **`wget`:** fetch WP-CLI phar.

---

### `RUN wget ... wp-cli.phar ...`

- Installs **WP-CLI** to `/usr/local/bin/wp` so `setup.sh` can run `wp core download`, `wp config create`, etc., **without** clicking through the web installer.

---

### `RUN mkdir -p /run/php`

- Debian PHP-FPM expects runtime paths; missing dirs can cause startup failure.

---

### `COPY conf/www.conf ...`

- Your pool listens on **TCP 9000** so nginx in **another container** can connect. A Unix **socket** file would not be visible across containers the same way.

---

### `COPY tools/setup.sh` + `RUN chmod +x`

- Put the entry script in the image and mark executable.

---

### `CMD ["/usr/local/bin/setup.sh"]`

- Container starts by running the script; script ends with **`exec php-fpm7.4 -F`** so FPM replaces the shell as PID 1.

---

## Part G — MariaDB Dockerfile (`srcs/requirements/mariadb/Dockerfile`)

**Goal:** MariaDB server + custom `mysql.cnf` + init script; long-running process is `mysqld_safe` via `exec`.

---

### `RUN apt-get ... mariadb-server`

- Installs the database engine and client tools used in setup.

---

### `RUN mkdir -p /var/run/mysqld && chown -R mysql:mysql ...`

- MariaDB’s default user is **`mysql`**; socket/pid paths must be writable.

---

### `COPY conf/mysql.cnf ...`

- Ships your tuning; critical piece is often **`bind-address = 0.0.0.0`** so connections are accepted from the Docker network, not only literal `localhost` inside the same container.

---

### `CMD ["/usr/local/bin/setup.sh"]`

- Same pattern as WordPress: init once, then `exec mysqld_safe`.

---

## Part H — `nginx.conf` (`srcs/requirements/nginx/conf/nginx.conf`)

**Goal:** one `server { }` block for HTTPS, WordPress root, pretty permalinks, PHP to FPM.

---

### `server { listen 443 ssl; server_name ... }`

- **`443 ssl`:** only HTTPS listener in this file.  
- **`server_name`:** which hostname this block answers for (after placeholder replacement).

---

### SSL directives

- **`ssl_certificate` / `ssl_certificate_key`:** paths to the files generated in the image build.  
- **`ssl_protocols TLSv1.2 TLSv1.3;`:** forbid old broken protocols; allow modern clients.

---

### `root` and `index`

- **`root /var/www/html`:** document root is the mounted WordPress tree.  
- **`index ...`:** default filenames when a directory is requested.

---

### `location / { try_files ... }`

**Line by line behavior:**

1. Try exact file `$uri`.  
2. Try directory `$uri/`.  
3. Fall back to **`/index.php?$args`** — WordPress front controller pattern.

**Plain English:** “pretty URLs still end up running through WordPress’s `index.php`.”

---

### `location ~ \.php$ { ... }`

- Regex match for URLs ending in `.php`.  
- **`fastcgi_pass wordpress:9000;`:** send FastCGI to the **wordpress** service on **9000**.  
- **`include fastcgi_params;`:** standard CGI-like meta vars.  
- **`SCRIPT_FILENAME`:** full path to the PHP file on **this** container’s filesystem — nginx and WordPress share the **same volume mount path** (`/var/www/html`), so the path nginx computes is valid inside the WordPress container too.

---

## Part I — `www.conf` (PHP-FPM pool)

- **`[www]`:** pool section name.  
- **`user` / `group`:** drop privileges from root to `www-data` for worker processes.  
- **`listen = 9000`:** TCP listener for cross-container FastCGI.  
- **`pm = dynamic` + child counts:** how many PHP worker processes to keep ready under load vs idle — small numbers are fine for a school VM.

---

## Part J — `mysql.cnf` (MariaDB server)

- **`[mysqld]`:** server-only options.  
- **`user = mysql`:** run server as non-root after startup steps.  
- **`port = 3306`:** default MySQL wire protocol port.  
- **`datadir = /var/lib/mysql`:** where table files live (your volume mount point).  
- **`bind-address = 0.0.0.0`:** listen on all interfaces inside the container namespace so **wordpress** can connect over the bridge.

---

## Part K — WordPress `setup.sh` (`srcs/requirements/wordpress/tools/setup.sh`)

**Shebang `#!/bin/sh`**

- Script runs with POSIX shell (Dash on Debian), not bash-specific syntax.

---

### `cd /var/www/html`

- All `wp` commands operate in the web root on the volume.

---

### `if [ ! -f "wp-config.php" ]; then ... fi`

- **First boot:** no config file → download core, create config, install site, create second user.  
- **Later boots:** file exists → skip block; go straight to starting FPM.  
- **Plain English:** “install WordPress **once**, never wipe the volume accidentally on restart.”

---

### `wp core download --allow-root`

- Fetches WordPress PHP sources. **`--allow-root`:** WP-CLI normally refuses root; containers often run as root here.

---

### `wp config create ... --dbhost=mariadb`

- Writes `wp-config.php` with DB credentials from **environment variables** injected by Compose.  
- **`mariadb`:** must match **`container_name`** / service DNS name.

---

### `wp core install ... --url=https://${DOMAIN_NAME}`

- Creates database tables and the **admin** user.  
- **HTTPS URL:** avoids mixed-content surprises and matches how users reach the site.

---

### `wp user create ... --role=author`

- Second user for the subject; **author** can post/comment but is not a full administrator.

---

### `exec /usr/sbin/php-fpm7.4 -F`

- **`-F`:** foreground.  
- **`exec`:** shell becomes php-fpm → **correct PID 1** for signals.

---

## Part L — MariaDB `setup.sh` (`srcs/requirements/mariadb/tools/setup.sh`)

---

### `if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then ... fi`

- Heuristic: if that database directory does not exist on the volume, treat as **first init**.  
- **Caveat:** unusual if someone deletes only that subfolder; script might try re-init in a messy state.

---

### `service mariadb start`

- Starts MariaDB **temporarily** so `mysql` CLI can connect for SQL bootstrap.  
- **Plain English:** “spin up the engine briefly to run setup SQL.”

---

### `sleep 2`

- Crude wait for mysqld to accept connections. **Not a perfect readiness gate**, but simple.

---

### SQL lines (`CREATE DATABASE`, `CREATE USER`, `GRANT`, `ALTER USER`, `FLUSH PRIVILEGES`)

- **`CREATE USER ... @'%'`:** user may connect from **any host** — required because WordPress connects from **another container IP**, not `localhost` inside MariaDB.  
- **`GRANT ... ON db.*`:** app user only has rights on the WordPress schema.  
- **`ALTER USER root@localhost`:** sets a real root password instead of empty default.  
- **`FLUSH PRIVILEGES`:** apply grant tables immediately.

---

### `mysqladmin ... shutdown`

- Stops the **temporary** background server cleanly before the real long-run server starts.

---

### `exec mysqld_safe`

- Wrapper that starts **`mysqld`** and monitors it; **`exec`** makes it PID 1 for Docker lifecycle.

---

## Part M — Corrected “first `make up`” timeline

1. **Make** creates host dirs under `DATA_DIR`.  
2. **Compose build** builds three images (unless cached).  
3. **Containers start** with dependency order: **mariadb** → **wordpress** → **nginx**.  
4. **MariaDB first run:** `service mariadb start` → SQL setup → shutdown → `exec mysqld_safe` (foreground DB).  
5. **WordPress first run:** `wp` downloads and installs if `wp-config.php` missing → `exec php-fpm7.4 -F`.  
6. **Nginx:** serves TLS on 443, proxies PHP to **wordpress:9000**.  
7. **Browser:** `https://<login>.42.fr` hits nginx on the VM.

**Correction vs older drafts:** the **`sleep 2`** belongs to the **MariaDB** init path, **not** the WordPress script in your current repo.

---

## Part N — `.env` variables (names only; use your own secrets)

Compose reads **`srcs/.env`** for substitution and `env_file:` injection. **Never commit real passwords.**

Example shape (values are placeholders):

```env
HOST_VOLUME_PATH=/home/<login>/data
DOMAIN_NAME=<login>.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=<login>
MYSQL_PASSWORD=CHANGEME
MYSQL_ROOT_PASSWORD=CHANGEME_ROOT

# Admin username must NOT contain admin/Admin (subject).
WP_ADMIN_USER=<login>_owner
WP_ADMIN_PASSWORD=CHANGEME
WP_ADMIN_EMAIL=you@student.42.fr

WP_USER=editor_user
WP_USER_EMAIL=editor@example.com
WP_USER_PASSWORD=CHANGEME
```

---

## Part O — Debugging commands (expanded)

```bash
# Are containers up?
docker compose -f srcs/docker-compose.yml ps

# Follow logs (pick a service)
docker compose -f srcs/docker-compose.yml logs -f nginx
docker compose -f srcs/docker-compose.yml logs -f wordpress
docker compose -f srcs/docker-compose.yml logs -f mariadb

# Shell inside a container (use sh if bash not installed)
docker compose -f srcs/docker-compose.yml exec wordpress sh
docker compose -f srcs/docker-compose.yml exec mariadb sh

# DNS / reachability smoke tests
docker compose -f srcs/docker-compose.yml exec wordpress ping -c 2 mariadb

# Volumes (names depend on project directory name; often prefixed with folder name)
docker volume ls
docker volume inspect srcs_mariadb_data
docker volume inspect srcs_wordpress_data

# Inspect certificate subject
docker compose -f srcs/docker-compose.yml exec nginx openssl x509 \
  -in /etc/nginx/ssl/inception.crt -text -noout

# Confirm WordPress sees DB settings (avoid pasting secrets in screenshots)
docker compose -f srcs/docker-compose.yml exec wordpress grep DB_ /var/www/html/wp-config.php

# Tables exist?
docker compose -f srcs/docker-compose.yml exec mariadb \
  mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SHOW TABLES;"
```

---

## Part P — Summary table (why each file exists)

| Piece | Role in plain English |
|------|------------------------|
| **Makefile** | Short commands; ensures host data dirs exist; wraps `docker compose -f srcs/docker-compose.yml`. |
| **docker-compose.yml** | Defines **3 services**, **2 volumes**, **1 network**, **443** publish, build args for nginx. |
| **nginx Dockerfile + nginx.conf** | TLS + static files + FastCGI to WordPress. |
| **wordpress Dockerfile + www.conf + setup.sh** | PHP-FPM on **9000**; automated WP install; `exec` to FPM. |
| **mariadb Dockerfile + mysql.cnf + setup.sh** | DB reachable on network; first-time SQL; `exec` to `mysqld_safe`. |
| **Host paths + volumes** | Keep MariaDB and WordPress files across container recreation. |


