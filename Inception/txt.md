# Inception 

### What is an image?

An image is a **read-only template** for running a container. It is **not** a single big file in the naive sense; internally it is a **stack of filesystem layers** plus **metadata** (default command, exposed ports, labels, environment defaults, etc.).

- **Immutable:** once built, those layers are not edited in place; a “change” means a **new** build producing new layer IDs on top or replacing the tag.
- **Layers:** each layer is a set of filesystem **deltas** (add/modify/delete files) on top of the parent. Docker merges them with an **overlay** (e.g. overlay2) so the container sees one unified `/` tree.

### What is a container?

A container is a **running** (or created-but-stopped) instance of an image. At minimum:

- It uses **all image layers** (read-only).
- Docker adds one **thin writable layer** on top for anything that changes at runtime (logs, temp files, writes **outside** mounted volumes).

So: **image = recipe + frozen filesystem**; **container = that frozen stack + live writes**.

### What is a Dockerfile?

A text file that lists **instructions** (`FROM`, `RUN`, `COPY`, …). It is **not** literally a shell script for the whole file, though `RUN` can execute shell commands.

- **`docker build`** (or `docker compose build` / `up --build`) reads the Dockerfile and produces an **image**.
- Each instruction that changes the filesystem typically creates or contributes to **cacheable** build steps.

Typo fix: think “**build recipe**”, not “shell script for the whole image” — only `RUN` lines run arbitrary commands.

### What is Docker Compose?

A **YAML** file (`docker-compose.yml`) declares **services** (containers you want), **networks**, **volumes**, sometimes **configs**. One command (`docker compose up`) can:

- **Build** images from Dockerfiles (if `build:` is set).
- **Create** networks and volumes.
- **Start** containers with the right env, mounts, ports, and dependencies.

Instead of many long `docker run …` commands, you describe the **desired state** once.

### What is a volume?

A **mount** that stores data **outside** the container’s writable layer (and usually **outside** the image). Typical uses: database files, WordPress `wp-content`, uploads.

- If the container is removed, **volume data normally stays** (unless you use `docker compose down -v` or delete the volume explicitly).
- The container’s **writable layer** is discarded when the container is removed; that is why “ephemeral container filesystem” is a common phrase.

---

## 2. Dockerfile → image → container → “deploy”

### Does a Dockerfile build an image?

**Yes.** The Dockerfile is the **input**. The **output** of a successful build is one **image** (identified by an image ID; you also tag it, e.g. `nginx:inception`).

### When we deploy, do we deploy the “ready” image?

**Usually you deploy by running containers from an image** (plus config: env, secrets, volumes, ports). Exact workflow depends on the environment:

| Workflow | What happens |
|----------|----------------|
| **Inception / local VM** | `make` or `docker compose up --build` often **builds on the same machine**, then **starts** containers. The “artifact” you care about is the **image on disk** + **compose state**. |
| **CI/CD (typical prod)** | Pipeline **builds** the image, **pushes** to a registry; the server **pulls** the image and **runs** it. The Dockerfile might never exist on the server. |

So:

- **Build time:** Dockerfile + context → **image** (layers frozen).
- **Run time:** **image** + configuration → **container** (processes + writable layer + volume mounts).

**Deploy** in the loose sense = “make the app available”: that means **running** the right **containers** from the right **images**, not “shipping only a Dockerfile”.

---

## 3. Image layers — elaborate picture

### 3.1 Why layers exist

Layers let Docker:

1. **Reuse work:** If line 5 of the Dockerfile did not change, Docker can **reuse** the layer from cache instead of re-downloading or re-running expensive steps.
2. **Share storage:** Many images based on `debian:11` **share** the same bottom layers on disk.
3. **Transfer efficiently:** Registry pushes/pulls send **layer blobs** the other side does not already have.

### 3.2 What usually creates a filesystem layer

Rough mental model (BuildKit can optimize in edge cases, but this is fine for learning):

| Instruction | Typical effect |
|-------------|----------------|
| **`FROM`** | You **inherit** the entire layer stack of that base image. You do not “rebuild Debian from zero” in your Dockerfile; you **stack on top**. |
| **`RUN`** | New layer: result of everything that command wrote to the filesystem in that step. |
| **`COPY` / `ADD`** | New layer: files from build context (or remote URL for `ADD`) copied into the image. |
| **`ARG`** | Build-time variable available to later `RUN` lines; mostly affects **build**, not a huge layer by itself. |
| **`ENV`** | Sets environment metadata; may not add a large filesystem diff. |
| **`WORKDIR`** | Creates directory metadata if needed; small. |
| **`EXPOSE`** | **Documentation** only by default; does not publish ports to the host (Compose `ports:` does). |
| **`CMD` / `ENTRYPOINT`** | Default process metadata when a **container** starts; not “another full OS layer”. |

