mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfile_dir  := $(shell dirname $(mkfile_path))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))

ALPINE_VERS=latest
ELASTICSEARCH_VERS=6.2.4
ES_URL=localhost:9200
NODE_NAME?=$(uuidgen)
VOLUMES_PATH?=${mkfile_dir}

.PHONY: help build run clean

help:
	@echo make apt           - установка необходимых утилит
	@echo make build         - Cобрать один image elasticsearch из dockerfiles/Dockerfile-es
	@echo make run           - запустить один контейнер elasticsearch с именем nd
	@echo make kill          - убить один контейнер elasticsearch с именем nd
	@echo make info          - информация о контейнер elasticsearch с именем nd
	@echo make cluster-run   - запустить кластер из трех контейнеров elasticsearch с именами es-node-1 es-node-2 es-node-3
	@echo make cluster-info  - информация о кластере
	@echo make cluster-kill  - убить кластер
	@echo make clean         - Очистить imag'ы
	@echo make ans-build     - Cобрать один image ansible
	@echo make ans-run       - Запустить ansible-playbook внутри контейнера
	@echo make do-asn-run    - Запустить ansible-playbook на DigitalOcean
	@echo make local-asn-run - Запустить ansible-playbook локально
	@echo make export        - экспорт image elasticsearch на DigitalOcean
	@echo make ssh_0         - зайти по ssh на nd
	@echo make ssh_1         - зайти по ssh на es-node-1
	@echo make ssh_2         - зайти по ssh на es-node-2
	@echo make ssh_3         - зайти по ssh на es-node-3
	@echo make rssh_1        - зайти по ssh на es-node-1 на DigitalOcean
	@echo make rssh_2        - зайти по ssh на es-node-2 на DigitalOcean
	@echo make rssh_3        - зайти по ssh на es-node-3 на DigitalOcean

./ssh/id_rsa:
	@echo ssh key generate

ssh: ./ssh/id_rsa
	@ssh-keygen -q -t rsa -N "" -f $<
	@chmod 600 `pwd`/ssh/id_rsa
	@chmod 600 `pwd`/ssh/id_rsa.pub

apt:
	sudp apt install jq

build: dockerfiles/Dockerfile-es ssh
	@echo ============= Build
	@docker build \
	--build-arg ELASTICSEARCH_VERS=${ELASTICSEARCH_VERS} \
	--build-arg NODE_NAME=${NODE_NAME} \
	--build-arg UNICAST_HOSTS=${NODE_NAME} \
	-t maxt/alpine-elastic:0.1 \
	-f $< \
	.

run: build
	@echo ============= Run
	docker network create es
	docker run \
	--detach \
	--privileged \
	-e NODE_NAME=${NODE_NAME} \
	-e UNICAST_HOSTS=${NODE_NAME} \
	--name nd \
	--network es \
	-p 127.0.0.1:9200:9200 \
	-p 127.0.0.1:9300:9300 \
	-v `pwd`/es-data:/data \
	maxt/alpine-elastic:0.1

info:
	curl -X GET ${ES_URL}/?pretty
	curl -X GET ${ES_URL}/_nodes?pretty

kill:
	@echo ============= Kill
	docker kill nd || true
	docker rm nd || true
	docker network rm es || true

cluster-run: build
	@echo ============= Run Cluster
	docker network create es

	docker run --detach --privileged -e NODE_NAME=es-node-1 -e UNICAST_HOSTS="es-node-1,es-node-2,es-node-3" --name es-node-1 --network es -p 127.0.0.1:9200:9200 -p 127.0.0.1:9300:9300 -v `pwd`/es-data-cluster/es-data-1:/data maxt/alpine-elastic:0.1
	docker run --detach --privileged -e NODE_NAME=es-node-2 -e UNICAST_HOSTS="es-node-1,es-node-2,es-node-3" --name es-node-2 --network es -p 127.0.0.1:9201:9200 -p 127.0.0.1:9301:9300 -v `pwd`/es-data-cluster/es-data-2:/data maxt/alpine-elastic:0.1
	docker run --detach --privileged -e NODE_NAME=es-node-3 -e UNICAST_HOSTS="es-node-1,es-node-2,es-node-3" --name es-node-3 --network es -p 127.0.0.1:9202:9200 -p 127.0.0.1:9302:9300 -v `pwd`/es-data-cluster/es-data-3:/data maxt/alpine-elastic:0.1

cluster-kill:
	@echo ============= Kill Cluster
	docker kill es-node-1 || true
	docker kill es-node-2 || true
	docker kill es-node-3 || true

	docker rm es-node-1 || true
	docker rm es-node-2 || true
	docker rm es-node-3 || true

	docker network rm es || true

cluster-info:
	curl -XGET 'http://localhost:9200/_cluster/stats?human&pretty'

ans-build: dockerfiles/Dockerfile-ans build
	@echo ============= Ansible Build
	@docker build \
	-t maxt/alpine-ansible:0.1 \
	-f $< \
	.

