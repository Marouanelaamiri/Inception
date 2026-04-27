# 1. THE BASE
FROM debian:11

# 2. THE INSTALLATION
RUN apt-get update -y && apt-get install -y \
    php7.4-fpm \
    php7.4-mysql \
    wget

# Download the WP-CLI executable, make it runnable, and move it to the binaries folder
RUN wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# 3. THE DIRECTORY SETUP
# PHP-FPM requires this specific directory to exist to store its process ID (PID) file.
# If you do not create it, PHP-FPM will crash on boot.
RUN mkdir -p /run/php

# 4. THE CONFIGURATION INJECTION
# Overwrite the default www.conf with our custom network configuration
COPY conf/www.conf /etc/php/7.4/fpm/pool.d/www.conf

# 5. THE SCRIPT INJECTION
COPY tools/setup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/setup.sh

# 6. THE EXECUTION
CMD ["/usr/local/bin/setup.sh"]