### 3.3 Union / overlay in one sentence

Each layer knows **only its diffs**. At runtime the kernel **overlays** them so path `/etc/nginx/nginx.conf` might come from layer 7 even if layer 3 also had an `/etc` directory — **upper** layers **hide** or **replace** files from lower layers.

### 3.4 Image vs container writable layer

- **Image layers:** read-only. Many containers can mount the same image.
- **Container writable layer:** copy-on-write. If a process writes to a file that came from an image layer, the modified file is stored in the **writable** layer (or in a **volume** if that path is mounted).

### 3.5 Cache order matters

Dockerfile order is a **pipeline**:

- Put **slow, rarely changing** steps early (`apt-get install`, install PHP, etc.).
- Put **fast, often changing** steps late (`COPY` your app code, small config tweaks).

If you `COPY . .` on line 3 and `RUN apt-get` on line 20, **any** file change invalidates cache for line 3 onward — you redo apt constantly. Bad.

### 3.6 Inspecting layers on your machine

After building (e.g. `nginx:inception`):

```bash
docker history nginx:inception
```

You see one row per instruction / layer contribution (sizes, creation commands). Good for linking **Dockerfile lines** ↔ **what ended up in the image**.

---

## 4. Inception — per-Dockerfile layer map (this repo)

Paths: `srcs/requirements/<service>/Dockerfile`.

### 4.1 NGINX

| Step | Instruction | What it adds to the story |
|------|-------------|---------------------------|
| Base | `FROM debian:11` | All layers of official `debian:11` become your floor. |
| Build arg | `ARG DOMAIN_NAME` | Value injected at **build** time (from Compose `build.args`). Used in `RUN openssl` and `RUN sed`. |
| Packages | `RUN apt-get … install nginx openssl` | Big layer: binaries, default configs, certs tooling. |
| SSL dir | `RUN mkdir -p /etc/nginx/ssl` | Small layer: directory tree. |
| Cert | `RUN openssl req …` | Layer with `inception.key` / `inception.crt`; **CN** tied to `DOMAIN_NAME` at build time. |
| Config | `COPY conf/nginx.conf …` | Your vhost template as default site. |
| Domain in config | `RUN sed -i …` | Layer replacing placeholder with real server_name / TLS server block content. |
| Metadata | `EXPOSE 443` | Documents intent; **publish** still done in Compose. |
| Runtime default | `CMD ["nginx", "-g", "daemon off;"]` | When a **container** starts, PID 1 should be **nginx** in foreground (`daemon off`). |

### 4.2 WordPress + PHP-FPM

| Step | Instruction | What it adds |
|------|-------------|----------------|
| Base | `FROM debian:11` | Same family of base layers as nginx. |
| PHP stack | `RUN apt-get … php7.4-fpm php7.4-mysql wget` | PHP-FPM, MySQL client bindings for PHP, wget. |
| WP-CLI | `RUN wget … wp-cli.phar` → `/usr/local/bin/wp` | CLI for scripted WP install in `setup.sh`. |
| Runtime dir | `RUN mkdir -p /run/php` | PHP-FPM PID/socket expectations. |
| Pool | `COPY conf/www.conf …` | Listen on **TCP 9000** for FastCGI from nginx. |
| Entry script | `COPY tools/setup.sh` + `RUN chmod` | First boot: download WP, `wp config`, `wp core install`, second user; then `exec php-fpm -F`. |
| Default CMD | `CMD ["/usr/local/bin/setup.sh"]` | **Container start** runs script; script ends with **`exec`** so **php-fpm** becomes PID 1. |

Important: **WordPress site files** under `/var/www/html` are meant to live on the **named volume** at runtime, not only inside image layers — persistence and reinstall behavior depend on that.

### 4.3 MariaDB

| Step | Instruction | What it adds |
|------|-------------|----------------|
| Base | `FROM debian:11` | Base stack. |
| Server | `RUN apt-get … install mariadb-server` | `mysqld`, tools, default layout. |
| Run dir | `RUN mkdir … chown … /var/run/mysqld` | Socket/pid expectations. |
| Config | `COPY conf/mysql.cnf …` | e.g. `bind-address`, `datadir` under `/var/lib/mysql`. |
| Entry script | `COPY tools/setup.sh` + `RUN chmod` | First boot: init DB/users; then `exec mysqld_safe`. |
| Default CMD | `CMD ["/usr/local/bin/setup.sh"]` | Same **exec** pattern for graceful shutdown. |

**Data** in `/var/lib/mysql` should persist via the **MariaDB volume**, not by baking DB files into the image.

---

## 5. Core concepts

### 5.1 The container illusion (namespaces, cgroups)

A container is **not** a lightweight VM.//i was here 

