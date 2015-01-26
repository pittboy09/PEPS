# PEPS deployment based on Docker containers
# (c) 2014-2015 MLstate

HOSTNAME?=$(shell cat hostname)
DOMAIN_NAME=$(shell cat domain)
MONGO_DATA=/data/db
SOLR_DATA=/data/solr
PEPS_ETC=/etc/peps

# Public ports
HTTPS_PORT?=443
SMTP_PORT?=25
SMTPS_PORT?=587

# Handy if you need --no-cache=true
DOCKER_BUILD_OPTS?=
DOCKER_DAEMON=docker run -d -h $(HOSTNAME)

default:
	@echo "PEPS"
	@echo "Write the server domain name to a file named 'domain' and then:"
	@echo "- make build: build docker containers"
	@echo "- make certificate: generate self-signed SSL certificate"
	@echo "  (or copy your own to server.key and server.crt)"
	@echo "- make run: run docker containers"
	@echo "---"
	@echo "make start/stop/kill/rm"

certificate:
	openssl genrsa -des3 -out server.key 1024
	openssl req -new -key server.key -out server.csr
	cp server.key server.key.org
	openssl rsa -in server.key.org -out server.key # strip passphrase
	openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

install_cert: server.key server.crt
	cp -a server.key server.crt $(PEPS_ETC)

build: domain
	cd mongod; docker build $(DOCKER_BUILD_OPTS) -t mongod .
	cd opa; docker build $(DOCKER_BUILD_OPTS) -t opa .
	cd peps; docker build $(DOCKER_BUILD_OPTS) -t peps .
	cd solr; docker build $(DOCKER_BUILD_OPTS) -t solr .
	cp domain smtpin/
	cd smtpin; docker build $(DOCKER_BUILD_OPTS) -t smtpin .
	cp domain smtpout/
	cd smtpout; docker build $(DOCKER_BUILD_OPTS) -t smtpout .

data_init:
	mkdir -p $(SOLR_DATA)/peps_mail $(SOLR_DATA)/peps_file $(SOLR_DATA)/peps_user $(SOLR_DATA)/peps_contact
	mkdir -p $(MONGO_DATA)
	mkdir -p $(PEPS_ETC)

run: data_init install_cert
	$(DOCKER_DAEMON) --name peps_mongod -v $(MONGO_DATA):/data/db:rw mongod
	$(DOCKER_DAEMON) --name peps_solr -v $(SOLR_DATA):/solr_data:rw solr
	$(DOCKER_DAEMON) --name peps_server -p $(HTTPS_PORT):$(HTTPS_PORT) -v $(PEPS_ETC):/etc/peps:ro --link=peps_mongod:mongod --link=peps_solr:solr peps
	$(DOCKER_DAEMON) --name peps_smtpin -p $(SMTP_PORT):$(SMTP_PORT) --link peps_server:peps smtpin
	$(DOCKER_DAEMON) --name peps_smtpout -p $(SMTPS_PORT):$(SMTPS_PORT) --link peps_server:peps smtpout
	@echo Now open your browser and log in to https://$(HOSTNAME) to set up the admin password

start:
	docker start peps_mongod peps_solr peps_smtpout peps_server peps_smtpin

stop:
	docker stop peps_smtpin peps_server peps_mongod peps_solr peps_smtpout

kill:
	docker kill peps_smtpin peps_server peps_mongod peps_solr peps_smtpout

rm:
	docker rm peps_smtpin peps_server peps_mongod peps_solr peps_smtpout