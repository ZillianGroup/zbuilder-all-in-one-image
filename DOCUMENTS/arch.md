zweb-builder Architecture Diagram
---------------------------------

# Description

This document describes the components and architecture of the zweb-builder docker image.



# Architecture Diagram

![img](./assets/images/zweb-builder-self-host-arch.svg)



# Parts

## Envoy

The entry of all requests, the configuration file is in [Envoy Config](../config/envoy/zweb-unit-ingress.yaml)

## Nginx

Static file web server for zweb-builder, the configuration file is in [Nginx Config](../config/nginx/zweb-builder-frontend.conf)

## zweb-builder

Static files for zweb-builder front-end.

## builder-backend

Holds all APP, Resource and Action APIs. 

## builder-backend-ws

WebScoket server for editor, all components modify method are served by this unit. 

For WebSocket message detail, please see [zweb-builder-backend WebSocket Message Documents](https://github.com/zilliangroup/zweb-builder-backend-websocket-docs).

## zweb-supervisor-backend

the supervisor unit holds all logon and user info APIs.

## zweb-supervisor-backend-internal

The supervisor internal unit holds ABAC and raw info APIs.

## Postgres

Storage all data in it.

The postgres init scripts is in [Postgres Init](../scripts/postgres-init.sh)

## Redis

For cache user session.

## Minio

For object storage, like user avatar etc.
