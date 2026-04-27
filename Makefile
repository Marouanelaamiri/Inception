DATA_DIR := /home/malaamir/data
WP_DIR   := $(DATA_DIR)/wordpress
DB_DIR   := $(DATA_DIR)/mariadb

COMPOSE  := docker compose -f srcs/docker-compose.yml

all: up

up:
	@mkdir -p $(WP_DIR)
	@mkdir -p $(DB_DIR)
	$(COMPOSE) up --build -d

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down -v --rmi all --remove-orphans
	sudo rm -rf $(DATA_DIR)
	docker system prune -af

re: clean up

.PHONY: all up down clean re