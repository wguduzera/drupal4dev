include .env

ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
DOCKER               = docker
DOCKER_COMPOSE       = docker compose
DOCKER_COMPOSE_FILE  = $(ROOT_DIR)/docker-compose.yml
DOCKER_COMPOSE_LOCAL = $(DOCKER_COMPOSE) --file $(DOCKER_COMPOSE_FILE)

EXEC_CONTAINER       = $(DOCKER_COMPOSE) --file $(DOCKER_COMPOSE_FILE) exec
EXEC_DRUPAL          = $(EXEC_CONTAINER) drupal
EXEC_DB	 	 		 = $(EXEC_CONTAINER) db

default: help

## help	:	Print commands help.
.PHONY: help
ifneq (,$(wildcard docker.mk))
help : docker.mk
	@sed -n 's/^##//p' $<
else
help : Makefile
	@sed -n 's/^##//p' $<
endif

## up : Subir o projeto
.PHONY: up
up: dockerup install mod-install site-install mod-enable permissions debug

## dockerup :	Start up containers
.PHONY: dockerup
dockerup:
	@echo ">> Subindo containers"
	@$(DOCKER_COMPOSE_LOCAL) up -d --remove-orphans

## install : Instalar Drupal
.PHONY: install
install:
	@echo ">> instalando o drupal ${DRUPAL_VERSION}"
	@$(EXEC_DRUPAL) sh -c "cd /opt && composer create-project drupal/recommended-project:${DRUPAL_VERSION} ${PROJECT_NAME} --no-interaction"

## mod-install : Instalar módulos
.PHONY: mod-install
mod-install:
	@echo ">> Instalando modulos"
	@$(EXEC_DRUPAL) sh -c "composer require -n $(DRUPAL_CONTRIB_MODULES_INSTALL)"
	
## si : site-install
.PHONY: site-install
site-install:
	@echo ">> Instalando o Drupal"
	@$(EXEC_DRUPAL) sh -c "drush si standard install_configure_form.enable_update_status_emails=NULL --db-url=$(DB_URL) --account-name=admin --account-pass=admin --locale=pt-br --site-name=$(PROJECT_NAME) -y && drush cr"

