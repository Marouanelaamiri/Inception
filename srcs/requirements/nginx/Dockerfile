# 1. THE BASE
FROM debian:11

# 2. THE BUILD ARGUMENT
# This catches the variable passed from docker-compose.yml
ARG DOMAIN_NAME

# 3. THE INSTALLATION
# Update and install the required packages
RUN apt-get update -y && apt-get install nginx openssl -y

# 4. THE SSL GENERATION
# Create the directory and immediately generate the self-signed certificate using the argument.
RUN mkdir -p /etc/nginx/ssl
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
	-keyout /etc/nginx/ssl/inception.key \
	-out /etc/nginx/ssl/inception.crt \
	-subj "/C=MA/ST=BeniMellal/L=Khouribga/O=42/OU=42/CN=${DOMAIN_NAME}"

# 5. THE CONFIGURATION INJECTION
# Copy your config file, overwriting the default Debian NGINX site
COPY conf/nginx.conf /etc/nginx/sites-available/default

# Replace the placeholder with the actual domain name inside the configuration file
RUN sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/g" /etc/nginx/sites-available/default

# 6. THE EXECUTION
# Expose the port for documentation and start the server natively in the foreground
EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]