- A **VM** runs a **guest OS** on emulated/virtual hardware with its **own kernel**.
- A **container** is mostly **normal processes** on the **host kernel**, with isolation **views** and **limits** applied by the kernel.

**Namespaces (isolation — what the process “sees”):**

- **PID:** nginx can be PID 1 **inside** the container even if it is not 1 on the host.
- **Network:** separate interfaces, routing table, ports; **docker0** / bridge connects containers.
- **Mount:** the container’s `/` is the merged image layers (+ writable layer + **volume mounts**), not the host’s `/`.

**Cgroups (limits — what the process may use):**

- CPU, memory, I/O caps so one bad container does not starve others.

**Syscall reality:** when MariaDB writes to its datadir, it still ends up as host kernel **open/write** on real block storage — often through a mount that **is** a Docker volume or overlay path. No full hardware virtualization in the VM sense.

### 5.2 Docker networking and internal DNS

By default, arbitrary containers do not share one flat “LAN” unless you attach them to the same user-defined network.

Your **Compose** file attaches `nginx`, `wordpress`, and `mariadb` to a **custom bridge** (e.g. `inception_network`). Docker provides an **embedded DNS** resolver (commonly seen as `127.0.0.11` inside containers).

- Service names (`wordpress`, `mariadb`) become **stable hostnames**.
- Container IPs can change on restart; **DNS** tracks the current IP for that name.

That is why `fastcgi_pass wordpress:9000;` and WordPress `DB_HOST=mariadb` work without hardcoding IPs.

### 5.3 PID 1 and signal handling

PID 1 inside the container namespace is special: when Docker stops the container, it sends **SIGTERM** to PID 1. The process should **exit cleanly** (flush DB, close connections).

**Anti-pattern:** `CMD ["sh", "-c", "mysqld_safe & sleep infinity"]` — shell is PID 1, DB is a child; signals and shutdown are messy. The subject explicitly discourages `tail -f`, `sleep infinity`, infinite loops as fake PID 1.

**Your pattern:** shell script runs setup, then **`exec mysqld_safe`** or **`exec php-fpm7.4 -F`** so the **database server** or **php-fpm** **replaces** the shell and becomes PID 1 — it receives SIGTERM directly.

---

## 6. Request path mindmap (HTTPS → WordPress → MariaDB)

1. **Browser →** `https://<login>.42.fr` on port **443** (TLS).
2. **Host →** published port maps to **nginx** container (Compose `ports: "443:443"`).
3. **Nginx →** terminates TLS; serves static files from the **shared WordPress volume** where possible.
4. **`.php` →** FastCGI to **`wordpress:9000`** (PHP-FPM).
5. **PHP / WordPress →** SQL to **`mariadb:3306`** on the internal network.
6. **MariaDB →** reads/writes datadir on its **volume**; returns rows; PHP builds HTML.
7. **Response →** back through nginx to the browser.

---

## 7. YAML (why Compose uses it)

YAML uses **indentation** to nest structures. A key like `services:` holds a mapping of service names to their configuration (`build`, `image`, `networks`, `volumes`, `ports`, …).

Compared to JSON: fewer braces; compared to XML: less noise. Good for human-maintained infrastructure files.

---

## 8. TLS and HTTPS (plain English)

**TLS** (*Transport Layer Security*) is the protocol that creates a **private, tamper‑evident tunnel** between your browser and the server **before** normal web data flows. **HTTPS** means: **HTTP carried inside TLS**. TLS sits on top of TCP; it is not “the web page” itself, it is the **secure pipe** the page travels through.

### What problem TLS solves

Traffic crosses Wi‑Fi, ISPs, routers, and datacenters. **Without TLS**, much of that would be **readable** to anyone who can tap the path. **With TLS**, eavesdroppers see **ciphertext**, not passwords, cookies, or page content in clear text.

### Three pillars (what TLS gives you)

1. **Encryption (secrecy)** — only the two endpoints should read the real content; everyone else sees noise.
2. **Integrity (anti‑tampering)** — if someone alters bytes in transit, the receiver detects it and aborts instead of trusting garbage.
3. **Authentication (who is the server?)** — the server presents a **certificate** (identity bound to a **public key**, usually tied to a **domain name**). The browser checks whether it **trusts** that certificate (chain to a known Certificate Authority). With a **self‑signed** cert (typical in Inception), the browser still **encrypts**, but shows a **warning** because it cannot verify the issuer everyone trusts.

TLS does **not** fix weak passwords leaked elsewhere, malware on your laptop, or a compromised server after data is decrypted there.

### The handshake (simplified story)

Think: **short negotiation**, then **one agreed secret** for fast bulk encryption.