## mod-enable : Habilitar módulos
.PHONY: mod-enable
mod-enable:
	@echo ">> Habilitando modulos"
	@$(EXEC_DRUPAL) sh -c "drush en -y "$(subst drupal/,,${DRUPAL_CONTRIB_MODULES_ENABLE}")"

# debug : Twig debug
.PHONY: debug
define SETTINGS_CONFIG
\\n'$$settings'"['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';" \\n'$$settings'"['cache']['bins']['render'] = 'cache.backend.null';" \\n'$$settings'"['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';" \\n'$$settings'"['cache']['bins']['page'] = 'cache.backend.null';" \\n'$$config'"['system.performance']['css']['preprocess'] = FALSE;" \\n'$$config'"['system.performance']['js']['preprocess'] = FALSE;" \\n
endef

debug:
	@echo ">> Habilitando debud de twig"
	@sed -i '/http.response.debug_cacheability_headers:/a\  twig.config:\n\     debug: true\n\     auto_reload: true\n\     cache: false' drupal/web/sites/development.services.yml
	@echo $(SETTINGS_CONFIG) >> drupal/web/sites/default/settings.php

	@echo ">> Definindo pasta de sync"
	@sed -i "s/sites\/default\/files\/config_.*'/\/opt\/config\/sync'/g" drupal/web/sites/default/settings.php

	@echo ">> Limpando caches"
	@$(EXEC_DRUPAL) sh -c "drush cr"


## multi : multisite : make multisite NEW_SITE=<NOME_DO_NOVO_SITE>
.PHONY: multisite-mysql
multisite-mysql:
	@echo ">> Instalando novo site"
	@$(EXEC_DB) sh -c "mysql -uroot -pdrupal -e 'CREATE DATABASE $(NEW_SITE);'"
	@$(EXEC_DRUPAL) sh -c "touch /etc/apache2/sites-available/$(NEW_SITE).conf"
	@$(EXEC_DRUPAL) sh -c "echo '<VirtualHost *:80> \n DocumentRoot /var/www/html \n ServerName $(NEW_SITE).localhost \n ErrorLog \$${APACHE_LOG_DIR}/$(NEW_SITE).localhost.log \n CustomLog \$${APACHE_LOG_DIR}/$(NEW_SITE).localhost_error.log combined \n </VirtualHost>' > /etc/apache2/sites-available/$(NEW_SITE).conf"
	@$(EXEC_DRUPAL) sh -c "drush si standard install_configure_form.enable_update_status_emails=NULL --account-name=admin --account-pass=admin --locale=pt-br --sites-subdir=$(NEW_SITE) --db-url='mysql://root:${DB_ROOT_PASSWORD}@db:${DB_PORT}/${NEW_SITE}' --site-name=$(NEW_SITE) -y"
	@make permissions
	@$(EXEC_DRUPAL) sh -c "echo '\$$sites['\''$(NEW_SITE).localhost'\''] = '\''$(NEW_SITE)'\'';'" >> drupal/web/sites/sites.php
	@$(EXEC_DRUPAL) sh -c "drush cr"

## multi : multisite : make multisite NEW_SITE=<NOME_DO_NOVO_SITE>
.PHONY: multisite-pgsql
multisite-pgsql:
	@echo ">> Instalando novo site"
	@$(EXEC_DB) sh -c "psql -U $(DB_USER) -c 'CREATE DATABASE $(NEW_SITE);'"
	@$(EXEC_DRUPAL) sh -c "touch /etc/apache2/sites-available/$(NEW_SITE).conf"
	@$(EXEC_DRUPAL) sh -c "echo '<VirtualHost *:80> \n DocumentRoot /var/www/html \n ServerName $(NEW_SITE).localhost \n ErrorLog \$${APACHE_LOG_DIR}/$(NEW_SITE).localhost.log \n CustomLog \$${APACHE_LOG_DIR}/$(NEW_SITE).localhost_error.log combined \n </VirtualHost>' > /etc/apache2/sites-available/$(NEW_SITE).conf"
	@$(EXEC_DRUPAL) sh -c "drush si standard install_configure_form.enable_update_status_emails=NULL --account-name=admin --account-pass=admin --locale=pt-br --sites-subdir=$(NEW_SITE) --db-url='pgsql://drupal:drupal@db:5432/$(NEW_SITE)' --site-name=$(NEW_SITE) -y"
	@make permissions
	@$(EXEC_DRUPAL) sh -c "echo '\$$sites['\''$(NEW_SITE).localhost'\''] = '\''$(NEW_SITE)'\'';'" >> drupal/web/sites/sites.php
	@$(EXEC_DRUPAL) sh -c "drush cr"

## Ajustar permissões na pasta do projeto para permitir edição de arquivos localmente
.PHONY: permissions
permissions:
	@echo ">> Ajustando permissões para edição local de arquivos"
	sudo chown -R ${USER}:www-data ./$(PROJECT_NAME) && sudo chmod -R 775 ./$(PROJECT_NAME) && sudo chmod -R g+s ./$(PROJECT_NAME)

## backup	:	Backup drupal site
.PHONY: backup
backup:
	@$(EXEC_DRUPAL) sh -c "drush cr"
	@$(EXEC_DRUPAL) sh -c "drush cex -y"
	@$(EXEC_DRUPAL) sh -c "drush sql-dump --result-file=/opt/config/dump/$(PROJECT_NAME).sql"

## restore	:	Backup drupal site
.PHONY: restore
 restore: 
	@$(EXEC_DRUPAL) sh -c "drush sqlc < /opt/config/dump/$(PROJECT_NAME).sql"
	@$(EXEC_DRUPAL) sh -c "drush deploy -y"

## usergroup : Adicionar usuário local no grupo www-data
.PHONY: usergroup
usergroup:
	@echo ">>Adicionando usuário local ao grupo www-data"
	sudo usermod -a -G www-data ${USER}

## @drush Drush Cache Rebuild 
.PHONY: cr	
cr:
	@echo ">> Limpando o cache do drupal"
	@$(EXEC_DRUPAL) sh -c "drush cr"

## start	:	Start containers without updating.
.PHONY: start
start:
	@echo ">> Starting containers "
	@$(DOCKER_COMPOSE_LOCAL) start

## stop	:	Stop containers.
.PHONY: stop
stop:
	@echo ">> Stopping containers "
	@$(DOCKER_COMPOSE_LOCAL) stop

## down	:	Remove containers and their volumes.
.PHONY: down
down:
	@echo ">> Removing containers "
	@$(DOCKER_COMPOSE_LOCAL) down -v $(filter-out $@,$(MAKECMDGOALS))
	@echo ">> Removing project folder"
	@sudo rm -fr $(PROJECT_NAME)

## ps	:	List running containers.
.PHONY: ps
ps:
	@docker ps --filter name='$(PROJECT_NAME)*'

## ssh	:	Access `php` container via shell.
##		You can optionally pass an argument with a service name to open a shell on the specified container
.PHONY: ssh
ssh:
	docker compose exec -ti -e COLUMNS=$(shell tput cols) -e LINES=$(shell tput lines) drupal bash

## composer	:	Executes `composer` command in a specified `COMPOSER_ROOT` directory (default is `/var/www/html`).
##		To use "--flag" arguments include them in quotation marks.
##		For example: make composer "update drupal/core --with-dependencies"
.PHONY: composer
composer:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") composer --working-dir=$(COMPOSER_ROOT) $(filter-out $@,$(MAKECMDGOALS))

## drush	:	Executes `drush` command in a specified `DRUPAL_ROOT` directory (default is `/var/www/html/web`).
##		To use "--flag" arguments include them in quotation marks.
##		For example: make drush "watchdog:show --type=cron"
.PHONY: drush
drush:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) $(filter-out $@,$(MAKECMDGOALS))

## logs	:	View containers logs.
##		You can optinally pass an argument with the service name to limit logs
##		logs php	: View `php` container logs.
##		logs nginx php	: View `nginx` and `php` containers logs.
.PHONY: logs
logs:
	@$(DOCKER_COMPOSE_LOCAL) logs -f $(filter-out $@,$(MAKECMDGOALS))

# https://stackoverflow.com/a/6273809/1826109
%:
	@:
