include .env

ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
DOCKER               = docker
DOCKER_COMPOSE       = docker compose
DOCKER_COMPOSE_FILE  = $(ROOT_DIR)/docker-compose.yml
DOCKER_COMPOSE_LOCAL = $(DOCKER_COMPOSE) --file $(DOCKER_COMPOSE_FILE)

EXEC_CONTAINER       = $(DOCKER_COMPOSE) --file $(DOCKER_COMPOSE_FILE) exec
EXEC_PHP             = $(EXEC_CONTAINER) drupal
EXEC_DATABASE	 	 = $(EXEC_CONTAINER) db

BACKUP_DIR_FILE=config/dump/$(PROJECT_NAME).sql

default: up

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
up: usergroup install permissions dockerup mod-install site-install mod-enable permissions

## usergroup : Adicionar usuário local no grupo www-data
.PHONY: usergroup
usergroup:
	@echo ">>Adicionando usuário local ao grupo www-data"
	sudo usermod -a -G www-data ${USER}

## install : Instalar Drupal
.PHONY: install
install:
	@echo ">> instalando o drupal ${DRUPAL_VERSION}"
	composer create-project drupal/recommended-project:${DRUPAL_VERSION} ${PROJECT_NAME} --no-interaction
	cp ./${PROJECT_NAME}/web/core/assets/scaffold/files/drupal.README.md ./${PROJECT_NAME}/web/core/assets/scaffold/files/drupal.README.txt

## Ajustar permissões na pasta do projeto para permitir edição de arquivos localmente
.PHONY: permissions
permissions:
	@echo ">> Ajustando permissões para edição local de arquivos"
	sudo chown -R ${USER}:www-data ./$(PROJECT_NAME) && sudo chmod -R 775 ./$(PROJECT_NAME) && sudo chmod -R g+s ./$(PROJECT_NAME)

## up :	Start up containers
.PHONY: dockerup
dockerup:
	@echo ">> Subindo containers"
	@$(DOCKER_COMPOSE_LOCAL) up -d --remove-orphans

## mod-install : Instalar módulos
.PHONY: mod-install
mod-install:
	@echo ">> Instalando modulos"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "composer require -n $(DRUPAL_CONTRIB_MODULES) $(DRUPAL_CONTRIB_MODULES_INSTALL)"
	
## mod-enable : Habilitando módulos
.PHONY: mod-enable
mod-enable:
	@echo ">> Habilitando modulos"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush en -y "${DRUPAL_CONTRIB_MODULES_INSTALL//"drupal/"/}""

## si : site-install com instalação de módulos para DEV
.PHONY: site-install
site-install:
	@echo ">> Configurando o Drupal para o projeto"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush si standard install_configure_form.enable_update_status_emails=NULL --account-name=admin --account-pass=admin --db-url=${DB_URL} --site-name=$(PROJECT_NAME) -y"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c " sed -i 's/sites\/default\/files.\+sync/..\/config\/sync/g' web/sites/default/settings.php"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cr"


## backup	:	Backup drupal site
.PHONY: debugMode
debugMode:
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "cat << EOF >> drupal/sites/default/settings.php
	$settings['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';
	$settings['cache']['bins']['render'] = 'cache.backend.null';
	$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';
	$settings['cache']['bins']['page'] = 'cache.backend.null';
	$config['system.performance']['css']['preprocess'] = FALSE;
	$config['system.performance']['js']['preprocess'] = FALSE;
	EOF
	"
	
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "cat >| drupal/web/sites/development.services.yml << EOF
	# Local development services.
	#
	# To activate this feature, follow the instructions at the top of the
	# 'example.settings.local.php' file, which sits next to this file.
	parameters:
	http.response.debug_cacheability_headers: true
	twig.config:
		debug: true
		auto_reload: true
		cache: false
	services:
	cache.backend.null:
		class: Drupal\Core\Cache\NullBackendFactory
	EOF
	"

	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush -y config-set system.performance css.preprocess 0"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush -y config-set system.performance js.preprocess 0"
	@$(DOCKER_COMPOSE_LOCAL) exec drupal sh -c "drush cr"

## backup	:	Backup drupal site
.PHONY: backup
backup:
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

# https://stackoverflow.com/a/6273809/1826109
%:
	@:
