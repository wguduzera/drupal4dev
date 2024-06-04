# drupal4dev
Plug&amp;Play Drupal environment

## What is this repository for? ##
Código para subir um Projeto Plug 'n Play do Drupal para desenvolvimento.

## Requisitos ##
Docker,
Docker Compose,
Composer.

## Orientações ##
* variáveis em estão no arquivo - .env
* comandos úteis estão no arquivo - Makefile
* user e senha de administrador : admin/admin

## Rodando ##
* Subindo um Drupal do zero
```
make up
```

* Acessando
```
https://localhost:8080
```

### Multisite ###
* Após subir o projeto, criar um novo site
```
make multisite NEW_SITE=<NOME_SITE>

Ex.: make multisite NEW_SITE=projeto2
```

* Acessando
```
https://projeto2.localhost:8080
```
