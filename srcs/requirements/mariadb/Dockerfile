# 1. THE BASE
FROM debian:12

# 2. THE INSTALLATION
# Update package list and install MariaDB server. -y skips the confirmation prompt.
RUN apt-get update -y && apt-get install mariadb-server -y

# 3. THE DIRECTORY SETUP
# Ensure the run directory exists and belongs to the mysql user
RUN mkdir -p /var/run/mysqld \
    && chown -R mysql:mysql /var/run/mysqld

# 4. THE CONFIGURATION INJECTION
# Overwrite the default Debian configuration with our custom file
COPY conf/mysql.cnf /etc/mysql/mariadb.conf.d/mysql.cnf

# 5. THE SCRIPT INJECTION
# Move the setup script into the binary folder
COPY tools/setup.sh /usr/local/bin/

# Make the script executable
RUN chmod +x /usr/local/bin/setup.sh

# 6. THE EXECUTION
# Run the script when the container boots
ENTRYPOINT ["/usr/local/bin/setup.sh"]