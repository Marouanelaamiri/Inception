#!/bin/sh

# Check if the WordPress database folder already exists. 
# If it does, we skip the setup so we don't overwrite existing data.
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then

    echo "Initializing MariaDB for the first time..."
    
    # Start the database process in the background temporarily
    service mariadb start
    
    # Pause for 2 seconds to ensure the database engine is fully booted before sending commands
    sleep 2

    # Inject the SQL commands using the environment variables
    # 1. Create the database
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;"
    
    # 2. Create the standard user. Note the '%' symbol. This allows the user to log in from ANY IP (the WordPress container) instead of just 'localhost'.
    mysql -e "CREATE USER IF NOT EXISTS \`${MYSQL_USER}\`@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    
    # 3. Give the standard user total control over the WordPress database
    mysql -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO \`${MYSQL_USER}\`@'%';"
    
    # 4. Lock down the root user with the secure root password
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    
    # 5. Reload the permission tables to apply changes
    mysql -e "FLUSH PRIVILEGES;"

    # Shut down the temporary background process using the new root password
    mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} shutdown
fi

# The 'exec' command replaces the shell script process with the database process.
# mysqld_safe is the standard command to run MariaDB in the foreground, keeping the container alive.
echo "Starting MariaDB in the foreground..."
exec mysqld_safe