1. **Client hello** — browser sends supported TLS versions, cipher families, random bytes.
2. **Server hello** — server picks a **TLS version** (prefer **1.3** if both support it, else **1.2**), sends its **certificate** and key‑exchange material.
3. **Key agreement** — both sides derive **session keys** without sending those keys in plaintext on the wire. After this, **symmetric** crypto handles the bulk of the session (fast).
4. **Finished** — both sides prove the handshake was not corrupted.
5. **Application data** — HTTP requests/responses flow **encrypted** for the rest of the connection.

Only **one** TLS version is used **per connection**. Listing both 1.2 and 1.3 in the server config means: “**allow** either; **never** old SSL / TLS 1.0 / 1.1.”

### TLS 1.2 vs TLS 1.3 (why both appear in nginx)

| | **TLS 1.2** | **TLS 1.3** |
|---|-------------|-------------|
| Role | Long‑supported default for many years | Newer, stricter, faster handshake in common cases |
| Compatibility | Older clients, libraries, or OS builds may stop at 1.2 | Modern browsers prefer it when available |
| Security posture | Fine when configured well; more legacy baggage existed in the ecosystem | Removes many obsolete weak options at the protocol level |

**Why configure both:** strict enough for the subject (**no ancient protocols**), still **compatible** with clients that only reach **1.3** or only **1.2**. Modern stacks negotiate **1.3** automatically when possible.

In this project, nginx pins that policy:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

(`srcs/requirements/nginx/conf/nginx.conf`.)

### One‑paragraph summary

TLS sets up **encrypted, integrity‑checked** communication and ties the connection to a **server identity** via certificates (with a self‑signed warning in dev). **1.2** and **1.3** are two **allowed modern editions**; the client and server pick the **best** mutual version per connection so you stay secure and interoperable.

---

## 9. Reverse proxy (nginx’s role)

A **reverse proxy** sits in front of app backends and speaks to the client **as if** it were the whole site.

- **SSL termination:** browser sees HTTPS; nginx can talk to PHP-FPM over plain HTTP/FastCGI inside the trust boundary (same Docker network).
- **Routing:** `location ~ \.php$` sends PHP to FPM; other paths can be static from disk.
- **Hiding internals:** the browser never opens port 9000 or 3306 — only 443 on the host.

Forward proxy vs reverse proxy (direction of “on behalf of”):

- **Forward:** client → proxy → internet.
- **Reverse:** client → proxy → **your** backends (wordpress, etc.).

---

## 10. PHP-FPM and FastCGI

**PHP-FPM** = FastCGI Process Manager: a **pool** of worker processes that run PHP.

- **Nginx** does not embed a PHP interpreter.
- For PHP URIs, nginx speaks **FastCGI** (a binary protocol) to **php-fpm** listening on **TCP 9000** (in your `www.conf`).
- FPM returns generated HTML; nginx returns it to the client.

---

## 11. Ports in this stack (and SSH 2222 context)

| Port | Service | Visible from host? | Role |
|------|---------|-------------------|------|
| **443** | Nginx | **Yes** (published) | HTTPS from browser. |
| **9000** | PHP-FPM | **No** (not published) | FastCGI from nginx to wordpress container. |
| **3306** | MariaDB | **No** | SQL from wordpress to mariadb. |
| **2222** | SSH (cluster) | N/A for Compose | Sometimes used to reach the **VM** from 42 computers; not part of the three Compose services. |

**Security intent:** only nginx faces the outside world for web traffic; DB and FPM stay on the internal bridge.

---

## 12. Accessing the site from a 42 lab machine (SOCKS + Firefox)

When your browser is **not** on the same network as the VM, you can tunnel through SSH:

1. On the lab machine, something like:  
   `ssh -N -D 9999 -p 2222 <login>@127.0.0.1`  
   (exact host/port depend on how your VM is exposed — adjust to your setup.)

2. **`-D 9999`:** SOCKS proxy on local port 9999.  
   **`-N`:** no remote shell, just hold the tunnel.

3. Firefox: **Manual proxy** → SOCKS host `127.0.0.1`, port `9999`, **SOCKS v5**, and enable **“Proxy DNS when using SOCKS v5”** so DNS for `<login>.42.fr` resolves the way the VM expects (e.g. via VM `/etc/hosts`).

4. Open **`https://<login>.42.fr`** — traffic goes through the tunnel to the VM where nginx listens on **443**.

---

## 13. Optional reminders (subject-adjacent)

- **No secrets in Git:** keep real passwords in local `.env` or secrets, not in the Dockerfile `RUN` lines or committed files.
- **TLS versions:** nginx must allow **TLS 1.2 and/or 1.3 only** (see §8 and `ssl_protocols` in nginx config).
- **Two WordPress users:** one admin whose name must **not** contain `admin` / `Admin` (per subject examples).

---

*End of extended notes. Complement with official Docker docs and your own defense Q&A.*