ans-run: ans-build
	@echo ============= Ansible Run
	docker run -ti --rm \
	--privileged \
	--name ansible \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v `pwd`/ansible:/etc/ansible \
	-v `pwd`/ansible-home:/home/ansible \
	-v `pwd`/es-data-cluster:/data-cluster \
	maxt/alpine-ansible:0.1 sudo ansible-playbook es-cluster.yml --extra-vars "volumes_path=${VOLUMES_PATH}/es-data-cluster"

local-asn-run: build
	@echo ============= Local Ansible Run
	ansible-playbook -i ansible/hosts ansible-home/es-cluster.yml --extra-vars "volumes_path=${VOLUMES_PATH}/es-data-cluster"

do-asn-run: build
	@echo ============= DigitalOcean Ansible Run
	ansible-playbook -i ansible/hosts ansible-home/es-cluster.yml --extra-vars "volumes_path=/root/data arg_hosts=doc"

ssh_0: ssh
	@chmod 600 `pwd`/ssh/id_rsa &> /dev/null
	@chmod 600 `pwd`/ssh/id_rsa.pub &> /dev/null
	@ssh-keygen  -q -f "/home/${USER}/.ssh/known_hosts" -R `docker inspect nd | jq -r .[0].NetworkSettings.Networks.es.IPAddress` &> /dev/null
	@ssh -i `pwd`/ssh/id_rsa -o Compression=no -o StrictHostKeyChecking=no elasticsearch@`docker inspect nd | jq -r .[0].NetworkSettings.Networks.es.IPAddress`

ssh_1: ssh
	@chmod 600 `pwd`/ssh/id_rsa &> /dev/null
	@chmod 600 `pwd`/ssh/id_rsa.pub &> /dev/null
	@ssh-keygen -q -f "/home/${USER}/.ssh/known_hosts" -R `docker inspect es-node-1 | jq -r .[0].NetworkSettings.Networks.es.IPAddress` &> /dev/null
	@ssh -i `pwd`/ssh/id_rsa -o Compression=no -o StrictHostKeyChecking=no elasticsearch@`docker inspect es-node-1 | jq -r .[0].NetworkSettings.Networks.es.IPAddress`

ssh_2: ssh
	@chmod 600 `pwd`/ssh/id_rsa &> /dev/null
	@chmod 600 `pwd`/ssh/id_rsa.pub &> /dev/null
	@ssh-keygen -q -f "/home/${USER}/.ssh/known_hosts" -R `docker inspect es-node-2 | jq -r .[0].NetworkSettings.Networks.es.IPAddress` &> /dev/null
	@ssh -i `pwd`/ssh/id_rsa -o Compression=no -o StrictHostKeyChecking=no elasticsearch@`docker inspect es-node-2 | jq -r .[0].NetworkSettings.Networks.es.IPAddress`

ssh_3: ssh
	@chmod 600 `pwd`/ssh/id_rsa &> /dev/null
	@chmod 600 `pwd`/ssh/id_rsa.pub &> /dev/null
	@ssh-keygen -q -f "/home/${USER}/.ssh/known_hosts" -R `docker inspect es-node-3 | jq -r .[0].NetworkSettings.Networks.es.IPAddress` &> /dev/null
	@ssh -i `pwd`/ssh/id_rsa -o Compression=no -o StrictHostKeyChecking=no elasticsearch@`docker inspect es-node-3 | jq -r .[0].NetworkSettings.Networks.es.IPAddress`

rssh_1: ssh
	@chmod 600 `pwd`/ssh/id_rsa &> /dev/null
	@chmod 600 `pwd`/ssh/id_rsa.pub &> /dev/null
#	@ssh-keygen -q -f "/home/${USER}/.ssh/known_hosts" -R 167.99.215.176
	@ssh -i `pwd`/ssh/id_rsa -o Compression=no -o StrictHostKeyChecking=no -p 2020 elasticsearch@167.99.215.176

rssh_2: ssh
	@chmod 600 `pwd`/ssh/id_rsa &> /dev/null
	@chmod 600 `pwd`/ssh/id_rsa.pub &> /dev/null
#	@ssh-keygen -q -f "/home/${USER}/.ssh/known_hosts" -R 167.99.215.176
	@ssh -i `pwd`/ssh/id_rsa -o Compression=no -o StrictHostKeyChecking=no -p 2021 elasticsearch@167.99.215.176

rssh_3: ssh
	@chmod 600 `pwd`/ssh/id_rsa &> /dev/null
	@chmod 600 `pwd`/ssh/id_rsa.pub &> /dev/null
#	@ssh-keygen -q -f "/home/${USER}/.ssh/known_hosts" -R 167.99.215.176
	@ssh -i `pwd`/ssh/id_rsa -o Compression=no -o StrictHostKeyChecking=no -p 2022 elasticsearch@167.99.215.176

export:
	docker save maxt/alpine-elastic | bzip2 | ssh root@167.99.215.176 "bunzip2 | docker load"

clean:
	[ "`docker ps -a -q -f status=exited`" != "" ] && docker rm `docker ps -a -q -f status=exited` || exit 0
	[ "`docker images -a -q -f dangling=true`" != "" ] && docker rmi `docker images -a -q -f dangling=true` || exit 0
