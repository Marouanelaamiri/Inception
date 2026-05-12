what is an image :
its a readonly immutable snapshot of a filesystem and configurations, its built in layers.
what is a container :
its a running instance of an image. its a process with a writable layer on top.
what is a Dockerfile :
its the shell-sccript recipe used to build an image. every RUN, COPY or ADD commands creates a new cached filesystem layer.
what is Docker Compose :
its a YAML based tool , instead of running 10 massive docker run commands in terminal, we define the desired state of the 
network, volumes and containers in docker-compose.yml.
what is a Volume :
its a mechanism to persist data outside the lifecycle of a container. if a container dies , its internal filesysten is cleand.

CORE CONCEPTS :

1/ The container illusion(Namespases, Cgroups) :
A container is not a lightweight Virtual Machine. A VM runs a full guest operating system with virtualized hardware. A container does not.

A container is just a normal Linux process running directly on your host kernel, but Docker uses kernel features to lie to that process.

Namespaces (Isolation): This dictates what the process can see. Docker uses the PID namespace so your Nginx process thinks it is Process ID 1. It uses the Network namespace so the container thinks it has its own eth0 network card. It uses the Mount namespace so the container thinks it has its own root / filesystem.

Cgroups (Limits): This dictates what the process can use. Cgroups prevent a memory leak in your WordPress container from crashing your MariaDB container. It hard-caps CPU and RAM usage.

Example: When MariaDB writes to disk inside the container, it makes a standard Linux open() and write() syscall. The host kernel executes it. There is no translation layer.

2/Docker networking and internal DNS :
By default, containers cannot talk to each other. Your docker-compose.yml puts them on a custom bridge network.

Under the hood, Docker creates a virtual network switch on your host machine. It plugs a virtual ethernet cable (veth pair) into each container.

The critical concept here is Docker's embedded DNS (127.0.0.11).
Because container IP addresses change every time they restart, you cannot hardcode IPs. Instead, Docker intercepts DNS queries. When your Nginx config says fastcgi_pass wordpress:9000;, Nginx asks for the IP of "wordpress". Docker's internal DNS dynamically resolves the word "wordpress" to the container's current IP address on the bridge network.

3/PID 1 and signal handling :
In Linux, Process ID 1 (PID 1) is special. It is the init system. When you tell Docker to stop a container, Docker sends a SIGTERM signal to PID 1. If PID 1 doesn't handle it, Docker waits 10 seconds and mercilessly kills the process with SIGKILL, leading to database corruption.

In your setup.sh scripts, you use commands like exec mysqld_safe and exec /usr/sbin/php-fpm7.4 -F.

Why exec is mandatory:
If you just ran mysqld_safe in your bash script, Bash becomes PID 1, and MariaDB becomes PID 2. Bash ignores the SIGTERM signal from Docker. MariaDB never gets the shutdown command.
Using exec tells Linux to replace the current shell process with the new process. MariaDB becomes PID 1, receives the SIGTERM from Docker, and shuts down gracefully.

MINDMAP ? 

The Entry: You type https://malaamir.42.fr in your browser.

Host Routing: The traffic hits your physical machine on port 443. Iptables (Linux firewall rules managed by Docker) performs Network Address Translation (NAT) to forward this traffic to the Nginx container's IP.

Reverse Proxy (Nginx): Nginx decrypts the SSL traffic. It checks the request. If you asked for a static image (.jpg), Nginx grabs it from the shared volume and sends it back. If you asked for a .php page, it forwards the request over the bridge network to the WordPress container on port 9000.

App Server (PHP-FPM): WordPress executes the PHP code. To render the page, it needs user data. It makes a TCP connection to mariadb:3306.

Database (MariaDB): MariaDB receives the query, reads the data from its persistent volume (so the data survives container restarts), and returns the SQL result.

The Return: The HTML is generated, passed back to Nginx, and sent to your browser.