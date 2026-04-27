#!/bin/bash

# Navigate to the volume directory where the website files will live
cd /var/www/html

# Check if WordPress is already installed by looking for its core configuration file.
if [ ! -f "wp-config.php" ]; then
    echo "Downloading WordPress..."
    
    # Download the core WordPress files
    wp core download --allow-root

    echo "Configuring database connection..."
    # Generate the wp-config.php file using the variables injected from your .env file
    # Note that --dbhost points to 'mariadb', the exact container_name we set in docker-compose.yml
    wp config create \
        --dbname=${MYSQL_DATABASE} \
        --dbuser=${MYSQL_USER} \
        --dbpass=${MYSQL_PASSWORD} \
        --dbhost=mariadb \
        --allow-root

    echo "Installing WordPress and creating the Admin user..."
    # Run the internal installation script
    wp core install \
        --url=https://${DOMAIN_NAME} \
        --title="Inception" \
        --admin_user=${WP_ADMIN_USER} \
        --admin_password=${WP_ADMIN_PASSWORD} \
        --admin_email=${WP_ADMIN_EMAIL} \
        --allow-root

    echo "Creating the standard secondary user..."
    # The subject requires a second, non-admin user. We give them the 'author' role.
    wp user create ${WP_USER} ${WP_USER_EMAIL} \
        --user_pass=${WP_USER_PASSWORD} \
        --role=author \
        --allow-root

    echo "WordPress installation complete."
fi

# PHP-FPM runs as a background daemon by default. 
# The -F flag forces it to run in the foreground, keeping the Docker container alive.
echo "Starting PHP-FPM..."
exec /usr/sbin/php-fpm7.4 -F