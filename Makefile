include .env

ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
DOCKER               = docker
DOCKER_COMPOSE       = docker compose
DOCKER_COMPOSE_FILE  = $(ROOT_DIR)/docker-compose.yml
DOCKER_COMPOSE_LOCAL = $(DOCKER_COMPOSE) --file $(DOCKER_COMPOSE_FILE)

EXEC_CONTAINER       = $(DOCKER_COMPOSE) --file $(DOCKER_COMPOSE_FILE) exec
EXEC_DRUPAL             = $(EXEC_CONTAINER) drupal
EXEC_DB	 	 		 = $(EXEC_CONTAINER) db

BACKUP_DIR_FILE=config/dump/$(PROJECT_NAME).sql

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
up: usergroup install dockerup mod-install site-install mod-enable permissions twig-debug

## install : Instalar Drupal
.PHONY: install
install:
	@echo ">> instalando o drupal ${DRUPAL_VERSION}"
	@composer create-project drupal/recommended-project:${DRUPAL_VERSION} ${PROJECT_NAME} --no-interaction

## dockerup :	Start up containers
.PHONY: dockerup
dockerup:
	@echo ">> Subindo containers"
	@$(DOCKER_COMPOSE_LOCAL) up -d --remove-orphans

## mod-install : Instalar módulos
.PHONY: mod-install
mod-install:
	@echo ">> Instalando modulos"
	@cd drupal && composer require -n "$(DRUPAL_CONTRIB_MODULES_INSTALL)"

## si : site-install
.PHONY: site-install
site-install:
	@echo ">> Instalando o Drupal"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush si standard install_configure_form.enable_update_status_emails=NULL --db-url=$(DB_URL) --account-name=admin --account-pass=admin --locale=pt-br --site-name=$(PROJECT_NAME) -y && drush cr"

## mod-enable : Habilitando módulos
.PHONY: mod-enable
mod-enable:
	@echo ">> Habilitando modulos"
	@$(EXEC_DRUPAL) sh -c "drush en -y "$(subst drupal/,,${DRUPAL_CONTRIB_MODULES_ENABLE}")"

## twig-debug : Twig debug
.PHONY: twig-debug
define SETTINGS_CONFIG
'$$settings'"['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';" \\n'$$settings'"['cache']['bins']['render'] = 'cache.backend.null';" \\n'$$settings'"['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';" \\n'$$settings'"['cache']['bins']['page'] = 'cache.backend.null';" \\n'$$config'"['system.performance']['css']['preprocess'] = FALSE;" \\n'$$config'"['system.performance']['js']['preprocess'] = FALSE;" \\n
endef

define DEV_SERVICES
"parameters:\n  http.response.debug_cacheability_headers: true\n  twig.config:\n    debug: true\n    auto_reload: true\n    cache: false\nservices:\n  cache.backend.null:\n    class: Drupal\\Core\\Cache\\NullBackendFactory"
endef

twig-debug:
	@echo ">> Habilitando debud de twig"
	@echo $(SETTINGS_CONFIG) >> drupal/web/sites/default/settings.php
	@echo $(DEV_SERVICES) > drupal/web/sites/development.services.yml
	
## Ajustar permissões na pasta do projeto para permitir edição de arquivos localmente
.PHONY: permissions
permissions:
	@echo ">> Ajustando permissões para edição local de arquivos"
	sudo chown -R ${USER}:www-data ./$(PROJECT_NAME) && sudo chmod -R 775 ./$(PROJECT_NAME) && sudo chmod -R g+s ./$(PROJECT_NAME)

## multi : multisite : make multisite NEW_SITE=<NOME_DO_NOVO_SITE>
.PHONY: multisite
multisite:
	@echo ">> Instalando novo site"
	@$(EXEC_DB) sh -c "mysql -uroot -pdrupal -e 'CREATE DATABASE $(NEW_SITE);'"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "touch /etc/apache2/sites-available/$(NEW_SITE).conf"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "echo '<VirtualHost *:80> \n DocumentRoot /var/www/html \n ServerName $(NEW_SITE).localhost \n ErrorLog \$${APACHE_LOG_DIR}/$(NEW_SITE).localhost.log \n CustomLog \$${APACHE_LOG_DIR}/$(NEW_SITE).localhost_error.log combined \n </VirtualHost>' > /etc/apache2/sites-available/$(NEW_SITE).conf"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush si standard install_configure_form.enable_update_status_emails=NULL --account-name=admin --account-pass=admin --locale=pt-br --sites-subdir=$(NEW_SITE) --db-url='mysql://root:${DB_ROOT_PASSWORD}@db:${DB_PORT}/${NEW_SITE}' --site-name=$(NEW_SITE) -y"
	@make permissions
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "echo '\$$sites['\''$(NEW_SITE).localhost'\''] = '\''$(NEW_SITE)'\'';'" >> drupal/web/sites/sites.php
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cr"

## usergroup : Adicionar usuário local no grupo www-data
.PHONY: usergroup
usergroup:
	@echo ">>Adicionando usuário local ao grupo www-data"
	sudo usermod -a -G www-data ${USER}

## backup	:	Backup drupal site
.PHONY: backup
backup:
	sites/default/settings.php
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cr"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cex -y"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush sql-dump --result-file=../$(BACKUP_DIR_FILE)"

## restore	:	Backup drupal site
.PHONY: restore
 restore: 
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush sqlc < ./$(BACKUP_DIR_FILE)"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cim -y"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush updb -y"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cr"

## @drush Drush Cache Rebuild 
.PHONY: cr	
cr:
	@echo ">> Limpando o cache do drupal"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cr"

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
	docker exec -ti -e COLUMNS=$(shell tput cols) -e LINES=$(shell tput lines) $(shell docker ps --filter name='$(PROJECT_NAME)_$(or $(filter-out $@,$(MAKECMDGOALS)), 'php')' --format "{{ .ID }}") bash

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

.PHONY: teste
teste:
	@sed -i "s|\$settings\['config_sync_directory'\] = 'sites/default/files/config[^']*/sync';|\$settings['config_sync_directory'] = 'config/sync';|" drupal/web/sites/default/settings.php
	
# https://stackoverflow.com/a/6273809/1826109
%:
	@:
